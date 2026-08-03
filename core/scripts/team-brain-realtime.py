#!/usr/bin/env python3
"""Team Brain Realtime Broadcast listener (#31).

Subscribes to signal-only topic team-brain:{team_id}:{JIRA_KEY}.
On memory_changed: runs team-brain-api.sh _pull_signal <KEY> (authenticated
list_recent merge — bodies never travel on the wire via Broadcast).

Requires: pip install websockets
Fallback: leave this unused; watch / sync-mode poll still work.

Env:
  TEAM_BRAIN_SUPABASE_URL, TEAM_BRAIN_SUPABASE_ANON_KEY (or team.yaml / public env)
  TEAM_BRAIN_API_KEY or credentials.json (for topic RPC + pull)
  TEAM_BRAIN_DIR, TEAM_BRAIN_API_SCRIPT (optional)
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any
from urllib.parse import urlencode


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _api_script() -> Path:
    env = os.environ.get("TEAM_BRAIN_API_SCRIPT")
    if env:
        return Path(env)
    candidate = _repo_root() / "core" / "scripts" / "team-brain-api.sh"
    if candidate.is_file():
        return candidate
    raise FileNotFoundError("team-brain-api.sh not found; set TEAM_BRAIN_API_SCRIPT")


def _load_creds() -> dict[str, str]:
    url = os.environ.get("TEAM_BRAIN_SUPABASE_URL", "").strip()
    anon = os.environ.get("TEAM_BRAIN_SUPABASE_ANON_KEY", "").strip()
    api_key = os.environ.get("TEAM_BRAIN_API_KEY", "").strip()
    team_dir = Path(os.environ.get("TEAM_BRAIN_DIR", Path.cwd() / ".team-brain"))
    cred = team_dir / "credentials.json"
    yaml = team_dir / "team.yaml"
    if (not url or not anon) and yaml.is_file():
        text = yaml.read_text(encoding="utf-8")
        for line in text.splitlines():
            s = line.strip()
            if s.startswith("supabase_url:"):
                url = url or s.split(":", 1)[1].strip().strip("\"'")
            elif s.startswith("supabase_anon_key:"):
                anon = anon or s.split(":", 1)[1].strip().strip("\"'")
    if not api_key and cred.is_file():
        data = json.loads(cred.read_text(encoding="utf-8"))
        api_key = str(data.get("api_key") or "")
    if not url or not anon:
        public_env = _repo_root() / "supabase" / "project.public.env"
        if public_env.is_file():
            for line in public_env.read_text(encoding="utf-8").splitlines():
                if line.startswith("TEAM_BRAIN_SUPABASE_URL="):
                    url = url or line.split("=", 1)[1].strip()
                elif line.startswith("TEAM_BRAIN_SUPABASE_ANON_KEY="):
                    anon = anon or line.split("=", 1)[1].strip()
    if not url or not anon or not api_key:
        raise SystemExit(
            "Need TEAM_BRAIN_SUPABASE_URL, TEAM_BRAIN_SUPABASE_ANON_KEY, and TEAM_BRAIN_API_KEY"
        )
    return {"url": url.rstrip("/"), "anon": anon, "api_key": api_key}


def _rpc(url: str, anon: str, fn: str, payload: dict[str, Any]) -> Any:
    req = urllib.request.Request(
        f"{url}/rest/v1/rpc/{fn}",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "apikey": anon,
            "Authorization": f"Bearer {anon}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        err = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"RPC {fn} failed HTTP {exc.code}: {err}") from exc


def _pull_signal(jira_key: str) -> None:
    script = _api_script()
    env = os.environ.copy()
    proc = subprocess.run(
        ["bash", str(script), "_pull_signal", jira_key],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    if proc.stderr:
        print(proc.stderr, file=sys.stderr, end="")
    if proc.stdout:
        print(proc.stdout, end="")
    if proc.returncode != 0:
        print(f"→ _pull_signal failed ({proc.returncode})", file=sys.stderr)


async def _listen(jira_key: str, topic: str, url: str, anon: str) -> None:
    try:
        import websockets  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            "team-brain-realtime requires websockets — "
            "pip install websockets   (or use: watch <KEY> without --push)"
        ) from exc

    host = url.replace("https://", "wss://").replace("http://", "ws://")
    qs = urlencode({"apikey": anon, "vsn": "1.0.0"})
    ws_url = f"{host}/realtime/v1/websocket?{qs}"
    channel = f"realtime:{topic}"
    ref = 0

    def next_ref() -> str:
        nonlocal ref
        ref += 1
        return str(ref)

    print(f"→ Realtime listen {jira_key} topic={topic}", file=sys.stderr)
    print("  Signal-only; bodies via authenticated pull. Ctrl+C to stop.", file=sys.stderr)

    backoff = 1.0
    while True:
        try:
            async with websockets.connect(
                ws_url,
                ping_interval=20,
                ping_timeout=20,
                max_size=2**20,
            ) as ws:
                join_ref = next_ref()
                join = {
                    "topic": channel,
                    "event": "phx_join",
                    "payload": {
                        "config": {
                            "broadcast": {"ack": False, "self": False},
                            "presence": {"key": ""},
                            "postgres_changes": [],
                            "private": False,
                        }
                    },
                    "ref": join_ref,
                }
                await ws.send(json.dumps(join))
                joined = False
                backoff = 1.0
                while True:
                    raw = await ws.recv()
                    if isinstance(raw, (bytes, bytearray)):
                        raw = raw.decode("utf-8", errors="replace")
                    msg = json.loads(raw)
                    event = msg.get("event")
                    if event == "phx_reply" and msg.get("ref") == join_ref:
                        status = (msg.get("payload") or {}).get("status")
                        if status == "ok":
                            joined = True
                            print(f"→ subscribed ({channel})", file=sys.stderr)
                        else:
                            print(f"→ join failed: {msg}", file=sys.stderr)
                            raise RuntimeError("phx_join failed")
                        continue
                    if event == "phx_error":
                        print(f"→ channel error: {msg}", file=sys.stderr)
                        break
                    if not joined:
                        continue
                    if event in ("broadcast", "memory_changed"):
                        payload = msg.get("payload") or {}
                        # supabase wraps as { event, payload: {...} }
                        inner = payload.get("payload", payload)
                        ev_name = payload.get("event") or event
                        if ev_name not in ("memory_changed", "broadcast") and event != "broadcast":
                            continue
                        if isinstance(inner, dict) and inner.get("event") == "memory_changed":
                            inner = inner.get("payload") or inner
                        print(
                            f"── push signal {jira_key} "
                            f"op={inner.get('op') if isinstance(inner, dict) else '?'} "
                            f"ref={inner.get('source_ref') if isinstance(inner, dict) else ''} ──",
                            file=sys.stderr,
                        )
                        await asyncio.to_thread(_pull_signal, jira_key)
                    elif event == "phoenix" or event == "heartbeat":
                        continue
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 — reconnect loop
            print(f"→ realtime disconnected ({exc}); retry in {backoff:.0f}s", file=sys.stderr)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 30.0)


def main() -> None:
    parser = argparse.ArgumentParser(description="Team Brain Realtime Broadcast listener")
    parser.add_argument("jira_key", help="Jira key (e.g. AAP-81423)")
    parser.add_argument(
        "--topic",
        default="",
        help="Override Broadcast topic (default: memory_broadcast_topic RPC)",
    )
    args = parser.parse_args()
    key = args.jira_key.strip().upper()
    cfg = _load_creds()
    topic = args.topic.strip()
    if not topic:
        info = _rpc(
            cfg["url"],
            cfg["anon"],
            "memory_broadcast_topic",
            {"p_api_key": cfg["api_key"], "p_jira_key": key},
        )
        topic = str(info.get("topic") or "")
        if not topic:
            raise SystemExit(
                "memory_broadcast_topic returned no topic — "
                "apply migration 20260804000001_team_brain_realtime_broadcast.sql"
            )
        print(json.dumps({"topic": topic, "event": info.get("event"), "private": info.get("private")}))
    asyncio.run(_listen(key, topic, cfg["url"], cfg["anon"]))


if __name__ == "__main__":
    main()
