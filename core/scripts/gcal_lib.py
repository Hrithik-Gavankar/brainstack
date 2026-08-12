#!/usr/bin/env python3
"""Engineer Brain — Google Calendar integration (read-only).

Generic, plug-and-play Google Calendar client used by:
  - core/scripts/gcal.sh   (CLI, mirrors jira.sh conventions)
  - mcp/gcal/server.py     (MCP tools for agent-native sync)

Zero third-party dependencies — stdlib only (urllib, http.server for the
one-time OAuth loopback flow). Read-only scope by design (calendar.readonly):
this tool never creates, edits, or deletes calendar events.

Auth model (OAuth 2.0 "installed app" / loopback flow):
  1. One-time manual step: create a Google Cloud OAuth Client ID (Desktop app),
     download the client secrets JSON, then run:
       python3 gcal_lib.py authorize --client-secrets /path/to/client_secret.json
     This opens a browser, captures the redirect on 127.0.0.1, exchanges the
     code for a refresh token, and writes a local credentials file.
  2. After that, every command silently refreshes a short-lived access token
     from the stored refresh token — no further browser interaction.

Credential file resolution (first match wins):
  1. $GCAL_CREDENTIALS_PATH
  2. ./.gcal/credentials.json   (per-workspace)
  3. ~/.config/engineer-brain/gcal/credentials.json   (per-user, default)

Calendar id resolution: $GCAL_CALENDAR_ID > credentials.json "calendar_id" > "primary".
"""

from __future__ import annotations

import argparse
import http.server
import json
import os
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from datetime import datetime, timedelta
from pathlib import Path

SCOPE = "https://www.googleapis.com/auth/calendar.readonly"
DEFAULT_TOKEN_URI = "https://oauth2.googleapis.com/token"
DEFAULT_AUTH_URI = "https://accounts.google.com/o/oauth2/v2/auth"
CALENDAR_API_BASE = "https://www.googleapis.com/calendar/v3"
TOKEN_REFRESH_SKEW_SEC = 60


class GCalError(RuntimeError):
    """User-facing configuration or API error (message is safe to print)."""


# ---------------------------------------------------------------------------
# Config resolution
# ---------------------------------------------------------------------------

def default_credentials_path() -> Path:
    return Path.home() / ".config" / "engineer-brain" / "gcal" / "credentials.json"


def credentials_path() -> Path:
    env = os.environ.get("GCAL_CREDENTIALS_PATH", "").strip()
    if env:
        return Path(env).expanduser()
    workspace_path = Path.cwd() / ".gcal" / "credentials.json"
    if workspace_path.is_file():
        return workspace_path
    return default_credentials_path()


def token_cache_path(cred_path: Path) -> Path:
    return cred_path.with_suffix(cred_path.suffix + ".token_cache.json")


def load_credentials() -> dict:
    path = credentials_path()
    if not path.is_file():
        raise GCalError(
            f"No Google Calendar credentials found at {path}.\n"
            "Run: python3 gcal_lib.py authorize --client-secrets /path/to/client_secret.json\n"
            "(Download client_secret.json from Google Cloud Console — OAuth Client ID, Desktop app.)"
        )
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise GCalError(f"Credentials file at {path} is not valid JSON: {exc}") from exc
    for field in ("client_id", "client_secret", "refresh_token"):
        if not data.get(field):
            raise GCalError(f"Credentials file at {path} is missing '{field}'. Re-run authorize.")
    data["_path"] = str(path)
    return data


def resolved_calendar_id(creds: dict, override: str = "") -> str:
    if override.strip():
        return override.strip()
    env = os.environ.get("GCAL_CALENDAR_ID", "").strip()
    if env:
        return env
    return str(creds.get("calendar_id") or "primary")


# ---------------------------------------------------------------------------
# HTTP helpers (stdlib only)
# ---------------------------------------------------------------------------

def _http_post_form(url: str, fields: dict, timeout: int = 20) -> dict:
    body = urllib.parse.urlencode(fields).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise GCalError(f"Token request failed ({exc.code}): {detail}") from exc
    except urllib.error.URLError as exc:
        raise GCalError(f"Network error contacting {url}: {exc.reason}") from exc


def _http_get_json(url: str, access_token: str, timeout: int = 20) -> dict:
    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", f"Bearer {access_token}")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise GCalError(f"Calendar API request failed ({exc.code}): {detail}") from exc
    except urllib.error.URLError as exc:
        raise GCalError(f"Network error contacting Calendar API: {exc.reason}") from exc


# ---------------------------------------------------------------------------
# Access token (cached, auto-refreshed)
# ---------------------------------------------------------------------------

def get_access_token(creds: dict) -> str:
    cred_path = Path(creds["_path"])
    cache_path = token_cache_path(cred_path)
    now = time.time()

    if cache_path.is_file():
        try:
            cached = json.loads(cache_path.read_text(encoding="utf-8"))
            if cached.get("access_token") and cached.get("expires_at", 0) - TOKEN_REFRESH_SKEW_SEC > now:
                return str(cached["access_token"])
        except json.JSONDecodeError:
            pass

    token_uri = creds.get("token_uri") or DEFAULT_TOKEN_URI
    resp = _http_post_form(
        token_uri,
        {
            "client_id": creds["client_id"],
            "client_secret": creds["client_secret"],
            "refresh_token": creds["refresh_token"],
            "grant_type": "refresh_token",
        },
    )
    access_token = resp.get("access_token")
    if not access_token:
        raise GCalError(f"Token refresh did not return an access_token: {resp}")
    expires_in = int(resp.get("expires_in", 3600))
    cache_path.write_text(
        json.dumps({"access_token": access_token, "expires_at": now + expires_in}),
        encoding="utf-8",
    )
    try:
        os.chmod(cache_path, 0o600)
    except OSError:
        pass
    return str(access_token)


# ---------------------------------------------------------------------------
# Calendar API
# ---------------------------------------------------------------------------

def list_calendars(creds: dict) -> list[dict]:
    token = get_access_token(creds)
    data = _http_get_json(f"{CALENDAR_API_BASE}/users/me/calendarList", token)
    items = data.get("items", [])
    return [
        {
            "id": item.get("id"),
            "summary": item.get("summary"),
            "primary": bool(item.get("primary", False)),
            "access_role": item.get("accessRole"),
        }
        for item in items
    ]


def fetch_events(
    creds: dict,
    time_min: str,
    time_max: str,
    calendar_id: str = "",
    max_results: int = 50,
) -> list[dict]:
    token = get_access_token(creds)
    cal_id = resolved_calendar_id(creds, calendar_id)
    params = {
        "timeMin": time_min,
        "timeMax": time_max,
        "singleEvents": "true",
        "orderBy": "startTime",
        "maxResults": str(max_results),
    }
    url = f"{CALENDAR_API_BASE}/calendars/{urllib.parse.quote(cal_id, safe='')}/events?" + urllib.parse.urlencode(params)
    data = _http_get_json(url, token)
    events = []
    for item in data.get("items", []):
        if item.get("status") == "cancelled":
            continue
        start = item.get("start", {})
        end = item.get("end", {})
        events.append(
            {
                "id": item.get("id"),
                "summary": item.get("summary", "(no title)"),
                "start": start.get("dateTime") or start.get("date"),
                "end": end.get("dateTime") or end.get("date"),
                "all_day": "date" in start and "dateTime" not in start,
                "location": item.get("location", ""),
                "html_link": item.get("htmlLink", ""),
                "status": item.get("status", ""),
            }
        )
    return events


# ---------------------------------------------------------------------------
# Date range helpers (local timezone day boundaries, RFC3339 for the API)
# ---------------------------------------------------------------------------

def _local_day_bounds(d: datetime) -> tuple[str, str]:
    start = d.replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=1)
    return start.astimezone().isoformat(), end.astimezone().isoformat()


def today_range() -> tuple[str, str]:
    return _local_day_bounds(datetime.now())


def upcoming_range(days: int) -> tuple[str, str]:
    now = datetime.now()
    start, _ = _local_day_bounds(now)
    _, end = _local_day_bounds(now + timedelta(days=max(0, days - 1)))
    return start, end


def parse_date_arg(value: str) -> str:
    """Accept YYYY-MM-DD or a full ISO8601 timestamp; return RFC3339 for the API."""
    value = value.strip()
    try:
        if len(value) == 10:
            dt = datetime.strptime(value, "%Y-%m-%d")
            return dt.astimezone().isoformat()
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return dt.isoformat()
    except ValueError as exc:
        raise GCalError(f"Invalid date '{value}' — expected YYYY-MM-DD or ISO8601") from exc


# ---------------------------------------------------------------------------
# One-time OAuth loopback authorization flow
# ---------------------------------------------------------------------------

_CALLBACK_PATH = "/oauth2callback"


class _CallbackHandler(http.server.BaseHTTPRequestHandler):
    """Handles exactly the OAuth redirect; ignores everything else (e.g. favicon
    prefetch) so a stray unrelated request can't be mistaken for an auth error.
    """

    result: dict = {}

    def do_GET(self) -> None:  # noqa: N802 (stdlib signature)
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != _CALLBACK_PATH:
            self.send_response(404)
            self.end_headers()
            return
        params = urllib.parse.parse_qs(parsed.query)
        if "code" in params:
            _CallbackHandler.result["code"] = params["code"][0]
            message = "Authorization complete. You can close this tab and return to the terminal."
        else:
            _CallbackHandler.result["error"] = params.get("error", ["unknown_error"])[0]
            message = "Authorization failed. Check the terminal for details."
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(message.encode("utf-8"))

    def log_message(self, format: str, *args) -> None:  # noqa: A002 (silence default logging)
        pass


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _serve_until_result(server: http.server.HTTPServer, deadline: float) -> None:
    """Handle requests until the callback path is hit or the deadline passes.

    Uses a short per-request timeout so unrelated requests (e.g. a browser's
    favicon fetch) don't consume the single "real" callback and get
    misinterpreted as an auth error.
    """
    server.timeout = 1.0
    while time.time() < deadline and not _CallbackHandler.result:
        server.handle_request()


def authorize(client_secrets_path: str, calendar_id: str, out_path: str = "") -> Path:
    secrets_file = Path(client_secrets_path).expanduser()
    if not secrets_file.is_file():
        raise GCalError(f"client secrets file not found: {secrets_file}")
    raw = json.loads(secrets_file.read_text(encoding="utf-8"))
    section = raw.get("installed") or raw.get("web")
    if not section:
        raise GCalError("client secrets file must contain an 'installed' or 'web' section")
    client_id = section["client_id"]
    client_secret = section["client_secret"]
    auth_uri = section.get("auth_uri", DEFAULT_AUTH_URI)
    token_uri = section.get("token_uri", DEFAULT_TOKEN_URI)

    port = _free_port()
    redirect_uri = f"http://127.0.0.1:{port}{_CALLBACK_PATH}"
    _CallbackHandler.result = {}
    server = http.server.HTTPServer(("127.0.0.1", port), _CallbackHandler)
    deadline = time.time() + 180
    server_thread = threading.Thread(
        target=_serve_until_result, args=(server, deadline), daemon=True
    )
    server_thread.start()

    auth_params = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": SCOPE,
        "access_type": "offline",
        "prompt": "consent",
    }
    url = f"{auth_uri}?{urllib.parse.urlencode(auth_params)}"
    print("Open this URL to authorize Engineer Brain to read your Google Calendar:")
    print(url)
    webbrowser.open(url)

    server_thread.join(timeout=185)
    server.server_close()
    if "error" in _CallbackHandler.result:
        raise GCalError(f"Google returned an error: {_CallbackHandler.result['error']}")
    code = _CallbackHandler.result.get("code")
    if not code:
        raise GCalError("Timed out waiting for authorization redirect (180s). Try again.")

    token_resp = _http_post_form(
        token_uri,
        {
            "client_id": client_id,
            "client_secret": client_secret,
            "code": code,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
        },
    )
    refresh_token = token_resp.get("refresh_token")
    if not refresh_token:
        raise GCalError(
            "Google did not return a refresh_token. Revoke prior access at "
            "https://myaccount.google.com/permissions and re-run authorize."
        )

    out = Path(out_path).expanduser() if out_path else default_credentials_path()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps(
            {
                "auth_type": "oauth",
                "client_id": client_id,
                "client_secret": client_secret,
                "refresh_token": refresh_token,
                "token_uri": token_uri,
                "calendar_id": calendar_id or "primary",
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    try:
        os.chmod(out, 0o600)
    except OSError:
        pass
    return out


# ---------------------------------------------------------------------------
# Status (no secrets)
# ---------------------------------------------------------------------------

def status() -> dict:
    path = credentials_path()
    configured = path.is_file()
    result = {
        "configured": configured,
        "credentials_path": str(path),
    }
    if not configured:
        result["hint"] = (
            "Run: python3 gcal_lib.py authorize --client-secrets /path/to/client_secret.json"
        )
        return result
    try:
        creds = load_credentials()
    except GCalError as exc:
        result["configured"] = False
        result["error"] = str(exc)
        return result
    result["calendar_id"] = resolved_calendar_id(creds)
    cache_path = token_cache_path(path)
    if cache_path.is_file():
        try:
            cache = json.loads(cache_path.read_text(encoding="utf-8"))
            result["access_token_expires_in_sec"] = max(0, int(cache.get("expires_at", 0) - time.time()))
        except json.JSONDecodeError:
            pass
    return result


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _print(data, as_json: bool, text_fmt) -> None:
    if as_json:
        print(json.dumps(data, indent=2))
    else:
        print(text_fmt(data))


def _format_status(data: dict) -> str:
    if not data.get("configured"):
        lines = ["configured: false", f"credentials_path: {data.get('credentials_path', '')}"]
        if data.get("error"):
            lines.append(f"error: {data['error']}")
        if data.get("hint"):
            lines.append(f"hint: {data['hint']}")
        return "\n".join(lines)
    lines = [
        "configured: true",
        f"credentials_path: {data.get('credentials_path', '')}",
        f"calendar_id: {data.get('calendar_id', '')}",
    ]
    if "access_token_expires_in_sec" in data:
        lines.append(f"access_token_expires_in_sec: {data['access_token_expires_in_sec']}")
    return "\n".join(lines)


def _format_events(events: list[dict]) -> str:
    if not events:
        return "No events found."
    lines = []
    for ev in events:
        when = ev["start"][:16].replace("T", " ") if ev.get("start") else "?"
        marker = "[all day]" if ev.get("all_day") else when
        lines.append(f"- {marker}  {ev['summary']}" + (f"  ({ev['location']})" if ev.get("location") else ""))
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Engineer Brain — Google Calendar (read-only)")
    sub = parser.add_subparsers(dest="command", required=True)

    p_auth = sub.add_parser("authorize", help="One-time OAuth setup (opens a browser)")
    p_auth.add_argument("--client-secrets", required=True, help="Path to Google OAuth client_secret.json")
    p_auth.add_argument("--calendar-id", default="primary", help="Default calendar id to store (default: primary)")
    p_auth.add_argument("--out", default="", help="Where to write credentials.json (default: ~/.config/engineer-brain/gcal/credentials.json)")

    sub.add_parser("status", help="Show config status (no secrets)")
    sub.add_parser("calendars", help="List calendars visible to this account")

    p_today = sub.add_parser("today", help="Events for today")
    p_today.add_argument("--calendar-id", default="")

    p_upcoming = sub.add_parser("upcoming", help="Events for the next N days (default 7)")
    p_upcoming.add_argument("days", nargs="?", type=int, default=7)
    p_upcoming.add_argument("--calendar-id", default="")

    p_range = sub.add_parser("range", help="Events between two dates (YYYY-MM-DD or ISO8601)")
    p_range.add_argument("since")
    p_range.add_argument("until")
    p_range.add_argument("--calendar-id", default="")

    for sp in (sub.choices["status"], sub.choices["calendars"], p_today, p_upcoming, p_range):
        sp.add_argument("--json", action="store_true", help="Output machine-readable JSON")

    args = parser.parse_args(argv)

    try:
        if args.command == "authorize":
            out = authorize(args.client_secrets, args.calendar_id, args.out)
            print(f"Saved credentials to {out}")
            print("You're set — run: python3 gcal_lib.py today")
            return 0

        if args.command == "status":
            _print(status(), args.json, _format_status)
            return 0

        creds = load_credentials()

        if args.command == "calendars":
            cals = list_calendars(creds)
            _print(
                cals,
                args.json,
                lambda d: "\n".join(f"- {c['id']}  ({c['summary']})" for c in d) or "No calendars found.",
            )
            return 0

        if args.command == "today":
            start, end = today_range()
            events = fetch_events(creds, start, end, args.calendar_id)
            _print(events, args.json, _format_events)
            return 0

        if args.command == "upcoming":
            start, end = upcoming_range(args.days)
            events = fetch_events(creds, start, end, args.calendar_id)
            _print(events, args.json, _format_events)
            return 0

        if args.command == "range":
            start = parse_date_arg(args.since)
            end = parse_date_arg(args.until)
            events = fetch_events(creds, start, end, args.calendar_id)
            _print(events, args.json, _format_events)
            return 0

    except GCalError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    parser.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
