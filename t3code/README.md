# T3 Code Home Assistant Add-on

Run [T3 Code](https://github.com/pingdotgg/t3code) in headless server mode on Home Assistant OS so you can pair from the T3 Code desktop app over your LAN, with **Server-side Cursor** and bundled **Home Assistant Skills** against `/config`.

## Phase 2 scope

- Debian (glibc) Add-on image with Cursor CLI (`cursor-agent`) baked in — [ADR-0001](../docs/adr/0001-debian-base-server-side-cursor.md)
- Optional `cursor_api_key` + login-file fallback under Provider home `/data/home` — [ADR-0002](../docs/adr/0002-cursor-credential-schema.md)
- Five Home Assistant Skills digest-synced into `/config/.agents/skills/` — [ADR-0003](../docs/adr/0003-workspace-agent-skills.md)
- Workspace remains `/config`; T3 state under `/data/t3`

Phase 1 pairing behaviour is unchanged.

## Install the repository

1. In Home Assistant, open **Settings → Add-ons → Add-on store**.
2. Open the **⋮** menu (top right) → **Repositories**.
3. Add:

   ```
   https://github.com/wiggo-dev/ha-t3code
   ```

4. Click **Add**, refresh the store, install **T3 Code**.

## Update after repo changes

1. Add-on store → **⋮** → **Check for updates**
2. Open **T3 Code**, confirm version (**0.2.1**), **Update** or **Rebuild**, restart
3. Startup log should show `T3 Code add-on version 0.2.1`

## Configure and start

| Option | Default | Purpose |
| --- | --- | --- |
| `host` | `0.0.0.0` | Bind address |
| `port` | `3773` | T3 HTTP/WebSocket port |
| `advertise_host` | _(auto)_ | LAN host shown in pairing URLs |
| `cursor_api_key` | _(empty)_ | Optional Cursor API key (`CURSOR_API_KEY`) |

1. Install and start the add-on.
2. Open **Log**: pairing URL/token, Skills sync line, and Cursor auth-ready (or a warning if unset).
3. If using an API key, set **cursor_api_key** in Configuration and restart.
4. In the T3 desktop app, enable the **Cursor** provider in Settings once auth is ready (the add-on does not force-enable it).

Login-file fallback: from a host shell with Docker access, run `cursor-agent login` inside the add-on with `XDG_CONFIG_HOME=/data/home/.config` and `HOME=/config` (credentials land under `/data/home/.config/cursor/`). API key wins when both are present.

`HOME` is `/config` so `~` is the Workspace. Cursor config/cache use Provider home via `XDG_*` under `/data/home`.

## Home Assistant Skills

On each start the add-on syncs bundled Skills into:

```text
/config/.agents/skills/<name>/SKILL.md
```

Add your own Skills as extra directories there (survives HA backups). If you edit a bundled Skill, the add-on keeps your copy and logs a warning; delete your edited file to restore the shipped version on the next start.

Bundled set: `home-assistant-configuration`, `home-assistant-troubleshooting`, `home-assistant-dashboard-ui`, `home-assistant-zigbee-esphome`, `home-assistant-development` (light-adapted from OpenCode; no MCP/`hab` runtime).

## Faster local iteration

```bash
./scripts/dev-run.sh
```

Builds `t3code/Dockerfile`, mounts `.dev/config` → `/config`, `.dev/data` → `/data`, publishes port `3773`.

```bash
PORT=3773 ADVERTISE_HOST=127.0.0.1 CURSOR_API_KEY=… ./scripts/dev-run.sh
```

Skills digest-sync smoke test (no Docker):

```bash
./scripts/test-deploy-skills.sh
```

## Architecture

```text
T3 Code Desktop App (LAN)
        │
        ▼
Home Assistant host :3773
        │
        ▼
Add-on: t3 start … /config
        │
        ├── /config              ← Workspace (+ HOME / `~`)
        ├── /data/t3             ← T3 state
        └── /data/home           ← Provider home (XDG Cursor auth/cache)
```

## Security notes

- LAN only by default. Do not port-forward without extra protection.
- Prefer Tailscale or a trusted HTTPS reverse proxy for off-LAN access (still fog — see the wayfinder map).
- Treat pairing tokens and `cursor_api_key` as secrets.

## Troubleshooting

### Build fails

Image installs Node, T3, and Cursor on Debian. Check npm/Cursor download errors in the build log.

### Cursor provider unhealthy in T3

- Log should say auth ready (API key or login file)
- `cursor-agent` must be on PATH inside the container
- Enable Cursor in T3 Settings (not auto-enabled)
- Rebuild after upgrading the add-on so the CLI is present
- **API key alone is not enough today:** T3 still treats Cursor as logged out unless `cursor-agent about` has a user email ([t3code#7244](https://github.com/pingdotgg/t3code/issues/7244)). Workaround: one-time `cursor-agent login` in the add-on (see above). Tracked on the [wayfinder map](https://github.com/wiggo-dev/ha-t3code/issues/1) until upstream fixes it.

### Cannot pair

- Host network binds on the HA LAN IP
- Set **advertise_host** if logs show a Docker-internal address
- Confirm `<ha-ip>:3773` is reachable on the LAN

## Development layout

```text
repository.yaml
t3code/
  config.yaml
  Dockerfile
  run.sh
  deploy-skills.py
  skills/*/SKILL.md
  README.md
```
