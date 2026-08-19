# T3 Code Home Assistant Add-on

Run [T3 Code](https://github.com/pingdotgg/t3code) in headless server mode on Home Assistant OS so you can pair from the T3 Code desktop app over your LAN.

This add-on uses `t3 serve` (not SSH remote launch). Pairing details — connection string, token, pairing URL, and QR code — are printed in the add-on logs.

## Phase 1 scope

- Install and start the T3 Code CLI server inside a Home Assistant add-on
- Bind to `0.0.0.0:3773` by default
- Use `/config` (Home Assistant configuration) as the T3 Code working directory
- Persist T3 runtime state under the add-on data directory (`/data/t3` in the container)

Cursor provider integration inside the container is planned for a later phase.

## Install the repository

1. In Home Assistant, open **Settings → Add-ons → Add-on store**.
2. Open the **⋮** menu (top right) → **Repositories**.
3. Add this repository URL:

   ```
   https://github.com/wiggo-dev/ha-t3code
   ```

4. Click **Add**, then refresh the add-on store.
5. Open **T3 Code** under the new repository category and install it.

For local development before publishing, you can also add the repository from a local path or fork using the same URL pattern after pushing your branch.

## Update the add-on after repo changes

Home Assistant caches custom add-on repositories locally. **Rebuild alone does not pull the latest commit from GitHub.**

1. Open **Settings → Add-ons → Add-on store**.
2. Open the **⋮** menu (top right) → **Check for updates** (refreshes git repositories).
3. Open the **T3 Code** add-on page and confirm the version (currently **0.1.2**).
4. Click **Update** if shown, otherwise **Rebuild**, then restart the add-on.
5. In the log, look for `T3 Code add-on version 0.1.2` near startup.

If the version in logs is still `0.1.0`, the supervisor has not pulled the latest repository yet.

## Configure and start

Default options are suitable for LAN pairing:

| Option | Default | Purpose |
| --- | --- | --- |
| `host` | `0.0.0.0` | Network interface to bind |
| `port` | `3773` | T3 Code HTTP/WebSocket port |
| `advertise_host` | _(auto)_ | Optional LAN IP or hostname to show in logs when pairing URLs use Docker internal addresses |

1. Install the add-on.
2. Start it.
3. Open the **Log** tab and look for the pairing URL, token, and QR code printed by `t3 serve`.

Treat pairing URLs and tokens like passwords. Anyone on your LAN who can reach the port can pair until credentials expire or are revoked.

## Pair from the T3 Code desktop app

1. Ensure your laptop/phone is on the same LAN as Home Assistant.
2. Find your Home Assistant host IP (for example `192.168.1.42`).
3. In the T3 Code desktop app, add the remote environment using either:
   - the full pairing URL from the add-on logs, or
   - the host `192.168.1.42:3773` plus the pairing token from the logs.
4. After pairing, the remote workspace uses Home Assistant's `/config` directory.

If you need a fresh pairing token without restarting the add-on, you can exec into the running container and run `t3 pair` (advanced).

## Architecture

```text
T3 Code Desktop App (LAN)
        │
        ▼
Home Assistant host :3773
        │
        ▼
Add-on container: t3 serve --host 0.0.0.0 --port 3773 /config
        │
        ├── /config  ← Home Assistant configuration (workspace)
        └── /data/t3 ← persistent T3 state (pairing sessions, userdata)
```

## Security notes

- This add-on exposes T3 Code on your LAN only by default. Do not port-forward it to the public internet without additional protection.
- Prefer Tailscale or a trusted HTTPS reverse proxy if you need access outside your home network later.
- Revoke stale pairing credentials with `t3 auth` if needed.

## Troubleshooting

### Add-on fails to build

The image installs Node.js 22 and compiles native dependencies for the T3 CLI. Check the build log for npm or compiler errors.

### Cannot pair from another machine

- The add-on uses **host network** so T3 binds on your Home Assistant host's LAN interfaces, not the internal `172.30.x.x` Docker network.
- If logs still show a `172.30.x.x` pairing URL, build the LAN URL yourself: `http://<home-assistant-lan-ip>:3773/pair#token=<token-from-logs>`
- Or set **advertise_host** in add-on options to your HA host IP or `homeassistant.local` for clearer log hints.
- Confirm your client device can reach `<home-assistant-ip>:3773` on the LAN.

### SSH remote launch vs this add-on

T3 Code's SSH remote environment feature expects a general-purpose Linux host with Node on `PATH` in non-interactive shells. Home Assistant OS does not provide that. This add-on avoids SSH launch and runs `t3 serve` in a container instead.

## Development

Repository layout:

```text
repository.yaml
t3code/
  config.yaml
  Dockerfile
  run.sh
  README.md
```

After changing files, rebuild the add-on from the Home Assistant add-on page (**Rebuild** / reinstall depending on your Supervisor version).
