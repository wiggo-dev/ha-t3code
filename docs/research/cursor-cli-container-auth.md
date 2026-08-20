# Cursor CLI install and auth in containerized Linux

Research for [ha-t3code#5](https://github.com/wiggo-dev/ha-t3code/issues/5). Primary sources: [Cursor CLI installation](https://cursor.com/docs/cli/installation), [Cursor CLI authentication](https://cursor.com/docs/cli/reference/authentication), [Cursor CLI headless](https://cursor.com/docs/cli/headless), [Cursor CLI GitHub Actions](https://cursor.com/docs/cli/github-actions), the [official install script](https://cursor.com/install) (fetched 2026-08-19), and the bundled CLI package at `https://downloads.cursor.com/lab/2026.08.11-e8db854/linux/{x64,arm64}/agent-cli-package.tar.gz`. Empirical checks: Alpine 3.21, Debian bookworm-slim, and `ghcr.io/home-assistant/base:latest` (Alpine 3.24 aarch64).

Related: [t3-cursor-provider.md](./t3-cursor-provider.md) (T3 Code provider wiring).

## Summary

**The official Cursor CLI does not run on Alpine/musl today.** Install succeeds, but the bundled Node binary and native addons (`*.linux-*-gnu.node`) require **glibc**. On Alpine (including the Home Assistant add-on base image), `agent --version` fails with `cannot execute: required file not found` or `fcntl64: symbol not found` even with `gcompat`. On Debian/glibc it works.

**Auth can survive container restarts** if credentials live on a persistent volume and `HOME` (and optionally `XDG_CONFIG_HOME`) point there. Three headless-friendly options:

1. **`CURSOR_API_KEY`** (recommended for containers) — inject per start from add-on secrets; no token file needed.
2. **`agent login` + file store** — Linux stores tokens in `~/.config/cursor/auth.json` (mode `0600`); persist that path across restarts.
3. **`CURSOR_AUTH_TOKEN` / `--auth-token`** — session env/flag; same persistence rules as API key if supplied via secrets.

Browser login remains possible headlessly via `NO_OPEN_BROWSER=1 agent login` (print URL, complete auth on another device).

---

## Install method

### Official one-liner

```bash
curl https://cursor.com/install -fsS | bash
```

([installation docs](https://cursor.com/docs/cli/installation))

The install script ([source](https://cursor.com/install), version pinned at fetch time to `2026.08.11-e8db854`):

1. Detects OS (`linux` | `darwin`) and arch (`x64` | `arm64`).
2. Downloads `https://downloads.cursor.com/lab/<version>/{linux,darwin}/{x64,arm64}/agent-cli-package.tar.gz`.
3. Extracts to `~/.local/share/cursor-agent/versions/<version>/`.
4. Symlinks both command names into `~/.local/bin/`:
   - `agent` → `…/cursor-agent`
   - `cursor-agent` → `…/cursor-agent`

### Runtime dependencies (install script)

| Dependency | Purpose |
| --- | --- |
| `bash` | Install script and `cursor-agent` wrapper |
| `curl` | Download package |
| `tar` | Extract package |
| **glibc** | Bundled `node` ELF and `*.gnu.node` native modules |

Alpine provides bash/curl/tar, but uses **musl**, not glibc.

### Container install recipe (glibc base only)

```dockerfile
RUN apt-get update && apt-get install -y curl tar ca-certificates bash \
  && curl https://cursor.com/install -fsS | bash \
  && rm -rf /var/lib/apt/lists/*
ENV PATH="/root/.local/bin:${PATH}"
```

For HA add-ons on Alpine, either **change the base image** to a glibc distro or **run Cursor CLI outside** the Alpine container (host, sidecar, or nested glibc image). There is no official musl/Alpine build.

### Empirical Alpine failure

| Image | Arch | Result |
| --- | --- | --- |
| `alpine:3.21` | aarch64 | Install OK; `agent --version` → `node: cannot execute: required file not found` |
| `alpine:3.21` + `gcompat` | aarch64 | `Error relocating …/node: fcntl64: symbol not found` |
| `debian:bookworm-slim` | aarch64 | `agent --version` → `2026.08.11-e8db854` |
| `ghcr.io/home-assistant/base:latest` | aarch64 (Alpine 3.24) | Same musl/glibc mismatch expected |

Native modules in the Linux package are explicitly glibc builds, e.g. `file_service.linux-arm64-gnu.node`, `merkle-tree-napi.linux-arm64-gnu.node`.

---

## PATH and binary names

| Name | Role |
| --- | --- |
| `agent` | **Primary** CLI command ([installation docs](https://cursor.com/docs/cli/installation)) |
| `cursor-agent` | **Legacy alias**; same binary ([install script](https://cursor.com/install)) |

Default install location:

| Path | Contents |
| --- | --- |
| `~/.local/bin/agent` | Symlink to versioned binary |
| `~/.local/bin/cursor-agent` | Symlink to versioned binary |
| `~/.local/share/cursor-agent/versions/<version>/cursor-agent` | Bash wrapper → bundled `node index.js` |
| `~/.local/share/cursor-agent/versions/<version>/node` | Bundled Node (glibc) |

**PATH:** add `~/.local/bin` ([installation docs](https://cursor.com/docs/cli/installation)). The [GitHub Actions doc](https://cursor.com/docs/cli/github-actions) incorrectly suggests `$HOME/.cursor/bin`; the install script uses `~/.local/bin`.

T3 Code defaults to spawning `cursor-agent` ([t3-cursor-provider.md](./t3-cursor-provider.md)); either symlink name works.

Useful commands: `agent --version`, `agent update`, `agent status`, `agent login`, `agent logout`, `agent -p` (headless print mode).

---

## Config and credential file locations

Paths depend on `HOME` (and `XDG_CONFIG_HOME` on Linux). In containers, set `HOME` to a **persistent volume** (e.g. `/data/cursor` in HA add-ons).

### Linux (including containers on glibc)

| File | Path | Contents |
| --- | --- | --- |
| Auth tokens | `$XDG_CONFIG_HOME/cursor/auth.json` or `~/.config/cursor/auth.json` | `accessToken`, `refreshToken`, optional `apiKey` ([CLI bundle](../cli-credentials), verified by parsing `agent-cli-package` `index.js`) |
| CLI preferences | `~/.cursor/cli-config.json` | Permissions, sandbox, `authInfo` cache (display metadata — not the secret store) ([update-cli-config skill](https://cursor.com/docs/cli/reference/parameters)) |
| Agent install | `~/.local/share/cursor-agent/versions/` | Versioned CLI packages |
| Node compile cache | `$XDG_CACHE_HOME/cursor-compile-cache` or `~/.cache/cursor-compile-cache` | Performance cache |
| Worker data (optional) | `$CURSOR_DATA_DIR` or `/opt/cursor` or `~/.local/share/cursor-agent` | Logs/artifacts for `agent worker` mode |

Auth file is written with mode **0600**; parent dir mode **0700**.

### macOS (reference)

| File | Path |
| --- | --- |
| Auth (file store override) | `~/.cursor/auth.json` |
| Auth (default) | macOS Keychain services `cursor-access-token`, `cursor-refresh-token`, etc. |

### Windows (reference)

`%APPDATA%\Cursor\auth.json`

---

## Headless / container auth options

From [authentication docs](https://cursor.com/docs/cli/reference/authentication) and CLI source:

| Method | How | Container fit |
| --- | --- | --- |
| **API key** | `export CURSOR_API_KEY=…` or `agent --api-key …` | **Best** — inject from HA add-on option/secret each start; no filesystem persistence |
| **Auth token** | `CURSOR_AUTH_TOKEN` or `--auth-token` | Same as API key if sourced from secrets |
| **Browser login** | `agent login`; `NO_OPEN_BROWSER=1` prints URL | One-time setup; persist `~/.config/cursor/auth.json` on a volume |
| **Interactive fallback** | Without any of the above, CLI exits: *"Run 'agent login', pass --api-key/--auth-token, or set CURSOR_API_KEY/CURSOR_AUTH_TOKEN"* | — |

Headless automation: `agent -p --trust "prompt"` ([headless docs](https://cursor.com/docs/cli/headless)).

### Credential store override

`AGENT_CLI_CREDENTIAL_STORE`:

| Value | Behavior |
| --- | --- |
| `file` | Force file store (`auth.json` paths above) |
| `memory` | In-memory only — **lost on process exit** |
| unset / `default` | macOS → Keychain; **Linux → file store** |

On Linux containers, file store is already the default; `AGENT_CLI_CREDENTIAL_STORE=file` is explicit but not required.

### Network

CLI needs outbound HTTPS to Cursor APIs. Docs mention `*.cursor.sh` and `*.cursorapi.com` ([CLI help](https://cursor.com/help/integrations/cli)). DNS/network failures may surface as "invalid API key" ([authentication troubleshooting](https://cursor.com/docs/cli/reference/authentication)).

---

## Auth persistence across container restarts

| Auth method | Survives restart? | Requirement |
| --- | --- | --- |
| `CURSOR_API_KEY` / `CURSOR_AUTH_TOKEN` in env | **Yes** | Re-inject from add-on config/secrets on each start (env is ephemeral; secret store is durable) |
| `agent login` (file store) | **Yes** | Persist `~/.config/cursor/auth.json` (and usually `~/.cursor/cli-config.json`) on HA `/data` via `HOME=/data/cursor` or bind-mount |
| `AGENT_CLI_CREDENTIAL_STORE=memory` | **No** | Tokens die with the process |
| Install under `~/.local/share/cursor-agent` | **Yes** | Persist `HOME` or copy version dir into image; otherwise re-run install on each ephemeral container |

### Recommended HA add-on pattern (Phase 2)

1. **Switch to a glibc base** (e.g. Debian slim) *or* install/run Cursor CLI in a glibc sidecar — required until Cursor ships musl builds.
2. Install CLI in the image (`curl … | bash`) and `ENV PATH="/root/.local/bin:${PATH}"`.
3. Set `HOME=/data/cursor` (HA `/data` is persistent across add-on restarts/rebuilds).
4. Prefer **`CURSOR_API_KEY`** from add-on options (mapped to Supervisor secrets) — simplest and restart-safe.
5. Alternative: one-time `NO_OPEN_BROWSER=1 agent login` via add-on SSH/console, then rely on persisted `/data/cursor/.config/cursor/auth.json`.

Ephemeral container layers alone are **not** enough for login-based auth; only `/data` (or baked-in API keys) survives.

---

## Implications for this repo’s Alpine add-on

Current [`t3code/Dockerfile`](../../t3code/Dockerfile) uses `ghcr.io/home-assistant/base:latest` (Alpine 3.24, aarch64|amd64). Cursor CLI **cannot run there today** without an architectural change (non-Alpine base, glibc sidecar, or host-provided binary).

Minimum packages for install script on Alpine (insufficient alone): `bash`, `curl`, `tar`, plus attempted `gcompat` / `libstdc++` — still fails on missing glibc symbols.

---

## References

- Cursor CLI installation: https://cursor.com/docs/cli/installation
- Cursor CLI authentication: https://cursor.com/docs/cli/reference/authentication
- Cursor CLI headless: https://cursor.com/docs/cli/headless
- Cursor CLI GitHub Actions: https://cursor.com/docs/cli/github-actions
- Install script: https://cursor.com/install
- Linux arm64 package: https://downloads.cursor.com/lab/2026.08.11-e8db854/linux/arm64/agent-cli-package.tar.gz
- HA add-on base: `ghcr.io/home-assistant/base:latest` (Alpine, verified 2026-08-19)
- Related T3 provider research: [t3-cursor-provider.md](./t3-cursor-provider.md)
