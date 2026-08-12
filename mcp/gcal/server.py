#!/usr/bin/env python3
"""Google Calendar MCP — read-only agent tools for engineer-brain sync.

Generic, plug-and-play calendar signal: `sync` (and any skill/command) can
call today_sync()/upcoming_sync() to include hackathons, demos, meetups, and
workshops that are invisible to git/gh — without coupling to team-brain or any
tracker key. No write scope: this server can only read events.

Thin wrapper around core/scripts/gcal_lib.py so the CLI (gcal.sh) and this
MCP server share one auth/config implementation (no duplicated logic).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from mcp.server.fastmcp import FastMCP

# gcal_lib.py lives in core/scripts/, two levels up from mcp/gcal/server.py.
_REPO_ROOT = Path(__file__).resolve().parents[2]
_SCRIPTS_DIR = _REPO_ROOT / "core" / "scripts"
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

import gcal_lib  # noqa: E402  (path must be extended first)

mcp = FastMCP(
    "gcal",
    instructions=(
        "Google Calendar (read-only) for engineer-brain sync. "
        "For standup, prefer today_sync() / upcoming_sync() — they return only "
        "task-related or active-participation events (hackathon, demo, meetup, "
        "workshop). Routine ceremonies (syncs, retros, 1:1s, bug reviews) are filtered "
        "out. Raw today()/upcoming() return the full calendar. "
        "If status() reports configured=false, tell the user to run the one-time "
        "CLI setup (see authorize_instructions()). Read-only: no create/edit/delete."
    ),
)


def _handle(fn, *args, **kwargs) -> str:
    try:
        result = fn(*args, **kwargs)
    except gcal_lib.GCalError as exc:
        return json.dumps({"error": str(exc), "configured": False}, indent=2)
    return json.dumps(result, indent=2)


@mcp.tool()
def status() -> str:
    """Show Google Calendar config status (credentials path, calendar id). No secrets returned."""
    return json.dumps(gcal_lib.status(), indent=2)


@mcp.tool()
def authorize_instructions() -> str:
    """Return the one-time manual setup steps (this server has no write/browser access).

    Call this when status().configured is false, then relay the steps to the user.
    """
    return (
        "One-time setup (read-only calendar.readonly scope):\n"
        "1. Google Cloud Console -> APIs & Services -> Credentials -> Create OAuth "
        "client ID -> Application type: Desktop app. Download the JSON.\n"
        "2. Run: bash core/scripts/gcal.sh authorize --client-secrets /path/to/client_secret.json\n"
        "   (opens a browser once, then stores a refresh token locally)\n"
        "3. Re-check with the status tool — configured should now be true."
    )


@mcp.tool()
def list_calendars() -> str:
    """List calendars visible to the authorized account (id, summary, primary, access role)."""
    def _run():
        creds = gcal_lib.load_credentials()
        return gcal_lib.list_calendars(creds)

    return _handle(_run)


@mcp.tool()
def today(calendar_id: str = "") -> str:
    """Return all of today's events (local timezone). For standup, use today_sync() instead."""
    def _run():
        creds = gcal_lib.load_credentials()
        start, end = gcal_lib.today_range()
        return gcal_lib.fetch_events(creds, start, end, calendar_id)

    return _handle(_run)


@mcp.tool()
def today_sync(calendar_id: str = "") -> str:
    """Today's standup-worthy events only — hackathons, demos, meetups, workshops.

    Excludes routine ceremonies: syncs, retros, 1:1s, bug reviews, drop-in sessions.
    """
    def _run():
        creds = gcal_lib.load_credentials()
        start, end = gcal_lib.today_range()
        events = gcal_lib.fetch_events(creds, start, end, calendar_id)
        return gcal_lib.filter_sync_events(events)

    return _handle(_run)


@mcp.tool()
def upcoming(days: int = 7, calendar_id: str = "") -> str:
    """Return all events for the next N days (default 7). For standup, use upcoming_sync()."""
    def _run():
        creds = gcal_lib.load_credentials()
        start, end = gcal_lib.upcoming_range(max(1, int(days)))
        return gcal_lib.fetch_events(creds, start, end, calendar_id)

    return _handle(_run)


@mcp.tool()
def upcoming_sync(days: int = 7, calendar_id: str = "") -> str:
    """Standup-worthy events for the next N days — same filter as today_sync()."""
    def _run():
        creds = gcal_lib.load_credentials()
        start, end = gcal_lib.upcoming_range(max(1, int(days)))
        events = gcal_lib.fetch_events(creds, start, end, calendar_id)
        return gcal_lib.filter_sync_events(events)

    return _handle(_run)


@mcp.tool()
def events_range(since: str, until: str, calendar_id: str = "") -> str:
    """Return events between two dates (YYYY-MM-DD or ISO8601), e.g. for a Monday-covers-Friday scan."""
    def _run():
        creds = gcal_lib.load_credentials()
        start = gcal_lib.parse_date_arg(since)
        end = gcal_lib.parse_date_arg(until)
        return gcal_lib.fetch_events(creds, start, end, calendar_id)

    return _handle(_run)


def main() -> None:
    # stdio transport for Cursor / Claude Code MCP
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
