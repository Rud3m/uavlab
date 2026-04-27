#!/usr/bin/env python3
"""
Run from the lab/ directory:  python3 serve.py
Or specify a port:             python3 serve.py 9000
"""
import http.server
import socketserver
import webbrowser
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

os.chdir(os.path.dirname(os.path.abspath(__file__)))

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

print(f"[*] Lab UI → http://localhost:{PORT}")
print(f"[*] Ctrl+C to stop\n")

with socketserver.TCPServer(("", PORT), QuietHandler) as httpd:
    webbrowser.open(f"http://localhost:{PORT}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Stopped.")
