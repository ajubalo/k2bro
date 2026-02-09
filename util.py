# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "httpx",
#     "python-dotenv",
# ]
# ///

import subprocess
import sys
import re
from pathlib import Path

import httpx
from dotenv import dotenv_values

API_BASE = "https://keep2share.cc/api/v2"
TOKEN_FILE = Path.home() / "Library/Containers/com.example.flutte/Data/Documents/.token"
ENV_FILE = Path(".env")


def load_token() -> str | None:
    if TOKEN_FILE.exists():
        token = TOKEN_FILE.read_text().strip()
        if token:
            return token
    return None


def login() -> str:
    env = dotenv_values(ENV_FILE)
    username = env.get("USER")
    password = env.get("PASS")
    if not username or not password:
        print("Error: USER and PASS must be set in .env", file=sys.stderr)
        sys.exit(1)

    # Step 1: initial login request with username and password
    resp = httpx.post(f"{API_BASE}/login", json={"username": username, "password": password})
    data = resp.json()

    if data.get("status") == "success":
        token = data["auth_token"]
        TOKEN_FILE.write_text(token)
        print(f"Logged in, token saved to {TOKEN_FILE}")
        return token

    # If ReCaptcha is required, request a captcha challenge
    if data.get("errorCode") == 33:
        resp = httpx.post(f"{API_BASE}/requestReCaptcha")
        captcha_data = resp.json()
        if captcha_data.get("status") != "success":
            print(f"Failed to request captcha: {captcha_data}", file=sys.stderr)
            sys.exit(1)

        challenge = captcha_data["challenge"]
        captcha_url = captcha_data["captcha_url"]
        print(f"ReCaptcha required. Open this URL in your browser:")
        print(f"  {captcha_url}")
        response = input("Enter the captcha response: ").strip()

        # Step 2: retry login with captcha challenge and response
        resp = httpx.post(f"{API_BASE}/login", json={
            "username": username,
            "password": password,
            "re_captcha_challenge": challenge,
            "re_captcha_response": response,
        })
        data = resp.json()
        if data.get("status") != "success":
            print(f"Login failed: {data}", file=sys.stderr)
            sys.exit(1)

        token = data["auth_token"]
        TOKEN_FILE.write_text(token)
        print(f"Logged in, token saved to {TOKEN_FILE}")
        return token

    print(f"Login failed: {data}", file=sys.stderr)
    sys.exit(1)


def get_token() -> str:
    token = load_token()
    if token:
        return token
    return login()


def get_download_url(url: str) -> str:
    file_id = extract_file_id(url)
    token = get_token()

    resp = httpx.post(f"{API_BASE}/getUrl", json={"file_id": file_id, "auth_token": token})
    data = resp.json()
    if data.get("status") != "success":
        print(f"getUrl failed: {data}", file=sys.stderr)
        sys.exit(1)

    return data["url"]


def extract_file_id(url: str) -> str:
    match = re.match(r"https://k2s\.cc/file/([^/]+)", url)
    if not match:
        print(f"Error: invalid URL format: {url}", file=sys.stderr)
        print("Expected: https://k2s.cc/file/<file_id>/...", file=sys.stderr)
        sys.exit(1)
    return match.group(1)


def cmd_info(url: str) -> None:
    file_id = extract_file_id(url)
    payload: dict = {"ids": [file_id], "extended_info": True}
    token = load_token()
    if token:
        payload["auth_token"] = token
    resp = httpx.post(f"{API_BASE}/getFilesInfo", json=payload)
    data = resp.json()
    if data.get("status") != "success":
        print(f"getFilesInfo failed: {data}", file=sys.stderr)
        sys.exit(1)

    files = data.get("files", [])
    if not files:
        print("File not found", file=sys.stderr)
        sys.exit(1)

    info = files[0]
    print(f"id:            {info.get('id')}")
    print(f"name:          {info.get('name')}")
    print(f"size:          {info.get('size')}")
    print(f"is_available:  {info.get('is_available')}")
    print(f"is_free:       {info.get('isAvailableForFree')}")
    print(f"access:        {info.get('access')}")
    ext = info.get("extended_info", {})
    if ext:
        print(f"storage:       {ext.get('storage_object')}")
        print(f"content_type:  {ext.get('content_type')}")
        vi = ext.get("video_info")
        if vi:
            print(f"duration:      {vi.get('duration')}s")
            print(f"resolution:    {vi.get('width')}x{vi.get('height')}")
            print(f"streamable:    {vi.get('is_streamable')}")


def cmd_link(url: str) -> None:
    print(get_download_url(url))


def cmd_vlc(url: str) -> None:
    download_url = get_download_url(url)
    print(download_url)
    subprocess.run(["open", "-a", "VLC", download_url])


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: uv run util.py <command> [args...]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  login       - authenticate and save token", file=sys.stderr)
        print("  info <url>  - get file info", file=sys.stderr)
        print("  link <url>  - get download URL for a k2s.cc link", file=sys.stderr)
        print("  vlc <url>   - get download URL and open in VLC", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "login":
        login()
    elif command == "info":
        if len(sys.argv) < 3:
            print("Usage: uv run util.py info <url>", file=sys.stderr)
            sys.exit(1)
        cmd_info(sys.argv[2])
    elif command == "link":
        if len(sys.argv) < 3:
            print("Usage: uv run util.py link <url>", file=sys.stderr)
            sys.exit(1)
        cmd_link(sys.argv[2])
    elif command == "vlc":
        if len(sys.argv) < 3:
            print("Usage: uv run util.py vlc <url>", file=sys.stderr)
            sys.exit(1)
        cmd_vlc(sys.argv[2])
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
