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
        "Team Brain: shared AI memory for a crew on a Jira initiative. "
        "On attach or session start call recall/list_recent. "
        "After durable research call remember with a stable source_ref. "
        "Never upload personal BRAIN.md or credentials."
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


def _run(*args: str, timeout: int = 120) -> str:
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

    Always call this (or list_recent) before working on a key so the agent loads crew context.
    """
    key = jira_key.strip().upper()
    title = title.strip() or key
    args = ["attach", key, title, status or "active"]
    if jira_url.strip():
        args.append(jira_url.strip())
    return _as_json(_run(*args))


@mcp.tool()
def remember(
    jira_key: str,
    body: str,
    kind: str = "research",
    source_ref: str = "",
) -> str:
    """Write a durable shared memory for the initiative (research | decision | note).

    Use source_ref for idempotency (e.g. AAP-81423#cli-schema). Duplicate source_ref
    or identical body returns the existing row (deduped=true) — safe to retry.
    """
    key = jira_key.strip().upper()
    kind_n = (kind or "research").strip().lower()
    if kind_n not in ("research", "decision", "note"):
        raise ValueError("kind must be research, decision, or note")
    body = body.strip()
    if not body:
        raise ValueError("body is required")
    args = ["remember", key, kind_n]
    if source_ref.strip():
        args.extend(["--source-ref", source_ref.strip()])
    args.append(body)
    return _as_json(_run(*args))


@mcp.tool()
def recall(jira_key: str, query: str = "") -> str:
    """Recall shared memories for an initiative.

    With query: FTS search (or vector if TEAM_BRAIN_EMBED_PROVIDER is configured).
    Without query: list recent memories (session sync).
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
