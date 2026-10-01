#!/usr/bin/env python3
"""Tiny "echo headers" origin app (Python standard library only).

Every request (any method, any path) gets back ALL the HTTP request headers it
sent, in the response body. Default output is pretty-printed JSON; add
`?format=text` (or send `Accept: text/plain`) to get one "Name: value" per line.

The app binds to 127.0.0.1 only: it is reachable exclusively through nginx
(public 443 with mTLS/Authenticated Origin Pulls, or the loopback 8443
listener used by cloudflared). It never listens on a public interface.

/secure and /secure/* intentionally return 404 here: that path is served by a
Cloudflare Worker behind Cloudflare Access, never by the origin.
"""
import json
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

HOST = os.environ.get("APP_HOST", "127.0.0.1")
PORT = int(os.environ.get("APP_PORT", "8080"))


class HeadersHandler(BaseHTTPRequestHandler):
    server_version = "cf-assessment-headers/1.0"
    sys_version = ""  # do not advertise the Python version

    def _respond(self) -> None:
        url = urlsplit(self.path)
        if url.path == "/secure" or url.path.startswith("/secure/"):
            self._send(404, "text/plain; charset=utf-8", b"Not found at origin (served by the Worker)\n")
            return

        # Keep the headers exactly as received (order and duplicates preserved).
        headers = [[name, value] for name, value in self.headers.items()]
        want_text = parse_qs(url.query).get("format", [""])[0] == "text" or (
            "text/plain" in self.headers.get("Accept", "") and "json" not in self.headers.get("Accept", "")
        )

        # JSON view: duplicate header names are joined with ", " (RFC 9110 5.3).
        merged: dict = {}
        for n, v in headers:
            merged[n] = f"{merged[n]}, {v}" if n in merged else v

        if want_text:
            lines = [f"{self.command} {self.path} {self.request_version}"]
            lines += [f"{n}: {v}" for n, v in headers]
            body = ("\n".join(lines) + "\n").encode()
            ctype = "text/plain; charset=utf-8"
        else:
            payload = {
                "method": self.command,
                "path": self.path,
                "http_version": self.request_version,
                "received_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "header_count": len(headers),
                "headers": merged,
            }
            body = (json.dumps(payload, indent=2, ensure_ascii=False) + "\n").encode()
            ctype = "application/json; charset=utf-8"
        self._send(200, ctype, body)

    def _send(self, status: int, ctype: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    # Answer every common method the same way.
    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = do_HEAD = _respond

    def log_message(self, fmt, *args):  # journald adds its own timestamp
        print(f"{self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), HeadersHandler).serve_forever()
