import base64
import http.client
import json
import sqlite3
import socket
import ssl
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import spacefind


JPEG = b"\xff\xd8\xff\xd9"


class RunningServer:
    def __init__(self, data_dir, host="127.0.0.1"):
        options = {"port": 0, "host_name": "localhost"}
        if host is not None:
            options["host"] = host
        self.server = spacefind.create_server(data_dir, **options)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.context = ssl._create_unverified_context()

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, method, path, body=None, token=None, host="127.0.0.1"):
        data = None if body is None else json.dumps(body).encode()
        headers = {"Content-Type": "application/json"} if data is not None else {}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        url_host = f"[{host}]" if ":" in host else host
        request = urllib.request.Request(
            f"https://{url_host}:{self.server.server_port}{path}",
            data=data, headers=headers, method=method
        )
        try:
            response = urllib.request.urlopen(
                request, context=self.context, timeout=5
            )
        except urllib.error.HTTPError as error:
            status, raw = error.code, error.read()
            error.close()
        else:
            status, raw = response.status, response.read()
            response.close()
        return status, json.loads(raw) if raw else None


class SpaceFindTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.data_dir = Path(self.temp.name) / "data"
        self.running = RunningServer(self.data_dir)

    def tearDown(self):
        self.running.close()
        self.temp.cleanup()

    def join(self, running=None, invite=None):
        running = running or self.running
        if invite is None:
            invite = json.loads(running.server.pairing)["invite"]
        status, result = running.request("POST", "/join", {"invite": invite})
        self.assertEqual(status, 200)
        return result["token"]

    def create_item(self, token, item_id=None, change_id=None):
        item_id = item_id or str(uuid.uuid4())
        change_id = change_id or str(uuid.uuid4())
        change = {
            "id": change_id,
            "itemID": item_id,
            "kind": "create",
            "label": "Wrench",
            "description": "12 mm",
            "location": "Tool drawer",
            "photo": base64.b64encode(JPEG).decode(),
        }
        status, result = self.running.request("POST", "/changes", change, token)
        self.assertEqual((status, result), (200, {}))
        return item_id, change_id, change

    def inventory(self, running=None, token=None):
        status, result = (running or self.running).request(
            "GET", "/inventory", token=token
        )
        self.assertEqual(status, 200)
        return result["items"]

    def snapshot(self, running=None, token=None):
        status, result = (running or self.running).request(
            "GET", "/inventory", token=token
        )
        self.assertEqual(status, 200)
        return result

    def report_missing(self, token, name="Torque wrench", location="beside the workbench", photo=None,
                       report_id=None, change_id=None):
        change = {
            "id": change_id or str(uuid.uuid4()),
            "itemID": report_id or str(uuid.uuid4()),
            "kind": "reportMissing",
            "label": name,
            "location": location,
        }
        if photo is not None:
            change["photo"] = base64.b64encode(photo).decode()
        status, result = self.running.request("POST", "/changes", change, token)
        self.assertEqual((status, result), (200, {}))
        return change

    def reports(self, item_id, running=None, token=None):
        item = next(item for item in self.inventory(running, token) if item["id"] == item_id)
        return {report["id"]: report for report in item["reports"]}

    def move(self, token, item_id, parent_id, location):
        change = {
            "id": str(uuid.uuid4()),
            "itemID": item_id,
            "kind": "move",
            "parentID": parent_id,
            "location": location,
            "photo": base64.b64encode(b"\xff\xd8" + location.encode() + b"\xff\xd9").decode(),
        }
        status, result = self.running.request("POST", "/changes", change, token)
        self.assertEqual((status, result), (200, {}))
        return change["id"]

    def test_rejects_wrong_invite_and_unauthenticated_inventory_access(self):
        self.assertEqual(self.running.request("POST", "/join", {"invite": "wrong"})[0], 403)
        self.assertEqual(self.running.request("GET", "/inventory")[0], 401)
        self.assertEqual(
            self.running.request("POST", "/changes", {})[0], 401
        )
        token = self.join()
        self.assertEqual(self.inventory(token=token), [])

    def test_create_replay_and_restart_preserve_photo_and_location(self):
        invite = json.loads(self.running.server.pairing)["invite"]
        token = self.join()
        item_id, _, change = self.create_item(token)
        self.assertEqual(self.running.request("POST", "/changes", change, token), (200, {}))

        self.running.close()
        self.running = RunningServer(self.data_dir)
        self.assertEqual(json.loads(self.running.server.pairing)["invite"], invite)
        items = self.inventory(self.running, token)
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["id"], item_id)
        self.assertEqual(items[0]["reports"][0]["location"], "Tool drawer")
        self.assertEqual(
            base64.b64decode(items[0]["reports"][0]["photo"]), JPEG
        )

    def test_rename_changes_only_target_label_and_retries_do_not_overwrite_newer_rename(self):
        client_a = self.join()
        client_b = self.join()
        target_id, _, _ = self.create_item(client_a)
        other_id, _, _ = self.create_item(client_b)
        before = {item["id"]: item for item in self.inventory(token=client_a)}
        self.assertEqual(before[target_id]["label"], "Wrench")
        self.assertEqual(before[other_id]["label"], "Wrench")

        older_rename = {
            "id": str(uuid.uuid4()),
            "itemID": target_id,
            "kind": "rename",
            "label": "Pipe wrench",
        }
        newer_rename = {
            "id": str(uuid.uuid4()),
            "itemID": target_id,
            "kind": "rename",
            "label": "Spanner",
        }
        self.assertEqual(self.running.request("POST", "/changes", older_rename, client_a), (200, {}))
        self.assertEqual(self.running.request("POST", "/changes", newer_rename, client_b), (200, {}))

        after = {item["id"]: item for item in self.inventory(token=client_a)}
        self.assertEqual(after[target_id]["label"], "Spanner")
        self.assertEqual(after[target_id]["description"], before[target_id]["description"])
        self.assertEqual(after[target_id]["reports"], before[target_id]["reports"])
        self.assertEqual(after[other_id], before[other_id])

        self.assertEqual(self.running.request("POST", "/changes", older_rename, client_a), (200, {}))
        replayed = {item["id"]: item for item in self.inventory(token=client_b)}
        self.assertEqual(replayed[target_id]["label"], "Spanner")

    def test_rename_rejects_whitespace_only_label(self):
        token = self.join()
        item_id, _, _ = self.create_item(token)
        rename = {
            "id": str(uuid.uuid4()),
            "itemID": item_id,
            "kind": "rename",
            "label": "   \t",
        }

        self.assertEqual(
            self.running.request("POST", "/changes", rename, token),
            (400, {"error": "label is required"}),
        )

    def test_rename_rejects_unknown_item(self):
        token = self.join()
        rename = {
            "id": str(uuid.uuid4()),
            "itemID": str(uuid.uuid4()),
            "kind": "rename",
            "label": "Spanner",
        }

        self.assertEqual(
            self.running.request("POST", "/changes", rename, token),
            (400, {"error": "unknown item"}),
        )

    def test_two_clients_keep_concurrent_moves_and_allow_branch_updates(self):
        client_a = self.join()
        client_b = self.join()
        for first, second in ((client_a, client_b), (client_b, client_a)):
            item_id, root_id, _ = self.create_item(first)
            first_move = self.move(first, item_id, root_id, "Shelf A")
            second_move = self.move(second, item_id, root_id, "Shelf B")
            self.assertEqual(set(self.reports(item_id, token=first)), {first_move, second_move})

            first_tip = self.move(first, item_id, first_move, "Shelf A2")
            self.assertEqual(set(self.reports(item_id, token=first)), {first_tip, second_move})

            confirm = {
                "id": str(uuid.uuid4()),
                "itemID": item_id,
                "kind": "confirm",
                "observedIDs": [first_tip, second_move],
                "chosenID": second_move,
            }
            self.assertEqual(self.running.request("POST", "/changes", confirm, first), (200, {}))
            self.assertEqual(set(self.reports(item_id, token=first)), {second_move})

            delayed_move = self.move(first, item_id, first_tip, "Shelf A3")
            self.assertEqual(set(self.reports(item_id, token=first)), {second_move, delayed_move})

    def test_stale_confirmation_returns_conflict_without_dropping_reports(self):
        client_a = self.join()
        client_b = self.join()
        item_id, root_id, _ = self.create_item(client_a)
        move_a = self.move(client_a, item_id, root_id, "Shelf A")
        move_b = self.move(client_b, item_id, root_id, "Shelf B")
        stale_confirmation = {
            "id": str(uuid.uuid4()),
            "itemID": item_id,
            "kind": "confirm",
            "observedIDs": [move_a, move_b],
            "chosenID": move_a,
        }

        move_a2 = self.move(client_a, item_id, move_a, "Shelf A2")
        before = self.reports(item_id, token=client_a)
        self.assertEqual(set(before), {move_a2, move_b})
        status, _ = self.running.request(
            "POST", "/changes", stale_confirmation, client_b
        )
        self.assertEqual(status, 409)
        self.assertEqual(set(self.reports(item_id, token=client_a)), set(before))

    def test_normalizes_uuid_fields_and_reuses_private_server_identity(self):
        token = self.join()
        item_id = str(uuid.uuid4())
        change_id = str(uuid.uuid4())
        change = {
            "id": change_id.upper(),
            "itemID": item_id.upper(),
            "kind": "create",
            "label": "Wrench",
            "description": "",
            "location": "Bench",
            "photo": base64.b64encode(JPEG).decode(),
        }
        self.assertEqual(self.running.request("POST", "/changes", change, token), (200, {}))
        first_pairing = json.loads(self.running.server.pairing)
        self.assertTrue(first_pairing["invite"])
        self.assertEqual(len(first_pairing["fingerprint"]), 64)
        self.assertEqual(self.inventory(token=token)[0]["id"], item_id)

        self.running.close()
        self.running = RunningServer(self.data_dir)
        second_pairing = json.loads(self.running.server.pairing)
        self.assertEqual(second_pairing["invite"], first_pairing["invite"])
        self.assertEqual(second_pairing["fingerprint"], first_pairing["fingerprint"])

    def test_rejects_blank_required_fields_and_oversized_photo(self):
        token = self.join()
        item_id = str(uuid.uuid4())
        blank = {
            "id": str(uuid.uuid4()),
            "itemID": item_id,
            "kind": "create",
            "label": "  ",
            "description": "",
            "location": "Shelf",
            "photo": base64.b64encode(JPEG).decode(),
        }
        self.assertEqual(self.running.request("POST", "/changes", blank, token)[0], 400)

        oversized = dict(blank, id=str(uuid.uuid4()), label="Wrench")
        oversized["photo"] = base64.b64encode(b"\xff\xd8" + b"x" * (2 * 1024 * 1024) + b"\xff\xd9").decode()
        self.assertEqual(self.running.request("POST", "/changes", oversized, token)[0], 400)

        malformed = dict(blank, id=str(uuid.uuid4()), kind=[])
        self.assertEqual(self.running.request("POST", "/changes", malformed, token)[0], 400)

    def test_lost_report_lifecycle_and_replay(self):
        client_a = self.join()
        client_b = self.join()
        self.create_item(client_a)
        original_items = self.inventory(token=client_a)
        jpeg = b"\xff\xd8\xffcrew-photo\xff\xd9"
        first = self.report_missing(client_a, photo=jpeg)
        sibling = self.report_missing(client_b)
        close = {
            "id": str(uuid.uuid4()),
            "itemID": first["itemID"],
            "kind": "markFound",
            "location": "locker 2",
        }
        self.assertEqual(self.running.request("POST", "/changes", close, client_b), (200, {}))

        snapshot = self.snapshot(token=client_a)
        self.assertEqual(snapshot["items"], original_items)
        lost = {report["id"]: report for report in snapshot["lostReports"]}
        self.assertEqual(
            (lost[first["itemID"]]["lastSeen"], lost[first["itemID"]]["foundAt"]),
            ("beside the workbench", "locker 2"),
        )
        self.assertEqual(base64.b64decode(lost[first["itemID"]]["photo"]), jpeg)
        self.assertEqual(
            lost[sibling["itemID"]],
            {"id": sibling["itemID"], "name": "Torque wrench", "lastSeen": "beside the workbench"},
        )
        self.assertEqual(self.running.request("POST", "/changes", first, client_a), (200, {}))
        self.assertEqual(self.running.request("POST", "/changes", close, client_b), (200, {}))

    def test_first_closure_wins(self):
        client_a = self.join()
        client_b = self.join()
        report = self.report_missing(client_a, photo=None)
        first_close = {
            "id": str(uuid.uuid4()), "itemID": report["itemID"],
            "kind": "markFound", "location": "locker 2",
        }
        second_close = {
            "id": str(uuid.uuid4()), "itemID": report["itemID"],
            "kind": "markFound", "location": "loading bay",
        }
        with ThreadPoolExecutor(max_workers=2) as pool:
            requests = [pool.submit(self.running.request, "POST", "/changes", change, client)
                        for change, client in [(first_close, client_a), (second_close, client_b)]]
            results = [request.result() for request in requests]
        self.assertCountEqual([status for status, _ in results], [200, 409])
        winner = (first_close, second_close)[results.index((200, {}))]
        self.assertIn((409, {"code": "alreadyFound", "foundAt": winner["location"]}), results)
        self.assertEqual(
            {entry["id"]: entry for entry in self.snapshot(token=client_b)["lostReports"]}[report["itemID"]]["foundAt"],
            winner["location"],
        )
        self.assertEqual(self.running.request("POST", "/changes", winner, client_a), (200, {}))
        altered_replay = dict(winner, location="different locker")
        status, body = self.running.request("POST", "/changes", altered_replay, client_a)
        self.assertEqual(status, 409)
        self.assertNotIn("code", body)

    def test_lost_report_validation_and_authorization(self):
        token = self.join()
        report_id = str(uuid.uuid4())
        valid = {
            "id": str(uuid.uuid4()), "itemID": report_id, "kind": "reportMissing",
            "label": "Torque wrench", "location": "Bench",
        }
        self.assertEqual(self.running.request("POST", "/changes", valid)[0], 401)
        self.assertEqual(self.running.request("GET", "/inventory")[0], 401)

        unknown = {
            "id": str(uuid.uuid4()), "itemID": str(uuid.uuid4()),
            "kind": "markFound", "location": "Locker",
        }
        self.assertEqual(self.running.request("POST", "/changes", unknown, token)[0], 400)
        blank_name = dict(valid, id=str(uuid.uuid4()), label=" \t")
        blank_location = dict(valid, id=str(uuid.uuid4()), location="  ")
        self.assertEqual(self.running.request("POST", "/changes", blank_name, token)[0], 400)
        self.assertEqual(self.running.request("POST", "/changes", blank_location, token)[0], 400)

        report = self.report_missing(token)
        blank_found_at = {
            "id": str(uuid.uuid4()), "itemID": report["itemID"],
            "kind": "markFound", "location": " \n",
        }
        self.assertEqual(self.running.request("POST", "/changes", blank_found_at, token)[0], 400)
        malformed_photo = dict(valid, id=str(uuid.uuid4()), itemID=str(uuid.uuid4()), photo="not base64!")
        self.assertEqual(self.running.request("POST", "/changes", malformed_photo, token)[0], 400)
        oversized_photo = dict(valid, id=str(uuid.uuid4()), itemID=str(uuid.uuid4()))
        oversized_photo["photo"] = base64.b64encode(
            b"\xff\xd8" + b"x" * (2 * 1024 * 1024) + b"\xff\xd9"
        ).decode()
        self.assertEqual(self.running.request("POST", "/changes", oversized_photo, token)[0], 400)
        self.assertNotIn(report["itemID"], {entry["id"] for entry in self.snapshot(token=token)["lostReports"] if "foundAt" in entry})

    def test_lost_report_ids_do_not_collide_with_inventory_or_change_ids(self):
        token = self.join()
        item_id, change_id, _ = self.create_item(token)
        for field, reserved_id in (("itemID", item_id), ("itemID", change_id), ("id", item_id), ("id", change_id)):
            collision = {
                "id": str(uuid.uuid4()), "itemID": str(uuid.uuid4()), "kind": "reportMissing",
                "label": "Torque wrench", "location": "Bench",
            }
            collision[field] = reserved_id
            self.assertEqual(self.running.request("POST", "/changes", collision, token)[0], 409)

        report_id = str(uuid.uuid4())
        same_id = {
            "id": report_id, "itemID": report_id, "kind": "reportMissing",
            "label": "Torque wrench", "location": "Bench",
        }
        self.assertEqual(self.running.request("POST", "/changes", same_id, token)[0], 409)
        report = self.report_missing(token)
        self.assertEqual(
            self.running.request(
                "POST", "/changes",
                dict(report, id=str(uuid.uuid4()), label="Different search"), token,
            )[0],
            409,
        )
        inventory_id_collision = {
            "id": str(uuid.uuid4()), "itemID": report["itemID"], "kind": "create",
            "label": "Torque wrench", "description": "", "location": "Bench",
            "photo": base64.b64encode(JPEG).decode(),
        }
        self.assertEqual(self.running.request("POST", "/changes", inventory_id_collision, token)[0], 409)
        change_id_collision = {
            "id": report["itemID"], "itemID": str(uuid.uuid4()), "kind": "markFound",
            "location": "Locker",
        }
        self.assertEqual(self.running.request("POST", "/changes", change_id_collision, token)[0], 409)

    def test_upgrade_and_restart_preserve_inventory_and_lost_reports(self):
        token = self.join()
        item_id, _, _ = self.create_item(token)
        invite = json.loads(self.running.server.pairing)["invite"]
        self.running.close()
        with sqlite3.connect(self.data_dir / "spacefind.sqlite3") as db:
            db.execute("DROP TABLE IF EXISTS lost_reports")
        self.running = RunningServer(self.data_dir)
        self.assertEqual(json.loads(self.running.server.pairing)["invite"], invite)
        original = self.inventory(self.running, token)[0]
        self.assertEqual(original["id"], item_id)
        self.assertEqual(base64.b64decode(original["reports"][0]["photo"]), JPEG)

        report = self.report_missing(token, name="Torque wrench", photo=JPEG)
        self.running.close()
        self.running = RunningServer(self.data_dir)
        snapshot = self.snapshot(self.running, token)
        self.assertEqual(snapshot["items"], [original])
        self.assertEqual(snapshot["lostReports"], [{
            "id": report["itemID"], "name": "Torque wrench",
            "lastSeen": "beside the workbench", "photo": base64.b64encode(JPEG).decode(),
        }])

    def test_does_not_replace_an_incomplete_tls_identity(self):
        cert_path = self.data_dir / "server-cert.pem"
        key_path = self.data_dir / "server-key.pem"
        cert_before = cert_path.read_bytes()
        key_path.unlink()
        with self.assertRaisesRegex(RuntimeError, "incomplete TLS identity"):
            spacefind.create_server(self.data_dir, host="127.0.0.1", port=0, host_name="localhost")
        self.assertEqual(cert_path.read_bytes(), cert_before)
        self.assertFalse(key_path.exists())

    def test_default_server_accepts_https_over_ipv4_and_ipv6_loopback(self):
        supports_dual_stack = socket.has_dualstack_ipv6()
        running = RunningServer(self.data_dir / "default", host=None)
        try:
            hosts = ["127.0.0.1"] + (["::1"] if supports_dual_stack else [])
            for host in hosts:
                self.assertEqual(running.request("GET", "/missing", host=host)[0], 404)
        finally:
            running.close()

    def test_explicit_ipv4_wildcard_does_not_enable_ipv6(self):
        if not socket.has_dualstack_ipv6():
            self.skipTest("platform does not support dual-stack IPv6")
        running = RunningServer(self.data_dir / "ipv4", host="0.0.0.0")
        try:
            self.assertEqual(running.request("GET", "/missing")[0], 404)

            connection = http.client.HTTPSConnection(
                "::1", running.server.server_port, context=running.context, timeout=5
            )
            try:
                with self.assertRaises(ConnectionRefusedError):
                    connection.connect()
            finally:
                connection.close()
        finally:
            running.close()

    def test_rejects_request_over_three_mebibytes(self):
        token = self.join()
        connection = http.client.HTTPSConnection(
            "127.0.0.1", self.running.server.server_port, context=self.running.context, timeout=5
        )
        connection.putrequest("POST", "/changes")
        connection.putheader("Content-Type", "application/json")
        connection.putheader("Authorization", f"Bearer {token}")
        connection.putheader("Content-Length", str(3 * 1024 * 1024 + 1))
        connection.endheaders()
        response = connection.getresponse()
        self.assertEqual(response.status, 413)
        response.read()
        connection.close()


if __name__ == "__main__":
    unittest.main()
