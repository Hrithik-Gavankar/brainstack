# Google Calendar MCP

Read-only agent tools for Google Calendar — closes the "sync is calendar-blind"
gap: hackathons, demos, meetups, and workshops never show up in git/`gh`, so
`engineer-brain sync` used to miss them. This server is generic and standalone
(not coupled to Team Brain or any tracker key) — plug it in for any skill/command
that wants "what's on my calendar today".

Zero third-party dependencies beyond the `mcp` SDK — the Google OAuth + Calendar
API client (`core/scripts/gcal_lib.py`) is stdlib-only (`urllib`, `http.server`).
Scope is `calendar.readonly`: this server cannot create, edit, or delete events.

## Tools

| Tool | Purpose |
|------|---------|
| `status` | Config status — credentials path, resolved calendar id, token expiry. No secrets. |
| `authorize_instructions` | One-time manual setup steps (this server can't open a browser itself) |
| `list_calendars` | Calendars visible to the authorized account |
| `today` | Today's events (local timezone day bounds) |
| `today_sync` | Today's events filtered for standup (task/active-participation only) |
| `upcoming` | Events for the next N days (default 7) |
| `upcoming_sync` | Next N days, standup filter applied |
| `events_range` | Events between two dates (`YYYY-MM-DD` or ISO8601) — e.g. Monday-covers-Friday standup scans |

## One-time setup (manual, like Team Brain's `start`)

1. In [Google Cloud Console](https://console.cloud.google.com/apis/credentials), enable the
   **Google Calendar API**, then create an **OAuth client ID** with application
   type **Desktop app**. Download the client secret JSON.
2. Run the CLI once — it opens a browser, you approve read-only access, and it
   stores a refresh token locally (`~/.config/engineer-brain/gcal/credentials.json`,
   `chmod 600`):
   ```bash
   bash core/scripts/gcal.sh authorize --client-secrets /path/to/client_secret.json
   ```
3. Verify:
   ```bash
   bash core/scripts/gcal.sh today
   ```

No further browser interaction is needed — the MCP server and CLI both silently
refresh a short-lived access token from the stored refresh token.

### Credential resolution (first match wins)

1. `$GCAL_CREDENTIALS_PATH`
2. `./.gcal/credentials.json` (per-workspace)
3. `~/.config/engineer-brain/gcal/credentials.json` (default, per-user)

### Calendar id resolution

`$GCAL_CALENDAR_ID` > `calendar_id` in the credentials file > `"primary"`.

To read a calendar other than your primary one (e.g. a shared team calendar),
either export `GCAL_CALENDAR_ID` or pass `--calendar-id` (CLI) / `calendar_id`
(MCP tool) per call.

## Install (MCP)

```bash
cd mcp/gcal
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
```

## Cursor (`mcp.json`)

```json
{
  "mcpServers": {
    "gcal": {
      "command": "/path/to/brainstack/mcp/gcal/.venv/bin/python",
      "args": ["/path/to/brainstack/mcp/gcal/server.py"]
    }
  }
}
```

Add a `GCAL_CREDENTIALS_PATH` / `GCAL_CALENDAR_ID` entry under `env` if you're
not using the default per-user credentials path.

## Claude Code

Add the same command/args/env under MCP servers in your Claude config.

## CLI (non-MCP platforms)

Any platform without MCP support (Copilot, Windsurf, Aider, Continue.dev) can
shell out to the same client, mirroring [`jira.sh`](../../core/scripts/jira.sh):

```bash
bash core/scripts/gcal.sh status
bash core/scripts/gcal.sh today
bash core/scripts/gcal.sh today --sync          # standup filter (preferred for sync)
bash core/scripts/gcal.sh upcoming 3
bash core/scripts/gcal.sh upcoming 3 --sync
bash core/scripts/gcal.sh range 2026-08-10 2026-08-12
bash core/scripts/gcal.sh calendars
```

Add `--json` to any read command for machine-readable output.

## Using it in `sync`

`engineer-brain sync` reads `status()` first; if `configured` is true, it calls
`today_sync()` (and `upcoming_sync(3)` on Mondays). The **sync filter** keeps
task-related / active-participation events (hackathon, demo, meetup, workshop)
and drops routine ceremonies (pod syncs, retros, bug reviews, 1:1s, drop-in
sessions). Raw `today()` is for full calendar inspection only. If not
configured, sync falls back to the `Upcoming Events` table in `BRAIN.md`.

See [`core/COMMANDS.md`](../../core/COMMANDS.md) and
[`platforms/cursor/skills/engineer-brain/SKILL.md`](../../platforms/cursor/skills/engineer-brain/SKILL.md).

## Security notes

- **Read-only by design**: requested scope is `calendar.readonly` only.
- Credentials and the derived access-token cache are written with `chmod 600`
  and are covered by `.gitignore` (`.gcal/credentials.json`,
  `**/*.token_cache.json`) — never commit them.
- The OAuth redirect is captured on a loopback address (`127.0.0.1`, random
  free port) per Google's recommended flow for installed apps — no secrets
  cross the network except directly to `accounts.google.com` /
  `oauth2.googleapis.com` / `www.googleapis.com`.
- Revoke access anytime at <https://myaccount.google.com/permissions>.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `No Google Calendar credentials found` | Run the `authorize` step above |
| `Google did not return a refresh_token` | You've authorized before without revoking; revoke at [myaccount.google.com/permissions](https://myaccount.google.com/permissions) and re-run `authorize` (it passes `prompt=consent` so this shouldn't normally happen) |
| Browser doesn't open automatically | Copy the printed URL manually — the local callback server still waits up to 180s |
| `Timed out waiting for authorization redirect` | Re-run `authorize`; check no firewall/VPN blocks `127.0.0.1` loopback |
| `Error 400: redirect_uri_mismatch` | You created a **Web application** OAuth client. Create a **Desktop app** client instead and download that JSON — loopback uses a random local port that Web clients cannot register |
