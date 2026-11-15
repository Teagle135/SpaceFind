import base64
import http.client
import json
import socket
import ssl
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
import uuid
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
