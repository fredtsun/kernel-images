# /// script
# requires-python = ">=3.10"
# dependencies = ["playwright", "httpx"]
# ///
"""Smoke-drive a dev-local instance: the browser over CDP (:9222) and the
kernel-images REST API (:10001), including a CDP→API handoff.

Usage: uv run scripts/drive.py  (with `make dev-local` running)

NOTE: locally there is no sandbox — /process and /fs endpoints operate on
YOUR machine. In the container they are contained.
"""
import base64

import httpx
from playwright.sync_api import sync_playwright

API = "http://localhost:10001"
CDP = "http://localhost:9222"
DEMO_FILE = "/tmp/kernel-dev-demo.png"

api = httpx.Client(base_url=API, timeout=10)

print("== REST: run a command via /process/exec ==")
r = api.post("/process/exec", json={"command": "uname", "args": ["-a"]})
r.raise_for_status()
result = r.json()
print(f"exit={result['exit_code']} stdout={base64.b64decode(result['stdout_b64']).decode().strip()}")

print("\n== CDP: drive the browser ==")
with sync_playwright() as p:
    browser = p.chromium.connect_over_cdp(CDP)
    ctx = browser.contexts[0]
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    page.goto("https://example.com")
    print("title:", page.title())
    shot = page.screenshot()
    print(f"screenshot: {len(shot)} bytes")
    browser.close()  # disconnects; the browser itself stays up

print("\n== CDP→API handoff: store the screenshot via /fs/write_file ==")
r = api.put("/fs/write_file", params={"path": DEMO_FILE}, content=shot)
r.raise_for_status()

r = api.get("/fs/file_info", params={"path": DEMO_FILE})
r.raise_for_status()
info = r.json()
print(f"file_info: {info['path']} {info['size_bytes']}B mode={info['mode']}")

r = api.get("/fs/read_file", params={"path": DEMO_FILE})
r.raise_for_status()
assert r.content == shot, "read-back bytes differ from screenshot!"
print(f"read_file: {len(r.content)} bytes, matches screenshot ✓")
print(f"\nopen {DEMO_FILE} to see what the browser saw")
