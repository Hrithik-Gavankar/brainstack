#!/usr/bin/env python3
"""Team Brain MCP — agent tools for collaborative initiative memory.

Wraps core/scripts/team-brain-api.sh (Supabase RPCs). Embeddings optional;
recall uses FTS when TEAM_BRAIN_EMBED_PROVIDER is unset.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from mcp.server.fastmcp import FastMCP

mcp = FastMCP(
    "team-brain",
    instructions=(
        "Team Brain = shared AI memory for a crew on one Jira key. "
        "COMPLIANCE (policy=stronger_prompts, soft gate — do not skip): "
        "Before deep research on a Jira key you MUST have research_ok "
        "(start loads context; or call prepare_research / recall). "
        "If sync_status/compliance returns agent_action, follow it before coding. "
        "After durable findings call remember with source_ref in the same turn. "
        "ENTRY: when the user starts team work, call start(jira_key) once — "
        "loads crew memory + sync mode. Summarize cache, then research. "
        "While active: touch each turn; remember with source_ref "
        "(identical=no-op; same source_ref + new body=update/merge). "
        "On human correction: correct(source_ref, corrected_body) "
        "or re-remember same source_ref — never a second row for the topic. "
        "Optional learning kind: what was wrong → what to prefer (natural language, "
        "no TODO/NO-TODO dumps). "
        "source_ref updates archive the prior body; history() / restore() for soft rollback. "
        "If sync_status mode is sleep, prompt the user to wake before deep research. "
        "Peer push: start() may run Realtime Broadcast listener; check notify/<KEY>.json "
        "or sync_status.realtime_daemon after teammate remembers (poll/watch still fallback). "
        "Never upload personal BRAIN.md or credentials.json. "
        "CLI humans may bypass the soft gate; agents must not."
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
        "team-brain-api.sh not found; set TEAM_BRAIN_API_SCRIPT or run from brainstack checkout"
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


def _parse_obj(raw: str) -> dict:
    """Best-effort parse of CLI JSON object output."""
    if not raw:
        return {}
    try:
        data = json.loads(raw)
        return data if isinstance(data, dict) else {"data": data}
    except json.JSONDecodeError:
        for line in reversed(raw.splitlines()):
            line = line.strip()
            if line.startswith("{"):
                try:
                    data = json.loads(line)
                    if isinstance(data, dict):
                        return data
                except json.JSONDecodeError:
                    continue
    return {"raw": raw}


def _with_compliance(jira_key: str, payload: dict) -> str:
    """Attach compliance soft-gate fields so agents see agent_action inline."""
    key = jira_key.strip().upper()
    if not key:
        return json.dumps(payload, indent=2)
    try:
        compliance = _parse_obj(_run("compliance", key))
    except RuntimeError:
        compliance = {
            "policy": "stronger_prompts",
            "research_ok": False,
            "agent_action": f"Call start({key}) or compliance({key}) before deep research.",
        }
    out = dict(payload)
    out["compliance"] = compliance
    action = compliance.get("agent_action")
    if action:
        out["agent_action"] = action
    return json.dumps(out, indent=2)


@mcp.tool()
def whoami() -> str:
    """Show the current Team Brain member and team (from credentials.json)."""
    return _as_json(_run("whoami"))


@mcp.tool()
def pin_show() -> str:
    """Show commit-safe repo pin (.team-brain/project.json) — non-secret crew attach (#39)."""
    return _as_json(_run("pin", "show"))


@mcp.tool()
def rotate_invite() -> str:
    """Admin-only: rotate the team invite code (#40). Members/viewers cannot invite."""
    return _as_json(_run("rotate-invite"))


@mcp.tool()
def set_role(display_name: str, role: str) -> str:
    """Admin-only: set a teammate role to admin|member|viewer (#40)."""
    name = display_name.strip()
    role_n = role.strip().lower()
    if not name:
        raise ValueError("display_name is required")
    if role_n not in ("admin", "member", "viewer"):
        raise ValueError("role must be admin, member, or viewer")
    return _as_json(_run("set-role", name, "--role", role_n))


@mcp.tool()
def attach(
    jira_key: str = "",
    title: str = "",
    status: str = "active",
    jira_url: str = "",
) -> str:
    """Attach a Jira initiative and pull recent shared memories into the local cache.

    Prefer start() when beginning a work session — it attaches if needed and enters sync mode.
    jira_key optional when project.json pin is present. Writers only (viewers cannot attach).
    """
    key = jira_key.strip().upper() or _pinned_jira_key()
    if not key:
        raise ValueError(
            "jira_key required (or commit .team-brain/project.json with default_jira_key)"
        )
    title = title.strip() or key
    args = ["attach", key, title, status or "active"]
    if jira_url.strip():
        args.append(jira_url.strip())
    return _as_json(_run(*args))


def _pinned_jira_key() -> str:
    """Read commit-safe .team-brain/project.json default key if present."""
    team_dir = Path(os.environ.get("TEAM_BRAIN_DIR", Path.cwd() / ".team-brain"))
    pin = team_dir / "project.json"
    if not pin.is_file():
        return ""
    try:
        data = json.loads(pin.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return ""
    key = data.get("default_jira_key") or data.get("jira_key") or ""
    if not key and isinstance(data.get("jira_keys"), list) and data["jira_keys"]:
        key = data["jira_keys"][0]
    return str(key).strip().upper()


@mcp.tool()
def start(
    jira_key: str = "",
    interval_sec: int = 5,
    idle_hours: float = 1.0,
) -> str:
    """Enter sync mode for a Jira key — the ONE manual/session entrypoint.

    Loads crew memory into cache, starts background merge-safe pull, returns session JSON.
    Call when the user starts team work on a ticket. Summarize memories before researching.
    Sets research_ok (context load counts as recall for the soft compliance gate).
    jira_key optional when .team-brain/project.json pin has default_jira_key (#39).
    """
    key = jira_key.strip().upper() or _pinned_jira_key()
    if not key:
        raise ValueError(
            "jira_key required (or commit .team-brain/project.json with default_jira_key)"
        )
    args = ["start", key, str(max(2, int(interval_sec))), str(idle_hours)]
    payload = _parse_obj(_run(*args))
    return _with_compliance(key, payload)


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
    """Show sync mode + compliance soft gate (research_ok, agent_action).

    Modes: active | sleep | stopped | none.
    If compliance.agent_action is set, follow it before deep research.
    Prompt the user if mode is sleep.
    """
    if jira_key.strip():
        return _as_json(_run("sync-status", jira_key.strip().upper()))
    return _as_json(_run("sync-status"))


@mcp.tool()
def compliance(jira_key: str) -> str:
    """MCP-first soft gate for a Jira key (policy=stronger_prompts).

    Returns research_ok and agent_action. Soft gate: CLI humans are not blocked;
    agents MUST follow agent_action when present before deep research or ending a
    turn with unsaved durable findings. Never requires uploading personal BRAIN.md.
    """
    key = jira_key.strip().upper()
    if not key:
        raise ValueError("jira_key is required")
    return _as_json(_run("compliance", key))


@mcp.tool()
def prepare_research(jira_key: str, query: str = "") -> str:
    """Required before deep research — loads/search crew memory and returns compliance.

    Prefer this (or start + summarize) over jumping into the codebase.
    Without query: recent memories. With query: topic search.
    If compliance.agent_action remains set (e.g. sleep), stop and prompt the user.
    """
    key = jira_key.strip().upper()
    if not key:
        raise ValueError("jira_key is required")
    if query.strip():
        raw = _run("recall", key, query.strip())
    else:
        raw = _run("recall", key)
    payload = _parse_obj(raw)
    payload["prepared"] = True
    return _with_compliance(key, payload)


@mcp.tool()
def remember(
    jira_key: str,
    body: str,
    kind: str = "research",
    source_ref: str = "",
) -> str:
    """Save a finding for the crew — call IMMEDIATELY after durable research (do not wait).

    kind: research | decision | note | learning.
    Always pass source_ref (e.g. AAP-81423#cli-schema).
    Identical body → deduped=true. Same source_ref + new body → updated=true (merge);
    prior body is archived (archived_revision) when the history migration is applied.
    For human corrections prefer correct(); or re-remember with the same source_ref.
    Memory bodies: natural-language prefer/avoid guidance — never TODO/NO-TODO dumps.
    Response includes compliance (marks last_remember_at on the sync session).
    Viewers (read-only) cannot remember — RPC returns forbidden.
    """
    key = jira_key.strip().upper()
    kind_n = (kind or "research").strip().lower()
    if kind_n not in ("research", "decision", "note", "learning"):
        raise ValueError("kind must be research, decision, note, or learning")
    body = body.strip()
    if not body:
        raise ValueError("body is required")
    # Pass body on stdin ("-") so quotes/newlines/$() are not mangled as shell args
    args = ["remember", key, kind_n]
    if source_ref.strip():
        args.extend(["--source-ref", source_ref.strip()])
    args.append("-")
    payload = _parse_obj(_run(*args, stdin_data=body))
    return _with_compliance(key, payload)


@mcp.tool()
def correct(
    jira_key: str,
    source_ref: str,
    corrected_body: str,
    kind: str = "research",
    was_wrong: str = "",
    learning: str = "",
) -> str:
    """Absorb a human correction as ground truth — call when the user corrects bad research.

    Updates the memory at source_ref (merge — no second row). Optionally records a
    learning at source_ref/learning (what was wrong → what to prefer).
    Prefer natural-language guidance; never TODO/NO-TODO lists in bodies.
    """
    key = jira_key.strip().upper()
    ref = source_ref.strip()
    if not ref:
        raise ValueError("source_ref is required for correct")
    body = corrected_body.strip()
    if not body:
        raise ValueError("corrected_body is required")
    kind_n = (kind or "research").strip().lower()
    if kind_n not in ("research", "decision", "note"):
        raise ValueError("kind must be research, decision, or note")
    args = ["correct", key, "--source-ref", ref, "--kind", kind_n]
    if was_wrong.strip():
        args.extend(["--was", was_wrong.strip()])
    if learning.strip():
        args.extend(["--learning", learning.strip()])
    args.append("-")
    return _as_json(_run(*args, stdin_data=body))


@mcp.tool()
def history(jira_key: str, source_ref: str) -> str:
    """List archived revisions + current body for a source_ref (audit trail).

    Use after correct/remember updates when the crew needs to see what changed
    or pick a revision to restore(). Only revisions[] entries with restorable=true
    are valid restore targets (current.revision is null). Requires history migration.
    """
    key = jira_key.strip().upper()
    ref = source_ref.strip()
    if not ref:
        raise ValueError("source_ref is required for history")
    return _as_json(_run("history", key, "--source-ref", ref))


@mcp.tool()
def restore(jira_key: str, source_ref: str, revision: int) -> str:
    """Soft-rollback a memory to an archived revision (audit trail preserved).

    Archives the current body as a new revision, then restores body/kind from
    the chosen revision. Call history() first to pick a revision number.
    """
    key = jira_key.strip().upper()
    ref = source_ref.strip()
    if not ref:
        raise ValueError("source_ref is required for restore")
    try:
        rev = int(revision)
    except (TypeError, ValueError) as exc:
        raise ValueError("revision must be a positive integer") from exc
    if rev < 1:
        raise ValueError("revision must be a positive integer")
    return _as_json(
        _run("restore", key, "--source-ref", ref, "--revision", str(rev))
    )


@mcp.tool()
def recall(jira_key: str, query: str = "") -> str:
    """Sync crew memory — call BEFORE deep research on this Jira key.

    Without query: list recent (session sync). With query: search by topic.
    Summarize hits for the user, then explore the codebase. Skipping this causes
    duplicate work when a teammate already remembered findings.
    Marks research_ok on the sync session; response includes compliance.
    Prefer prepare_research() when you want an explicit pre-research gate check.
    """
    key = jira_key.strip().upper()
    if query.strip():
        raw = _run("recall", key, query.strip())
    else:
        raw = _run("recall", key)
    return _with_compliance(key, _parse_obj(raw))


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
def broadcast_topic(jira_key: str) -> str:
    """Return Realtime Broadcast topic for peer push signals (#31).

    Signal-only channel (no memory bodies). Requires migration
    20260804000001_team_brain_realtime_broadcast.sql. Content still via recall/list_recent.
    """
    key = jira_key.strip().upper()
    if not key:
        raise ValueError("jira_key is required")
    return _as_json(_run("broadcast-topic", key))


@mcp.tool()
def peer_notify(jira_key: str) -> str:
    """Read latest peer-push notification for a Jira key (if Realtime pull wrote one).

    Path: .team-brain/notify/<KEY>.json. Empty/missing means no push yet — use recall.
    """
    key = jira_key.strip().upper()
    if not key:
        raise ValueError("jira_key is required")
    team_dir = Path(os.environ.get("TEAM_BRAIN_DIR", Path.cwd() / ".team-brain"))
    path = team_dir / "notify" / f"{key}.json"
    if not path.is_file():
        return json.dumps(
            {
                "jira_key": key,
                "notify": None,
                "agent_hint": "No push notify yet — recall() or wait for sync poll.",
            },
            indent=2,
        )
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        data = {"raw": path.read_text(encoding="utf-8", errors="replace")}
    return json.dumps({"jira_key": key, "path": str(path), "notify": data}, indent=2)


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
