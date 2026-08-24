# T3 Code

Run [T3 Code](https://github.com/pingdotgg/t3code) in headless server mode on Home Assistant OS. Pair from the T3 desktop app over LAN or Tailscale and use Server-side Cursor against `/config`.

Canonical operator how-to: the add-on [README](https://github.com/wiggo-dev/ha-t3code/blob/main/t3code/README.md). Keep this page aligned with the Configuration sections there.

## Configuration

| Option | Default | Purpose |
| --- | --- | --- |
| `host` | `0.0.0.0` | Bind address |
| `port` | `3773` | T3 HTTP/WebSocket port |
| `advertise_host` | _(auto)_ | Host shown in pairing URLs (LAN IP by default; set to Tailscale MagicDNS/IP off-LAN) |
| `cursor_api_key` | _(empty)_ | Optional Cursor API key (`CURSOR_API_KEY`) |

## Start and pair (LAN)

1. Install and start the add-on.
2. Open **Log**: pairing URL/token, Skills sync line, and Cursor auth-ready (or a warning if unset).
3. If using an API key, set **cursor_api_key** and restart.
4. In the T3 desktop app, enable the **Cursor** provider in Settings once auth is ready (the add-on does not force-enable it).

Login-file fallback: from a host shell with Docker access, run `cursor-agent login` inside the add-on with `XDG_CONFIG_HOME=/data/home/.config` and `HOME=/config`. API key wins when both are present.

## Tailscale / `advertise_host`

Supported off-LAN path: **Tailscale** (or an equivalent private mesh). Public reverse proxy, HA Ingress, and port-forwarding `3773` are not supported.

1. Put the Home Assistant host and the T3 desktop on the same tailnet.
2. Set **advertise_host** to the HA host’s MagicDNS name (preferred) or Tailscale IP.
3. Restart and pair using the URL from the Log.

## Cursor auth

- Set **cursor_api_key** and/or complete a one-time `cursor-agent login` in the add-on.
- **API key alone is not enough today:** T3 still treats Cursor as logged out unless `cursor-agent about` has a user email ([t3code#7244](https://github.com/pingdotgg/t3code/issues/7244)). Workaround: one-time `cursor-agent login` (credentials under `/data/home`).

## Skills

On start, bundled Skills sync into `/config/.agents/skills/<name>/SKILL.md`. Operator-added Skills in that tree survive backups. Edited bundled copies are preserved; delete the edited file to restore the shipped version on the next start.

## Update / rebuild

Add-on store → **⋮** → **Check for updates** → open **T3 Code** → **Update** or **Rebuild** → restart. Confirm version **0.3.2** in the log (`T3 Code add-on version 0.3.2`) and the **Pin matrix** lines for `t3` and `cursor-agent`.

Update/Rebuild is the only supported upgrade path for the pin matrix. Previous Add-on version is break-glass. Do not run `agent update` or `npm install -g t3` inside the container.

## Thin evidence (read-only)

Agents gather live facts without paste-dumping ([ADR-0005](https://github.com/wiggo-dev/ha-t3code/blob/main/docs/adr/0005-thin-log-evidence-sources.md)). Auth is the Supervisor-injected `SUPERVISOR_TOKEN` bearer. Prefer Workspace files first; keep history/logbook windows short. **GET only** — never service calls, reload, restart, or device control from the agent ([ADR-0006](https://github.com/wiggo-dev/ha-t3code/blob/main/docs/adr/0006-control-plane-scope.md)).

**Core REST** (`homeassistant_api`) — base `http://supervisor/core/api`:

```bash
curl -fsS -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
  -H "Content-Type: application/json" \
  "http://supervisor/core/api/states/sensor.example"
```

Useful paths: `/states`, `/states/<entity_id>`, `/error_log`, `/history/period/<start>`, `/logbook/<start>`. Full shapes: [HA REST API](https://developers.home-assistant.io/docs/api/rest/).

**Supervisor REST** (`hassio_api`) — base `http://supervisor`:

```bash
curl -fsS -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
  "http://supervisor/core/logs"
```

Also: `/addons/<slug>/logs`, `/resolution/info`, host/supervisor health endpoints. Core container journal is `/core/logs`; Core API error text is `/core/api/error_log` — different sources.

**Exports:** drop files under `/config/.t3code/exports/` (created on Add-on start). If you version `/config` in git, ignore that path.

## Known limitations

- **Thin evidence / Skill depth (ADR-0005 / ADR-0008):** Home Assistant Skills follow ask → gather → propose → operator applies. Agents prefer Workspace files, then thin Core/Supervisor REST (`SUPERVISOR_TOKEN`), then paste or `/config/.t3code/exports/`.
- **Control plane (ADR-0006):** no MCP/`hab`, no agent-initiated service calls, reload, restart, or device control. The operator applies reload/restart/UI after approving edits.
