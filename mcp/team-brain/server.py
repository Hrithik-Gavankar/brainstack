#!/usr/bin/env python3
"""Team Brain MCP — agent tools for collaborative initiative memory.

Wraps core/scripts/team-brain-api.sh (Supabase RPCs). Embeddings optional;
recall uses FTS when TEAM_BRAIN_EMBED_PROVIDER is unset.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from mcp.server.fastmcp import FastMCP

mcp = FastMCP(
    "team-brain",
    instructions=(
        "Team Brain = shared AI memory for a crew on one Jira key. "
        "ENTRY: when the user starts team work on a ticket, call start(jira_key) once — "
        "that loads crew memory and enters sync mode (background pull). "
        "While active: call touch each turn; remember findings with source_ref "
        "(identical=no-op; same source_ref+new body=update/merge). "
        "If sync_status mode is sleep, prompt the user to wake before deep research. "
        "Never upload personal BRAIN.md or credentials.json."
    ),
)


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _api_script() -> Path:
    env = os.environ.get("TEAM_BRAIN_API_SCRIPT")
    if env:
        return Path(env)
    candidate = _repo_root() / "core" / "scripts" / "team-brain-api.sh"
    if candidate.is_file():
        return candidate
    raise FileNotFoundError(
        "team-brain-api.sh not found; set TEAM_BRAIN_API_SCRIPT or run from engineer-brain checkout"
    )


def _run(*args: str, timeout: int = 120, stdin_data: str | None = None) -> str:
    script = _api_script()
    env = os.environ.copy()
    # Prefer caller cwd .team-brain unless explicitly set
    if "TEAM_BRAIN_DIR" not in env:
        cwd_tb = Path.cwd() / ".team-brain"
        if cwd_tb.is_dir():
            env["TEAM_BRAIN_DIR"] = str(cwd_tb)
    cmd = ["bash", str(script), *args]
    try:
        proc = subprocess.run(
            cmd,
            input=stdin_data,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"team-brain-api timed out: {' '.join(args)}") from exc
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        raise RuntimeError(err or f"team-brain-api failed ({proc.returncode}): {' '.join(args)}")
    out = (proc.stdout or "").strip()
    # Prefer last JSON object if stderr mixed (script prints hints on stderr)
    return out


def _as_json(raw: str) -> str:
    """Return pretty JSON string for the model; pass through text on parse failure."""
    if not raw:
        return "{}"
    try:
        return json.dumps(json.loads(raw), indent=2)
    except json.JSONDecodeError:
        # Some commands may print multiple JSON docs; take the last object-looking line
        for line in reversed(raw.splitlines()):
            line = line.strip()
            if line.startswith("{") or line.startswith("["):
                try:
                    return json.dumps(json.loads(line), indent=2)
                except json.JSONDecodeError:
                    continue
        return raw


@mcp.tool()
def whoami() -> str:
    """Show the current Team Brain member and team (from credentials.json)."""
    return _as_json(_run("whoami"))


@mcp.tool()
def attach(
    jira_key: str,
    title: str = "",
    status: str = "active",
    jira_url: str = "",
) -> str:
    """Attach a Jira initiative and pull recent shared memories into the local cache.

    Prefer start() when beginning a work session — it attaches if needed and enters sync mode.
    """
    key = jira_key.strip().upper()
    title = title.strip() or key
    args = ["attach", key, title, status or "active"]
    if jira_url.strip():
        args.append(jira_url.strip())
    return _as_json(_run(*args))


@mcp.tool()
def start(
    jira_key: str,
    interval_sec: int = 5,
    idle_hours: float = 1.0,
) -> str:
    """Enter sync mode for a Jira key — the ONE manual/session entrypoint.

    Loads crew memory into cache, starts background merge-safe pull, returns session JSON.
    Call when the user starts team work on a ticket. Summarize memories before researching.
    """
    key = jira_key.strip().upper()
    return _as_json(
        _run(
            "start",
            key,
            str(max(2, int(interval_sec))),
            str(idle_hours),
        )
    )


@mcp.tool()
def stop(jira_key: str = "") -> str:
    """Leave sync mode for a key (or all sessions if jira_key empty)."""
    if jira_key.strip():
        return _as_json(_run("stop", jira_key.strip().upper()))
    return _as_json(_run("stop"))


@mcp.tool()
def wake(jira_key: str) -> str:
    """Resume sync mode after idle sleep."""
    return _as_json(_run("wake", jira_key.strip().upper()))


@mcp.tool()
def touch(jira_key: str) -> str:
    """Mark local activity so sync mode stays awake. Call each turn while working the key.

    If the session is sleeping, wakes it.
    """
    return _as_json(_run("touch", jira_key.strip().upper()))


@mcp.tool()
def sync_status(jira_key: str = "") -> str:
    """Show sync mode: active | sleep | stopped | none. Prompt user if sleep before deep work."""
    if jira_key.strip():
        return _as_json(_run("sync-status", jira_key.strip().upper()))
    return _as_json(_run("sync-status"))


@mcp.tool()
def remember(
    jira_key: str,
    body: str,
    kind: str = "research",
    source_ref: str = "",
) -> str:
    """Save a finding for the crew — call IMMEDIATELY after durable research (do not wait).

    kind: research | decision | note.
    Always pass source_ref (e.g. AAP-81423#cli-schema).
    Identical body → deduped=true. Same source_ref + new body → updated=true (merge).
    """
    key = jira_key.strip().upper()
    kind_n = (kind or "research").strip().lower()
    if kind_n not in ("research", "decision", "note"):
        raise ValueError("kind must be research, decision, or note")
    body = body.strip()
    if not body:
        raise ValueError("body is required")
    # Pass body on stdin ("-") so quotes/newlines/$() are not mangled as shell args
    args = ["remember", key, kind_n]
    if source_ref.strip():
        args.extend(["--source-ref", source_ref.strip()])
    args.append("-")
    return _as_json(_run(*args, stdin_data=body))


@mcp.tool()
def recall(jira_key: str, query: str = "") -> str:
    """Sync crew memory — call BEFORE deep research on this Jira key.

    Without query: list recent (session sync). With query: search by topic.
    Summarize hits for the user, then explore the codebase. Skipping this causes
    duplicate work when a teammate already remembered findings.
    """
    key = jira_key.strip().upper()
    if query.strip():
        return _as_json(_run("recall", key, query.strip()))
    return _as_json(_run("recall", key))


@mcp.tool()
def list_recent(jira_key: str, since: str = "") -> str:
    """List recent memories for an initiative (optional ISO8601 since cursor).

    Prefer this or recall() at session start / after a teammate announces a capture.
    """
    key = jira_key.strip().upper()
    if since.strip():
        return _as_json(_run("sync", key, since.strip()))
    return _as_json(_run("sync", key))


@mcp.tool()
def list_initiatives() -> str:
    """List initiatives attached for the current team."""
    return _as_json(_run("list"))


@mcp.tool()
def breakdown(jira_key: str, query: str = "") -> str:
    """Draft epic/story breakdown from recalled team memories.

    Always pulls memories first (FTS query optional), writes
    initiatives/<KEY>-breakdown.md, and returns JSON with path + memory_count.
    Prefer this over inventing stories without crew context.
    """
    key = jira_key.strip().upper()
    if query.strip():
        return _as_json(_run("breakdown", key, query.strip()))
    return _as_json(_run("breakdown", key))


@mcp.tool()
def metrics(jira_key: str = "") -> str:
    """Show local reuse metrics (recall hits, remember writes, breakdown runs)."""
    if jira_key.strip():
        return _as_json(_run("metrics", jira_key.strip().upper()))
    return _as_json(_run("metrics"))


@mcp.tool()
def status() -> str:
    """Show Team Brain client config (paths, supabase, embed provider)."""
    return _run("status")


def main() -> None:
    # stdio transport for Cursor / Claude Code MCP
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
