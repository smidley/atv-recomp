"""Loopback RomM 5.4 save API fixture. No ROMs, real credentials or live server."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from email.parser import BytesParser
from email.policy import default
from pathlib import Path
import json
import sys

records = []
mode = "normal"
redirected = 0
deletes = 0


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, status, data):
        body = data if isinstance(data, bytes) else json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def route(self):
        global redirected
        if self.path.startswith("/foreign"):
            redirected += 1
            self.reply(500, {})
            return False
        if self.headers.get("Authorization") != "Bearer test-token":
            self.reply(401, {})
            return False
        if mode in ("offline", "denied"):
            self.reply(503 if mode == "offline" else 403, {"detail": "private server diagnostic MUST NOT be exposed"})
            return False
        if mode == "redirect":
            self.send_response(307)
            self.send_header("Location", "/foreign")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return False
        return True

    def do_GET(self):
        global mode
        parsed = urlparse(self.path)
        if parsed.path == "/mode":
            mode = parse_qs(parsed.query)["value"][0]
            return self.reply(200, {})
        if parsed.path == "/stats":
            return self.reply(200, {"uploads": len(records), "redirected": redirected, "deletes": deletes})
        if not self.route():
            return
        if parsed.path == "/romm/api/saves":
            assert parse_qs(parsed.query) == {"rom_id": ["42"]}
            rows = [{k: v for k, v in row.items() if k != "body"} for row in records]
            for change in ({"rom_id": 99}, {"emulator": "emulatorjs"}, {"slot": "recomptv-../../escape"}, {"missing_from_fs": True}):
                rows.append({"id": 999, "rom_id": 42, "emulator": "recomptv-shipwright-9.3.1", "slot": "recomptv-file1", **change})
            return self.reply(200, rows)
        if parsed.path.startswith("/romm/api/saves/") and parsed.path.endswith("/content"):
            if mode == "oversize":
                return self.reply(200, b"x" * (4 * 1024 * 1024 + 1))
            if mode == "bad-save":
                return self.reply(200, {"version": 999})
            save_id = int(parsed.path.split("/")[-2])
            return self.reply(200, next(row["body"] for row in records if row["id"] == save_id))
        self.reply(404, {})

    def do_POST(self):
        data = self.rfile.read(int(self.headers["Content-Length"]))
        if not self.route():
            return
        parsed = urlparse(self.path)
        assert parsed.path == "/romm/api/saves"
        query = parse_qs(parsed.query)
        assert query["overwrite"] == ["false"] and query["autocleanup"] == ["false"]
        message = BytesParser(policy=default).parsebytes(("Content-Type: " + self.headers["Content-Type"] + "\r\n\r\n").encode() + data)
        part, = list(message.iter_parts())
        assert part.get_param("name", header="content-disposition") == "saveFile"
        assert part.get_filename().endswith(".sav")
        record = {"id": len(records) + 1, "rom_id": int(query["rom_id"][0]),
                  "slot": query["slot"][0], "emulator": query["emulator"][0],
                  "created_at": "2026-10-28T12:00:00Z", "body": part.get_payload(decode=True)}
        assert json.loads(record["body"])["version"] == 1
        records.append(record)
        self.reply(201, {k: v for k, v in record.items() if k != "body"})

    def do_DELETE(self):
        global deletes
        deletes += 1
        self.reply(500, {})


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
