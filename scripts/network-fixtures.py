#!/usr/bin/env python3
"""Loopback-only RomM API contract + SMB2 fixture. All ROM bytes are synthetic."""
import argparse
import json
import pathlib
import tempfile
import threading
import time
import struct
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

from impacket import smbserver
from impacket.ntlm import compute_lmhash, compute_nthash

ROM = bytes([0x80, 0x37, 0x12, 0x40]) + bytes(i % 251 for i in range(4, 256 * 1024))
TOKEN = "fixture-token"


def fixture_image(width=600, height=400):
    """A generated color chart, with no remote artwork or copyrighted game data."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    pixels = b"".join(b"\0" + b"".join(bytes((x * 255 // width, y * 255 // height, 110))
                                      for x in range(width)) for y in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))


ART = fixture_image()
# Like RomM's platform icons: one 256x256 PNG inside an .ico directory.
ICON_PNG = fixture_image(256, 256)
ICON = struct.pack("<HHHBBBBHHII", 0, 1, 1, 0, 0, 0, 0, 1, 32, len(ICON_PNG), 22) + ICON_PNG
MEDIA = {"path_cover_small": "/assets/romm/resources/roms/1/3/cover/small.png?ts=2026-10-28",
         "path_cover_large": "/assets/romm/resources/roms/1/3/cover/big.png?ts=2026-10-28",
         "merged_screenshots": ["/assets/romm/resources/roms/1/3/screenshots/0.jpg",
                                "https://outside.invalid/private.jpg"]}


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
        if path.startswith("/art-proxy/"):
            path = path.removeprefix("/art-proxy")
        if path.startswith("/assets/romm/resources/"):
            if path.endswith("/redirect.png"):
                self.send_response(302)
                self.send_header("Location", f"http://localhost:{self.server.server_port}/trap")
                self.send_header("Content-Length", "0")
                return self.end_headers()
            if path.endswith("/login.png"):
                return self.send(200, b"<html>Sign in</html>", "text/html")
            return self.send(200, ART, "image/png")
        if path == "/assets/platforms/n64.ico":
            return self.send(200, ICON, "image/x-icon")
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
            # RomM 5.4.1 sends "files": [] unless with_files=true; ROM 4 omits it like older servers.
            n64 = {"platform_id": 1, "platform_slug": "n64", "platform_display_name": "Nintendo 64"}
            rows = [
                {"id": 3, "name": "Synthetic Ocarina of Time fixture", "fs_name": "Fixture", **n64, "igdb_id": 1,
                 "files": [], **MEDIA},
                {"id": 4, "name": "Mario Kart 64 fixture", "fs_name": "Second", **n64},
                {"id": 5, "name": "Ocarina of Time 3D fixture", "fs_name": "Other", "platform_id": 2,
                 "platform_slug": "3ds", "platform_display_name": "Nintendo 3DS"},
                {"id": 6, "name": "Unsupported N64 fixture", "fs_name": "Third", **n64},
                # A second record for game 3, and a record whose file was deleted from the server.
                {"id": 7, "name": "Synthetic Ocarina of Time fixture", "fs_name": "Fixture (copy)", **n64, "igdb_id": 1},
                {"id": 8, "name": "Mario Kart 64 fixture", "fs_name": "Removed", **n64, "missing_from_fs": True},
                # Paper Mario's metadata aliases contain every word of "Super Mario 64".
                {"id": 9, "name": "Paper Mario fixture", "fs_name": "Paper", **n64, "aliases": ["Super Mario 64 RPG"]},
            ]
            platforms = query.get("platform_ids", [])
            if platforms:
                rows = [row for row in rows if str(row["platform_id"]) in platforms]
            if query.get("missing") == ["false"]:
                rows = [row for row in rows if not row.get("missing_from_fs")]
            # RomM 5.4.1: any "|" alternative whose words all appear in the name, filename or aliases.
            terms = [term.lower().split() for term in query.get("search_term", [""])[0].split("|") if term.strip()]
            if terms:
                rows = [row for row in rows if any(all(word in " ".join([row["name"], row["fs_name"], *row.get("aliases", [])]).lower()
                                                       for word in words) for words in terms)]
            if query.get("group_by_meta_id") == ["true"]:
                # Like RomM, after filtering: one row per metadata ID and platform, first filename wins.
                first = {}
                for row in sorted(rows, key=lambda row: row["fs_name"]):
                    key = ("igdb", row["igdb_id"]) if "igdb_id" in row else ("rom", row["id"])
                    first.setdefault((key, row["platform_id"]), row["id"])
                rows = [row for row in rows if row["id"] in first.values()]
            return self.send(200, {"items": rows[offset:offset + 1], "total": len(rows), "offset": offset, "limit": 50})
        if path == "/api/roms/3":
            return self.send(200, {"id": 3, "name": "Synthetic Ocarina of Time fixture", **MEDIA, "files": [
                {"id": 11, "file_name": "Fixture.z64", "file_size_bytes": len(ROM)},
                {"id": 12, "file_name": "Archive.zip", "file_size_bytes": 100},
            ]})
        if path == "/api/roms/4":
            return self.send(200, {"id": 4, "files": [
                {"id": 13, "file_name": "Second.z64", "file_size_bytes": len(ROM)},
            ]})
        if path == "/api/roms/5":
            return self.send(200, {"id": 5, "files": [
                {"id": 14, "file_name": "Other.3ds", "file_size_bytes": len(ROM)},
            ]})
        if path == "/api/roms/6":
            return self.send(200, {"id": 6, "files": [
                {"id": 15, "file_name": "Third.z64", "file_size_bytes": len(ROM)},
            ]})
        if path == "/api/roms/7":
            return self.send(200, {"id": 7, "files": [
                {"id": 16, "file_name": "Fixture (copy).z64", "file_size_bytes": len(ROM)},
            ]})
        if path == "/api/roms/8":
            return self.send(200, {"id": 8, "files": [
                {"id": 17, "file_name": "Removed.z64", "file_size_bytes": len(ROM)},
            ]})
        if path == "/api/roms/9":
            return self.send(200, {"id": 9, "files": []})
        if path in ["/api/roms/11/files/content/Fixture.z64", "/api/roms/13/files/content/Second.z64"]:
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
