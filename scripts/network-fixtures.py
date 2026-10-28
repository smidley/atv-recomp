#!/usr/bin/env python3
"""Loopback-only RomM API contract + SMB2 fixture. All ROM bytes are synthetic."""
import argparse
import json
import pathlib
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

from impacket import smbserver
from impacket.ntlm import compute_lmhash, compute_nthash

ROM = bytes([0x80, 0x37, 0x12, 0x40]) + bytes(i % 251 for i in range(4, 256 * 1024))
TOKEN = "fixture-token"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    trap_hits = 0

    def log_message(self, *_args):
        pass  # Never log Authorization headers or request URLs.

    def send(self, status, payload, content_type="application/json"):
        if not isinstance(payload, bytes):
            payload = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        url = urlsplit(self.path)
        path = url.path
        if path == "/health":
            return self.send(200, {"ready": True})
        if path == "/trap":
            Handler.trap_hits += 1
            return self.send(200, {})
        if path == "/trap-count":
            return self.send(200, {"hits": Handler.trap_hits})
        if self.headers.get("Authorization") != "Bearer " + TOKEN:
            return self.send(401, {})
        if path.startswith("/unauthorized/"):
            return self.send(403, {})
        if path.startswith("/redirect/"):
            self.send_response(302)
            self.send_header("Location", f"http://localhost:{self.server.server_port}/trap")
            self.send_header("Content-Length", "0")
            return self.end_headers()
        if path == "/oversized":
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(64 * 1024 * 1024 + 1))
            self.end_headers()
            try:
                self.wfile.write(bytes(4096))
            except (BrokenPipeError, ConnectionResetError):
                return
            self.wfile.flush()
            # Let the client process the advertised length before closing an incomplete body.
            time.sleep(2)
            self.close_connection = True
            return
        if path == "/chunked":
            self.send_response(200)
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            try:
                self.wfile.write(b"100\r\n" + bytes(256) + b"\r\n0\r\n\r\n")
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if path == "/slow":
            self.send_response(200)
            self.send_header("Content-Length", str(len(ROM)))
            self.end_headers()
            try:
                for offset in range(0, len(ROM), 1024):
                    self.wfile.write(ROM[offset:offset + 1024])
                    self.wfile.flush()
                    time.sleep(0.02)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if path == "/api/roms":
            query = parse_qs(url.query)
            offset = int(query.get("offset", ["0"])[0])
            return self.send(200, {"items": [{"id": 3 + offset, "name": "Synthetic Ocarina fixture",
                                            "fs_name": "Fixture", "platform_display_name": "Nintendo 64"}],
                                   "total": 2, "offset": offset, "limit": 50})
        if path == "/api/roms/3":
            return self.send(200, {"id": 3, "files": [
                {"id": 11, "file_name": "Fixture.z64", "file_size_bytes": len(ROM)},
                {"id": 12, "file_name": "Archive.zip", "file_size_bytes": 100},
            ]})
        if path == "/api/roms/11/files/content/Fixture.z64":
            return self.send(200, ROM, "application/octet-stream")
        return self.send(404, {})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--http-port", type=int, default=18080)
    parser.add_argument("--smb-port", type=int, default=1445)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="recomptv-fixtures-") as temp:
        root = pathlib.Path(temp)
        (root / "Fixture.z64").write_bytes(ROM)
        (root / "Notes.txt").write_text("Not a ROM")
        (root / "N64").mkdir()
        swapped = b"".join(ROM[i:i + 2][::-1] for i in range(0, len(ROM), 2))
        (root / "N64" / "Fixture.v64").write_bytes(swapped)
        smb = smbserver.SimpleSMBServer(listenAddress="127.0.0.1", listenPort=args.smb_port)
        smb.addShare("GAMES", str(root), "Synthetic test data")
        smb.setSMB2Support(True)
        smb.addCredential("player", 0, compute_lmhash("fixture-password"), compute_nthash("fixture-password"))
        threading.Thread(target=smb.start, daemon=True).start()
        ThreadingHTTPServer(("127.0.0.1", args.http_port), Handler).serve_forever()


if __name__ == "__main__":
    main()
