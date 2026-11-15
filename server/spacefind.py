#!/usr/bin/env python3
import argparse
import base64
import binascii
import hashlib
import hmac
import ipaddress
import json
import logging
import os
import re
import secrets
import sqlite3
import ssl
import subprocess
import tempfile
import uuid
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


MAX_PHOTO = 2 * 1024 * 1024
MAX_REQUEST = 3 * 1024 * 1024


class HTTPProblem(Exception):
    def __init__(self, status, message):
        self.status = status
        self.message = message


def _uuid(value):
    if not isinstance(value, str):
        raise HTTPProblem(400, "invalid UUID")
    try:
        return str(uuid.UUID(value))
    except ValueError as error:
        raise HTTPProblem(400, "invalid UUID") from error


def _nonblank(value, field):
    if not isinstance(value, str) or not value.strip():
        raise HTTPProblem(400, f"{field} is required")
    return value


def _photo(value):
    if not isinstance(value, str):
        raise HTTPProblem(400, "photo is required")
    try:
        photo = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as error:
        raise HTTPProblem(400, "photo must be base64 JPEG data") from error
    if not photo or len(photo) > MAX_PHOTO:
        raise HTTPProblem(400, "photo must be at most 2 MiB")
    if not photo.startswith(b"\xff\xd8") or not photo.endswith(b"\xff\xd9"):
        raise HTTPProblem(400, "photo must be JPEG data")
    return photo


def _normalize_change(body):
    if not isinstance(body, dict):
        raise HTTPProblem(400, "change must be an object")
    kind = body.get("kind")
    if not isinstance(kind, str):
        raise HTTPProblem(400, "invalid change")
    fields = {
        "create": {"id", "itemID", "kind", "label", "description", "location", "photo"},
        "move": {"id", "itemID", "kind", "parentID", "location", "photo"},
        "confirm": {"id", "itemID", "kind", "observedIDs", "chosenID"},
    }.get(kind)
    if fields is None or set(body) - fields:
        raise HTTPProblem(400, "invalid change")
    if fields - set(body) - ({"description"} if kind == "create" else set()):
        raise HTTPProblem(400, "invalid change")
    change = {"id": _uuid(body["id"]), "itemID": _uuid(body["itemID"]), "kind": kind}
    if kind == "create":
        change.update(
            label=_nonblank(body["label"], "label"),
            description=body.get("description", ""),
            location=_nonblank(body["location"], "location"),
            photo=_photo(body["photo"]),
        )
        if not isinstance(change["description"], str):
            raise HTTPProblem(400, "description must be text")
    elif kind == "move":
        change.update(
            parentID=_uuid(body["parentID"]),
            location=_nonblank(body["location"], "location"),
            photo=_photo(body["photo"]),
        )
    else:
        observed = body["observedIDs"]
        if not isinstance(observed, list) or not observed:
            raise HTTPProblem(400, "observedIDs must be a nonempty array")
        observed = [_uuid(value) for value in observed]
        if len(set(observed)) != len(observed):
            raise HTTPProblem(400, "observedIDs must be unique")
        chosen = _uuid(body["chosenID"])
        if chosen not in observed:
            raise HTTPProblem(400, "chosenID must be observed")
        change.update(observedIDs=sorted(observed), chosenID=chosen)
    if kind != "confirm":
        change["photo"] = base64.b64encode(change["photo"]).decode("ascii")
    return change


def _payload_hash(change):
    raw = json.dumps(change, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def _connect(db_path):
    db = sqlite3.connect(db_path, timeout=10, isolation_level=None)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    db.execute("PRAGMA secure_delete = ON")
    return db


def _initialize_db(db_path, invite):
    with closing(_connect(db_path)) as db:
        db.executescript(
            """
            CREATE TABLE IF NOT EXISTS meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS devices (
                token_hash TEXT PRIMARY KEY
            );
            CREATE TABLE IF NOT EXISTS items (
                id TEXT PRIMARY KEY,
                label TEXT NOT NULL,
                description TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS reports (
                id TEXT PRIMARY KEY,
                item_id TEXT NOT NULL REFERENCES items(id),
                parent_id TEXT REFERENCES reports(id),
                location TEXT,
                photo BLOB,
                active INTEGER NOT NULL CHECK (active IN (0, 1))
            );
            CREATE INDEX IF NOT EXISTS reports_current
                ON reports(item_id, active);
            CREATE TABLE IF NOT EXISTS changes (
                id TEXT PRIMARY KEY,
                payload_hash TEXT NOT NULL
            );
            """
        )
        invite_hash = hashlib.sha256(invite.encode()).hexdigest()
        db.execute("BEGIN IMMEDIATE")
        stored = db.execute("SELECT value FROM meta WHERE key='invite_hash'").fetchone()
        if stored is None:
            db.execute("INSERT INTO meta(key, value) VALUES('invite_hash', ?)", (invite_hash,))
        elif not hmac.compare_digest(stored["value"], invite_hash):
            raise RuntimeError("invite file does not match the database")
        db.commit()
    os.chmod(db_path, 0o600)


def _read_or_create_invite(data_dir):
    path = data_dir / "invite"
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        invite = path.read_text("utf-8").strip()
        if not invite:
            raise RuntimeError("invite file is empty")
        os.chmod(path, 0o600)
        return invite
    invite = secrets.token_urlsafe(32)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write(invite + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    return invite


def _host_identity(host_name):
    if not isinstance(host_name, str) or not host_name or len(host_name) > 253:
        raise ValueError("host name must be a DNS name or IP address")
    try:
        address = ipaddress.ip_address(host_name)
    except ValueError:
        labels = host_name.rstrip(".").split(".")
        if any(
            not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label)
            for label in labels
        ):
            raise ValueError("host name must be a DNS name or IP address")
        return "DNS", host_name
    return "IP", str(address)


def _ensure_certificate(data_dir, host_name):
    san_type, san_value = _host_identity(host_name)
    cert_path = data_dir / "server-cert.pem"
    key_path = data_dir / "server-key.pem"
    if cert_path.exists() != key_path.exists():
        raise RuntimeError("incomplete TLS identity; restore both server certificate files")
    if not cert_path.exists():
        with tempfile.TemporaryDirectory(dir=data_dir) as temporary:
            temporary = Path(temporary)
            temporary_cert = temporary / "cert.pem"
            temporary_key = temporary / "key.pem"
            config = temporary / "openssl.cnf"
            config.write_text(
                f"[req]\nprompt = no\ndistinguished_name = dn\n"
                f"x509_extensions = v3_req\n[dn]\nCN = {host_name}\n"
                f"[v3_req]\nsubjectAltName = {san_type}:{san_value}\n",
                encoding="ascii",
            )
            subprocess.run(
                [
                    "openssl", "req", "-x509", "-newkey", "rsa:2048", "-sha256",
                    "-days", "3650", "-nodes", "-keyout", str(temporary_key),
                    "-out", str(temporary_cert), "-config", str(config),
                    "-extensions", "v3_req",
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            os.chmod(temporary_key, 0o600)
            os.replace(temporary_cert, cert_path)
            os.replace(temporary_key, key_path)
    os.chmod(cert_path, 0o600)
    os.chmod(key_path, 0o600)
    der = ssl.PEM_cert_to_DER_cert(cert_path.read_text("ascii"))
    return cert_path, key_path, hashlib.sha256(der).hexdigest()


def _normalized_url_host(host_name):
    try:
        address = ipaddress.ip_address(host_name)
    except ValueError:
        return host_name
    return f"[{address}]" if address.version == 6 else str(address)


def _change(db_path, body):
    change = _normalize_change(body)
    digest = _payload_hash(change)
    db = _connect(db_path)
    try:
        db.execute("BEGIN IMMEDIATE")
        accepted = db.execute(
            "SELECT payload_hash FROM changes WHERE id=?", (change["id"],)
        ).fetchone()
        if accepted is not None:
            if not hmac.compare_digest(accepted["payload_hash"], digest):
                raise HTTPProblem(409, "change ID already used")
            db.commit()
            return

        collision = db.execute(
            "SELECT 1 FROM items WHERE id=? UNION SELECT 1 FROM reports WHERE id=?",
            (change["id"], change["id"]),
        ).fetchone()
        if collision:
            raise HTTPProblem(409, "change ID already used")

        item_id = change["itemID"]
        if change["kind"] == "create":
            if item_id == change["id"] or db.execute(
                "SELECT 1 FROM items WHERE id=? UNION SELECT 1 FROM reports WHERE id=? "
                "UNION SELECT 1 FROM changes WHERE id=?",
                (item_id, item_id, item_id),
            ).fetchone():
                raise HTTPProblem(409, "item ID already used")
            db.execute(
                "INSERT INTO items(id, label, description) VALUES(?, ?, ?)",
                (item_id, change["label"], change["description"]),
            )
            parent_id = None
            location, photo = change["location"], base64.b64decode(change["photo"])
        else:
            if not db.execute("SELECT 1 FROM items WHERE id=?", (item_id,)).fetchone():
                raise HTTPProblem(400, "unknown item")
            if change["kind"] == "move":
                parent_id = change["parentID"]
                parent = db.execute(
                    "SELECT item_id, active FROM reports WHERE id=?", (parent_id,)
                ).fetchone()
                if parent is None or parent["item_id"] != item_id:
                    raise HTTPProblem(400, "parent report does not belong to item")
                if parent["active"]:
                    db.execute(
                        "UPDATE reports SET active=0, location=NULL, photo=NULL WHERE id=?",
                        (parent_id,),
                    )
                location, photo = change["location"], base64.b64decode(change["photo"])
            else:
                parent_id = None
                location = photo = None
                for report_id in change["observedIDs"]:
                    report = db.execute(
                        "SELECT item_id FROM reports WHERE id=?", (report_id,)
                    ).fetchone()
                    if report is None or report["item_id"] != item_id:
                        raise HTTPProblem(400, "observed report does not belong to item")
                current = {
                    row["id"]
                    for row in db.execute(
                        "SELECT id FROM reports WHERE item_id=? AND active=1", (item_id,)
                    )
                }
                if current != set(change["observedIDs"]):
                    raise HTTPProblem(409, "candidate reports changed")
                db.execute(
                    "UPDATE reports SET active=0, location=NULL, photo=NULL "
                    "WHERE item_id=? AND active=1 AND id<>?",
                    (item_id, change["chosenID"]),
                )

        if change["kind"] != "confirm":
            db.execute(
                "INSERT INTO reports(id, item_id, parent_id, location, photo, active) "
                "VALUES(?, ?, ?, ?, ?, 1)",
                (change["id"], item_id, parent_id, location, photo),
            )
        db.execute(
            "INSERT INTO changes(id, payload_hash) VALUES(?, ?)",
            (change["id"], digest),
        )
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _handler(db_path, invite):
    invite_hash = hashlib.sha256(invite.encode()).hexdigest()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

        def _json(self, status, value):
            data = json.dumps(value, separators=(",", ":")).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def _body(self):
            if not self.headers.get("Content-Type", "").lower().startswith("application/json"):
                raise HTTPProblem(415, "content type must be application/json")
            try:
                length = int(self.headers.get("Content-Length", ""))
            except ValueError as error:
                raise HTTPProblem(400, "invalid content length") from error
            if length < 0:
                raise HTTPProblem(400, "invalid content length")
            if length > MAX_REQUEST:
                raise HTTPProblem(413, "request exceeds 3 MiB")
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise HTTPProblem(400, "incomplete request")
            try:
                return json.loads(raw)
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise HTTPProblem(400, "invalid JSON") from error

        def _authorized(self):
            scheme, separator, token = self.headers.get("Authorization", "").partition(" ")
            if not separator or scheme.lower() != "bearer" or not token or token.strip() != token:
                return False
            token_hash = hashlib.sha256(token.encode()).hexdigest()
            with closing(_connect(db_path)) as db:
                return db.execute(
                    "SELECT 1 FROM devices WHERE token_hash=?", (token_hash,)
                ).fetchone() is not None

        def do_POST(self):
            try:
                if self.path == "/join":
                    body = self._body()
                    supplied = body.get("invite") if isinstance(body, dict) else None
                    if not isinstance(supplied, str) or not hmac.compare_digest(
                        hashlib.sha256(supplied.encode()).hexdigest(), invite_hash
                    ):
                        raise HTTPProblem(403, "invalid invite")
                    token = secrets.token_urlsafe(32)
                    with closing(_connect(db_path)) as db:
                        db.execute("INSERT INTO devices(token_hash) VALUES(?)", (
                            hashlib.sha256(token.encode()).hexdigest(),
                        ))
                    self._json(200, {"token": token})
                elif self.path == "/changes":
                    if not self._authorized():
                        self.close_connection = True
                        raise HTTPProblem(401, "authentication required")
                    body = self._body()
                    _change(db_path, body)
                    self._json(200, {})
                else:
                    raise HTTPProblem(404, "not found")
            except HTTPProblem as error:
                self._json(error.status, {"error": error.message})
            except Exception:
                logging.exception("SpaceFind request failed")
                self._json(500, {"error": "internal error"})

        def do_GET(self):
            try:
                if self.path != "/inventory":
                    raise HTTPProblem(404, "not found")
                if not self._authorized():
                    self.close_connection = True
                    raise HTTPProblem(401, "authentication required")
                with closing(_connect(db_path)) as db:
                    db.execute("BEGIN")
                    items = []
                    for item in db.execute("SELECT id, label, description FROM items ORDER BY id"):
                        reports = [
                            {
                                "id": report["id"],
                                "location": report["location"],
                                "photo": base64.b64encode(report["photo"]).decode("ascii"),
                            }
                            for report in db.execute(
                                "SELECT id, location, photo FROM reports "
                                "WHERE item_id=? AND active=1 ORDER BY id",
                                (item["id"],),
                            )
                        ]
                        items.append({
                            "id": item["id"],
                            "label": item["label"],
                            "description": item["description"],
                            "reports": reports,
                        })
                    db.commit()
                self._json(200, {"items": items})
            except HTTPProblem as error:
                self._json(error.status, {"error": error.message})
            except Exception:
                logging.exception("SpaceFind request failed")
                self._json(500, {"error": "internal error"})

    return Handler


def create_server(data_dir, host="0.0.0.0", port=8443, host_name="localhost"):
    data_dir = Path(data_dir)
    data_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(data_dir, 0o700)
    invite = _read_or_create_invite(data_dir)
    cert_path, key_path, fingerprint = _ensure_certificate(data_dir, host_name)
    db_path = data_dir / "spacefind.sqlite3"
    _initialize_db(db_path, invite)

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(cert_path, key_path)
    server = ThreadingHTTPServer((host, port), _handler(db_path, invite))
    server.daemon_threads = True
    server.socket = context.wrap_socket(server.socket, server_side=True)
    host_for_url = _normalized_url_host(host_name)
    server.pairing = json.dumps({
        "url": f"https://{host_for_url}:{server.server_port}",
        "fingerprint": fingerprint,
        "invite": invite,
    }, separators=(",", ":"))
    server.db_path = db_path
    return server


def main():
    parser = argparse.ArgumentParser(description="Share a SpaceFind inventory over HTTPS")
    parser.add_argument("--host-name", required=True, help="LAN DNS name or IP in the pairing URL")
    parser.add_argument("--data-dir", required=True, type=Path, help="private directory for TLS identity and inventory")
    parser.add_argument("--port", type=int, default=8443)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("--port must be from 1 to 65535")

    server = create_server(args.data_dir, port=args.port, host_name=args.host_name)
    print(server.pairing, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
