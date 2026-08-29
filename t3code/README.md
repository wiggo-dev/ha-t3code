# T3 Code Home Assistant Add-on

Run [T3 Code](https://github.com/pingdotgg/t3code) in headless server mode on Home Assistant OS so you can pair from the T3 Code desktop app over your LAN, with **Server-side Cursor** and bundled **Home Assistant Skills** against `/config`.

## Scope

- Debian (glibc) Add-on image with Cursor CLI (`cursor-agent`) baked in — [ADR-0001](../docs/adr/0001-debian-base-server-side-cursor.md)
- Optional `cursor_api_key` + login-file fallback under Provider home `/data/home` — [ADR-0002](../docs/adr/0002-cursor-credential-schema.md)
- Five Home Assistant Skills digest-synced into `/config/.agents/skills/` — [ADR-0003](../docs/adr/0003-workspace-agent-skills.md)
- Workspace remains `/config`; T3 state under `/data/t3`
- Off-LAN: LAN + Tailscale (private mesh) only — [ADR-0004](../docs/adr/0004-tailscale-off-lan.md)
- Thin evidence: Workspace files + read-only Core/Supervisor REST (`homeassistant_api` / `hassio_api`) — [ADR-0005](../docs/adr/0005-thin-log-evidence-sources.md); Skill depth — [ADR-0008](../docs/adr/0008-skill-depth-ceiling.md)
- Thin control plane: agent proposes; operator applies reload/restart/UI — [ADR-0006](../docs/adr/0006-control-plane-scope.md)
- Pin matrix: known-good `t3` + Cursor CLI baked at build; Update/Rebuild is the upgrade path — [ADR-0007](../docs/adr/0007-t3-cursor-pin-matrix.md)

LAN pairing behaviour is unchanged from Phase 1.

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
2. Open **T3 Code**, confirm version (**0.3.5**), **Update** or **Rebuild**, restart
3. Startup log should show `T3 Code add-on version 0.3.5` plus **Pin matrix** lines for `t3` and `cursor-agent`

That Update/Rebuild is the **only** supported way to change the pin matrix. Previous Add-on version is break-glass rollback. Do not run `agent update` or `npm install -g t3` inside the container.

Maintainers refresh both pins together with `./scripts/bump-pins.sh` (patch-bumps the Add-on version and CHANGELOG), then commit and push.

## Configure and start

| Option | Default | Purpose |
| --- | --- | --- |
| `host` | `0.0.0.0` | Bind address |
| `port` | `3773` | T3 HTTP/WebSocket port |
| `advertise_host` | _(auto)_ | Host shown in pairing URLs (LAN IP by default; set to Tailscale MagicDNS/IP off-LAN) |
| `cursor_api_key` | _(empty)_ | Optional Cursor API key (`CURSOR_API_KEY`) |

1. Install and start the add-on.
2. Open **Log**: pairing URL/token, Skills sync line, and Cursor auth-ready (or a warning if unset).
3. If using an API key, set **cursor_api_key** in Configuration and restart.
4. In the T3 desktop app, enable the **Cursor** provider in Settings once auth is ready (the add-on does not force-enable it).

Login-file fallback: from a host shell with Docker access, run `cursor-agent login` inside the add-on with `XDG_CONFIG_HOME=/data/home/.config` and `HOME=/config` (credentials land under `/data/home/.config/cursor/`). API key wins when both are present.

`HOME` is `/config` so `~` is the Workspace. Cursor config/cache use Provider home via `XDG_*` under `/data/home`.

Supervisor Configuration-tab copy of this options/how-to lives in [`DOCS.md`](DOCS.md) — keep the two aligned.

## Home Assistant Skills

On each start the add-on syncs bundled Skills into:

```text
/config/.agents/skills/<name>/SKILL.md
```

Add your own Skills as extra directories there (survives HA backups). If you edit a bundled Skill, the add-on keeps your copy and logs a warning; delete your edited file to restore the shipped version on the next start.

Bundled set: `home-assistant-configuration`, `home-assistant-troubleshooting`, `home-assistant-dashboard-ui`, `home-assistant-zigbee-esphome`, `home-assistant-development` (light-adapted from OpenCode; no MCP/`hab` runtime). Skills follow ask → gather thin evidence → propose → operator applies ([ADR-0008](../docs/adr/0008-skill-depth-ceiling.md)).

## Thin evidence

Agents can gather live facts without paste-dumping: Workspace files first, then read-only Core/Supervisor REST via `SUPERVISOR_TOKEN`, then operator drops under `/config/.t3code/exports/`. Short endpoint pointers and example `curl` shapes: [DOCS.md](DOCS.md#thin-evidence-read-only) ([ADR-0005](../docs/adr/0005-thin-log-evidence-sources.md)).

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

## Remote access

**Supported:** home LAN, or **Tailscale** (private mesh). Put the Home Assistant host on your tailnet (e.g. the community Tailscale add-on), join the T3 desktop from a machine on the same tailnet, and pair to the HA host’s Tailscale MagicDNS name (or Tailscale IP) on port `3773`.

1. Install/configure Tailscale on the HA host and on the client.
2. In this Add-on’s options, set **advertise_host** to the HA host’s MagicDNS name (preferred) or Tailscale IP.
3. Restart the Add-on and use the pairing URL from the Log (rewritten to that host).

An equivalent private mesh (e.g. Headscale) is fine if it gives the same trust model — no public listener. This Add-on does not bundle or configure Tailscale; `host_network` already exposes `:3773` on the host.

**Not supported:** port-forwarding `3773`, public HTTPS reverse proxies, or HA Ingress as a way to reach this Add-on. Those are out of scope — see [ADR-0004](../docs/adr/0004-tailscale-off-lan.md).

## Architecture

```text
T3 Code Desktop App (LAN or Tailscale)
        │
        ▼
Home Assistant host :3773
        │
        ▼
Add-on: t3 start … /config
        │
        ├── /config              ← Workspace (+ HOME / `~`)
        ├── /config/.t3code/exports/  ← operator evidence drops
        ├── /data/t3             ← T3 state
        └── /data/home           ← Provider home (XDG Cursor auth/cache)
        │
        └── SUPERVISOR_TOKEN → Core + Supervisor REST (read-only)
```

## Security notes

- LAN or Tailscale only. Do not port-forward `3773` or expose the Add-on on the public internet.
- Treat pairing tokens and `cursor_api_key` as secrets.

## Troubleshooting

### Build fails

Image installs Node, T3, and Cursor on Debian. Check npm/Cursor download errors in the build log.

### Cursor provider unhealthy in T3

- Log should say auth ready (API key or login file)
- `cursor-agent` must be on PATH inside the container
- Enable Cursor in T3 Settings (not auto-enabled)
- Rebuild after upgrading the add-on so the CLI is present
- **API key alone is not enough today:** T3 still treats Cursor as logged out unless `cursor-agent about` has a user email ([t3code#7244](https://github.com/pingdotgg/t3code/issues/7244)). Workaround: one-time `cursor-agent login` in the add-on (see above). Watch until upstream fixes it (noted on the closed [wayfinder map](https://github.com/wiggo-dev/ha-t3code/issues/1)).

### Cannot pair

- Host network binds on the HA LAN IP (or Tailscale IP when the host is on the mesh)
- Set **advertise_host** if logs show a Docker-internal address, or for off-LAN Tailscale MagicDNS/IP
- Confirm `<advertise_host>:3773` is reachable from the desktop (LAN or same tailnet)

## Known limitations

- **Thin evidence / Skill depth (ADR-0005 / ADR-0008):** Home Assistant Skills follow ask → gather → propose → operator applies. Agents prefer Workspace files, then thin Core/Supervisor REST (`SUPERVISOR_TOKEN`), then paste or `/config/.t3code/exports/`. Short endpoint pointers: [DOCS.md](DOCS.md#thin-evidence-read-only).
- **Control plane (ADR-0006):** no MCP/`hab`, no agent-initiated service calls, reload, restart, or device control. `hassio_role: homeassistant` unlocks `GET /core/logs` and also *could* allow Core mutate POSTs — Skills forbid those; the operator applies reload/restart/UI after approving edits.
- **Cursor API-key auth:** API key alone is not enough today ([t3code#7244](https://github.com/pingdotgg/t3code/issues/7244)); use one-time `cursor-agent login` as well (see [Configure and start](#configure-and-start)).
- **Not supported:** public HTTPS reverse proxy, HA Ingress, or port-forwarding `3773` (see [Remote access](#remote-access)).

## Development layout

```text
LICENSE
README.md
repository.yaml
scripts/
  bump-pins.sh
  dev-run.sh
  test-bump-pins.sh
  test-cursor-agent-wrapper.sh
  test-deploy-skills.sh
t3code/
  config.yaml
  Dockerfile
  run.sh
  cursor-agent-wrapper.sh
  deploy-skills.py
  skills/*/SKILL.md
  README.md
  DOCS.md
  CHANGELOG.md
  icon.png
  logo.png
```
