#!/usr/bin/env python3
"""Team Brain Realtime Broadcast listener (#31 — full push).

Subscribes to topic team-brain:{team_id}:{JIRA_KEY}. Each memory_changed
event carries `body_ct`: an app-layer-encrypted (AES-256-CBC + HMAC-SHA256)
copy of the memory body, opaque to Postgres/Supabase. If this process has
the team's broadcast_key (fetched once via memory_broadcast_topic, member
api_key required) and the `cryptography` package, it decrypts inline and
upserts the local cache directly — zero extra RPC round-trip ("full push").

Otherwise (no key cached yet, `cryptography` not installed, or body_ct is
null — e.g. right after a restore) it transparently falls back to the
original #31 behavior: team-brain-api.sh _pull_signal <KEY> (authenticated
list_recent merge). This fallback is unconditional and always correct.

Requires: pip install websockets            (push transport; required)
Optional: pip install cryptography          (full-content decrypt; else signal+pull)
Fallback: leave this unused; watch / sync-mode poll still work either way.

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


def _apply_pushed(jira_key: str, memory: dict[str, Any]) -> None:
    """Merge an already-decrypted memory straight into the local cache (full push)."""
    script = _api_script()
    env = os.environ.copy()
    proc = subprocess.run(
        ["bash", str(script), "_apply_pushed_memory", jira_key],
        input=json.dumps(memory),
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
        print(
            f"→ _apply_pushed_memory failed ({proc.returncode}) — falling back to authenticated pull",
            file=sys.stderr,
        )
        _pull_signal(jira_key)


def _decrypt_body_ct(body_ct: str, broadcast_key_b64: str) -> str | None:
    """Decrypt a "<iv_hex>:<ct_b64>:<hmac_hex>" payload. None on any failure (never raises)."""
    try:
        import base64
        import hashlib
        import hmac as hmac_mod

        from cryptography.hazmat.primitives import padding as sym_padding
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    except ImportError:
        return None
    try:
        iv_hex, ct_b64, hmac_hex = body_ct.split(":", 2)
        raw_key = base64.b64decode(broadcast_key_b64)
        enc_key = hashlib.sha256(raw_key + b"enc").digest()
        mac_key_hex = hashlib.sha256(raw_key + b"mac").hexdigest()
        mac_input = f"{iv_hex}:{ct_b64}".encode("utf-8")
        expected = hmac_mod.new(mac_key_hex.encode("ascii"), mac_input, hashlib.sha256).hexdigest()
        if not hmac_mod.compare_digest(expected, hmac_hex):
            print("→ body_ct HMAC mismatch — discarding, falling back to pull", file=sys.stderr)
            return None
        iv = bytes.fromhex(iv_hex)
        ct = base64.b64decode(ct_b64)
        decryptor = Cipher(algorithms.AES(enc_key), modes.CBC(iv)).decryptor()
        padded = decryptor.update(ct) + decryptor.finalize()
        unpadder = sym_padding.PKCS7(128).unpadder()
        return (unpadder.update(padded) + unpadder.finalize()).decode("utf-8")
    except Exception as exc:  # noqa: BLE001 — any crypto failure just degrades to pull
        print(f"→ body_ct decrypt failed ({exc}) — falling back to pull", file=sys.stderr)
        return None


def _has_cryptography() -> bool:
    try:
        import cryptography  # noqa: F401
    except ImportError:
        return False
    return True


async def _listen(
    jira_key: str,
    topic: str,
    url: str,
    anon: str,
    broadcast_key_b64: str | None = None,
) -> None:
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

    full_push_ready = bool(broadcast_key_b64) and _has_cryptography()
    print(f"→ Realtime listen {jira_key} topic={topic}", file=sys.stderr)
    if full_push_ready:
        print(
            "  Mode: full push (body decrypted locally; falls back to pull if a "
            "payload can't be decrypted). Ctrl+C to stop.",
            file=sys.stderr,
        )
    elif broadcast_key_b64:
        print(
            "  Mode: signal-only — pip install cryptography for full push (decrypt "
            "locally, zero extra round-trip). Bodies via authenticated pull. Ctrl+C to stop.",
            file=sys.stderr,
        )
    else:
        print(
            "  Mode: signal-only; bodies via authenticated pull. Ctrl+C to stop.",
            file=sys.stderr,
        )

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
                        op = inner.get("op") if isinstance(inner, dict) else "?"
                        ref = inner.get("source_ref") if isinstance(inner, dict) else ""
                        body_ct = inner.get("body_ct") if isinstance(inner, dict) else None
                        plaintext = None
                        if body_ct and broadcast_key_b64:
                            plaintext = _decrypt_body_ct(body_ct, broadcast_key_b64)
                        if plaintext is not None:
                            print(
                                f"── push FULL {jira_key} op={op} ref={ref} (decrypted locally) ──",
                                file=sys.stderr,
                            )
                            memory = {
                                "id": inner.get("capture_id"),
                                "kind": inner.get("kind"),
                                "body": plaintext,
                                "source_ref": inner.get("source_ref"),
                                "content_hash": inner.get("content_hash"),
                                "author_name": inner.get("author_name"),
                                "created_at": inner.get("created_at"),
                                "updated_at": inner.get("updated_at"),
                            }
                            await asyncio.to_thread(_apply_pushed, jira_key, memory)
                        else:
                            print(f"── push signal {jira_key} op={op} ref={ref} ──", file=sys.stderr)
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
    broadcast_key_b64: str | None = None
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
        broadcast_key_b64 = str(info.get("broadcast_key_b64") or "") or None
        print(
            json.dumps(
                {
                    "topic": topic,
                    "event": info.get("event"),
                    "private": info.get("private"),
                    "full_push": bool(broadcast_key_b64) and _has_cryptography(),
                }
            )
        )
    else:
        print(
            "→ --topic override supplied; broadcast_key not fetched — signal-only mode "
            "(drop --topic to get full push via memory_broadcast_topic).",
            file=sys.stderr,
        )
    asyncio.run(_listen(key, topic, cfg["url"], cfg["anon"], broadcast_key_b64))


if __name__ == "__main__":
    main()
