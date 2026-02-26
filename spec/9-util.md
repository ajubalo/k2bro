# Utility Script (util.py)

A Python CLI tool run with `uv run util.py <command> [args...]`.

Uses embedded `uv` script dependencies (`httpx`, `python-dotenv`).

## Authentication

- Reads the auth token from `.token` (stored at `$HOME/Library/Containers/com.example.flutte/Data/Documents/.token`).
- If the token is missing, reads `USER` and `PASS` from `.env` and performs login:
  1. Request a ReCaptcha challenge via `/requestReCaptcha`, show the captcha URL to the user, and read the response.
  2. POST to `/login` with username, password, challenge, and response.
- API reference: https://keep2share.github.io/api/#resources:/login:post

## Commands

### `login`

Execute the authentication flow and save the token.

### `link <url>`

Expects a URL in format `https://k2s.cc/file/<id>/<filename>`.

Resolves the download URL using the token and the `/getUrl` API endpoint.

API reference: https://keep2share.github.io/api/#resources:/getUrl:post

### `vlc <url>`

Resolves the download link (same as `link`), prints it, then opens it in VLC.

### `info <url>`

Calls `/getFilesInfo` to retrieve file metadata without requiring authentication.

Returns availability status, file size, video info (duration, resolution, streamability), and other metadata.

### `scan <url>`

Fetch the HTML of the page, find all links matching `https://k2s.cc/file/<id>` or `https://keep2share.cc/file/<id>`, extract the id, invoke the getFilesInfo and show metadata