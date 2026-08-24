# Claude Code CLI install and auth in Debian containers

Research for [ha-t3code#30](https://github.com/wiggo-dev/ha-t3code/issues/30) (map [#27](https://github.com/wiggo-dev/ha-t3code/issues/27)). Primary sources only: [Advanced setup](https://docs.anthropic.com/en/docs/claude-code/setup) / [code.claude.com setup](https://code.claude.com/docs/en/setup), [Authentication](https://docs.anthropic.com/en/docs/claude-code/authentication), [Environment variables](https://docs.anthropic.com/en/docs/claude-code/env-vars), [Settings](https://code.claude.com/docs/en/settings), [Explore the `.claude` directory](https://code.claude.com/docs/en/claude-directory), [Development containers](https://docs.anthropic.com/en/docs/claude-code/devcontainer), [GitHub Actions](https://docs.anthropic.com/en/docs/claude-code/github-actions), [Week 18 changelog](https://code.claude.com/docs/en/whats-new/2026-w18.md), the [native install script](https://claude.ai/install.sh) (fetched 2026-08-24), and the release [manifest](https://downloads.claude.ai/claude-code-releases/) for the version string returned by `…/latest` that day (`2.1.241`).

Related in-repo: [cursor-cli-container-auth.md](./cursor-cli-container-auth.md) (Cursor glibc-only contrast), [ADR-0001](../adr/0001-debian-base-server-side-cursor.md), Provider home in [`CONTEXT.md`](../../CONTEXT.md).

**Scope:** facts for baking `claude` into a Debian (glibc) Home Assistant Add-on. No Add-on implementation in this ticket.

---

## Summary

| Topic | Finding |
| --- | --- |
| **Debian / glibc** | Officially supported (`Debian 10+`, `Ubuntu 20.04+`). Native installer, **apt**, and npm all ship Linux glibc binaries for **x64** and **arm64**. |
| **musl / Alpine** | Also officially supported (native `linux-*-musl` binaries, **apk** repo, npm musl optional deps). Unlike Cursor CLI, musl is a first-class path — not required for this Add-on’s Debian base, but removes the Alpine blocker if a future image revisits musl. |
| **Binary name** | `claude` (launcher under `~/.local/bin/claude` for native installs). |
| **Headless auth** | Prefer **`ANTHROPIC_API_KEY`** (Console key) or **`CLAUDE_CODE_OAUTH_TOKEN`** (from `claude setup-token`, subscription). Browser **`claude` / `/login` / `claude auth login`** works in containers if the operator pastes the OAuth code when the localhost callback cannot reach the container. |
| **Credential files (Linux)** | `~/.claude/.credentials.json` (mode `0600`). Session / OAuth / MCP state also lives in **`~/.claude.json`** (sibling of `~/.claude`, not inside it). Set **`CLAUDE_CONFIG_DIR`** so both land on a persistent volume (Provider home). |
| **Auto-update** | Native installs **auto-update in the background**. For a pin matrix, set **`DISABLE_AUTOUPDATER=1`** (and ideally **`DISABLE_UPDATES=1`**) and install a concrete version. apt/npm do not use Claude’s background updater by default. |

---

## System requirements (official)

From [setup → System requirements](https://docs.anthropic.com/en/docs/claude-code/setup#system-requirements):

| Requirement | Value |
| --- | --- |
| OS | macOS 13+, Windows 10 1809+ / Server 2019+, **Ubuntu 20.04+**, **Debian 10+**, **Alpine Linux 3.19+** |
| Hardware | 4 GB+ RAM, **x64 or ARM64** |
| Network | Internet required ([network config](https://docs.anthropic.com/en/docs/claude-code/network-config#network-access-requirements)) |
| Shell | Bash, Zsh, PowerShell, or CMD |
| Extra | ripgrep usually bundled; Alpine/musl needs extra packages (see below) |

Account: Pro, Max, Teams, Enterprise, or Console (API). Free Claude.ai does not include Claude Code ([setup → Authenticate](https://docs.anthropic.com/en/docs/claude-code/setup#authenticate)).

---

## Install methods

### 1. Native installer (macOS / Linux / WSL) — default docs path

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

([setup](https://docs.anthropic.com/en/docs/claude-code/setup#install-claude-code))

**Behavior of [`https://claude.ai/install.sh`](https://claude.ai/install.sh)** (fetched 2026-08-24):

1. Optional arg: `stable` \| `latest` \| semver (`N.N.N`).
2. Detects OS (`linux` \| `darwin`) and arch (`x64` \| `arm64`).
3. On Linux, detects musl (`/lib/libc.musl-*.so.1` or `ldd` output) and selects platform `linux-{arch}` vs `linux-{arch}-musl`.
4. Downloads a bootstrap binary from `https://downloads.claude.ai/claude-code-releases/<bootstrap-version>/<platform>/claude` (bootstrap version from `…/latest`), verifies SHA256 against `manifest.json`, then runs `claude install [TARGET]`.
5. Refuses `sudo` from a non-root user unless `CLAUDE_INSTALL_ALLOW_SUDO=1` (installs under `$HOME`). Plain root (typical Dockerfile `USER root`) is fine.

**Layout after native install** ([setup → Auto-updates](https://docs.anthropic.com/en/docs/claude-code/setup#auto-updates)):

| Path | Role |
| --- | --- |
| `~/.local/bin/claude` | Launcher symlink (PATH must include `~/.local/bin`) |
| `~/.local/share/claude/versions/` | Versioned binaries |

Verify: `claude --version` (example form `2.1.211 (Claude Code)`), or `claude doctor` ([setup → Verify](https://docs.anthropic.com/en/docs/claude-code/setup#verify-your-installation)).

**Platforms in the release manifest** (example `2.1.241` from `…/latest` on 2026-08-24): `darwin-arm64`, `darwin-x64`, `linux-arm64`, `linux-x64`, `linux-arm64-musl`, `linux-x64-musl`, `win32-x64`, `win32-arm64`. Checksums are in signed `manifest.json` ([Binary integrity](https://docs.anthropic.com/en/docs/claude-code/setup#binary-integrity-and-code-signing)).

### 2. Pin a version or channel (native)

```bash
# channel
curl -fsSL https://claude.ai/install.sh | bash -s stable
curl -fsSL https://claude.ai/install.sh | bash -s latest

# exact version
curl -fsSL https://claude.ai/install.sh | bash -s 2.1.89
```

([setup → Install a specific version](https://docs.anthropic.com/en/docs/claude-code/setup#install-a-specific-version)). Channel chosen at install becomes the default for auto-updates / `claude update` unless overridden by settings.

### 3. Debian / Ubuntu apt (signed Anthropic repo)

Documented under [Install with Linux package managers](https://docs.anthropic.com/en/docs/claude-code/setup#install-with-linux-package-managers). Summary for Debian:

```bash
sudo apt install curl gnupg   # if missing
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL https://downloads.claude.ai/keys/claude-code.asc \
  -o /etc/apt/keyrings/claude-code.asc
# fingerprint must be 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
gpg --show-keys /etc/apt/keyrings/claude-code.asc

echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" \
  | sudo tee /etc/apt/sources.list.d/claude-code.list
sudo apt update
sudo apt install claude-code
```

- Channels: `stable` (≈1 week lag, skip major regressions) vs `latest` (swap URL path + suite name to `latest`).
- **Does not auto-update through Claude Code**; upgrade with `sudo apt update && sudo apt upgrade claude-code`.
- Package manager verifies signatures via the repo key (Linux binaries themselves are not individually code-signed).

### 4. npm global

```bash
npm install -g @anthropic-ai/claude-code
# pin:
npm install -g @anthropic-ai/claude-code@X.Y.Z
```

([setup → Install with npm](https://docs.anthropic.com/en/docs/claude-code/setup#install-with-npm)). As of v2.1.198 requires Node.js 22+ for the package metadata; the installed `claude` is still a **native binary** via optional deps (`linux-x64`, `linux-arm64`, `linux-x64-musl`, `linux-arm64-musl`, …). Do not use `sudo npm install -g`. Official **devcontainer pin** recipe uses this path ([devcontainer → Enforce organization policy](https://docs.anthropic.com/en/docs/claude-code/devcontainer#enforce-organization-policy)).

### Alpine / musl note (contrast with Cursor)

[setup → Alpine Linux and musl-based distributions](https://docs.anthropic.com/en/docs/claude-code/setup#alpine-linux-and-musl-based-distributions): install `bash curl libgcc libstdc++ ripgrep`, set `USE_BUILTIN_RIPGREP=0`, then use the normal installer or **apk** repo (`https://downloads.claude.ai/claude-code/apk/{stable,latest}`). This is the opposite of Cursor’s glibc-only failure mode documented in [cursor-cli-container-auth.md](./cursor-cli-container-auth.md).

---

## Authentication

### Interactive login (browser)

Documented flow ([Authentication](https://docs.anthropic.com/en/docs/claude-code/authentication#log-in-to-claude-code)):

1. Run `claude` (first launch) or use `/login` / `/logout` inside a session.
2. Browser opens for Claude.ai / Console / cloud-provider wizard.
3. If the browser cannot reach the local callback (WSL2, SSH, **containers**): paste the code at `Paste code here if prompted`, or press `c` to copy the login URL.

**`claude auth login`:** documented as a CLI login path that accepts a pasted OAuth code when the localhost callback fails ([Week 18 notes](https://code.claude.com/docs/en/whats-new/2026-w18.md), v2.1.126). Env docs also say `claude auth login` exchanges `CLAUDE_CODE_OAUTH_REFRESH_TOKEN` (+ `CLAUDE_CODE_OAUTH_SCOPES`) without opening a browser ([env-vars](https://docs.anthropic.com/en/docs/claude-code/env-vars)).

There is **no** requirement that interactive login be named `claude auth login` only — first-run `claude` and in-session `/login` are the primary setup docs.

### API key vs subscription token (headless / Add-on-friendly)

| Mechanism | How | When to use |
| --- | --- | --- |
| **`ANTHROPIC_API_KEY`** | Console API key as `X-Api-Key`. Interactive: approve once; **non-interactive (`-p`): always used when set**. | Best fit for HA secrets / CI-style Add-on config. |
| **`CLAUDE_CODE_OAUTH_TOKEN`** | One-year token from `claude setup-token` (browser once on a machine that can complete OAuth); export into the container. | Keep Pro/Max/Teams/Enterprise **subscription** billing without browser at runtime. Model requests only (no Remote Control / claude.ai connectors). |
| **`CLAUDE_CODE_OAUTH_REFRESH_TOKEN` + `CLAUDE_CODE_OAUTH_SCOPES`** | Fed to `claude auth login` for non-browser exchange. | Automated provisioning. |
| **`ANTHROPIC_AUTH_TOKEN`** | Bearer token for LLM gateway/proxy. | Gateway setups, not default Anthropic Console. |
| **`apiKeyHelper`** | Script returning a key ([settings](https://docs.anthropic.com/en/docs/claude-code/settings)). | Rotating vault secrets. |
| Cloud providers | `CLAUDE_CODE_USE_BEDROCK` / `_VERTEX` / `_FOUNDRY` + cloud creds. | Org cloud routing; out of Add-on destination unless explicitly chosen. |

Precedence (highest first), simplified from [Authentication precedence](https://docs.anthropic.com/en/docs/claude-code/authentication#authentication-precedence):

1. Cloud provider flags (Bedrock / Vertex / Foundry)
2. `ANTHROPIC_AUTH_TOKEN`
3. `ANTHROPIC_API_KEY`
4. `apiKeyHelper`
5. `CLAUDE_CODE_OAUTH_TOKEN`
6. Anthropic profile / federation (`ANTHROPIC_PROFILE`, WIF vars)
7. Stored subscription OAuth from `/login`

If both a subscription login and `ANTHROPIC_API_KEY` are present, the **API key wins once approved** and can surprise operators — `unset ANTHROPIC_API_KEY` to fall back; check `/status`.

`claude setup-token`:

```bash
claude setup-token
export CLAUDE_CODE_OAUTH_TOKEN=your-token
```

Token is printed, **not** saved to disk by the command ([Generate a long-lived token](https://docs.anthropic.com/en/docs/claude-code/authentication#generate-a-long-lived-token)). Same pattern as [GitHub Actions secrets](https://docs.anthropic.com/en/docs/claude-code/github-actions).

**Bare mode** (`--bare` / `CLAUDE_CODE_SIMPLE=1`) does **not** read `CLAUDE_CODE_OAUTH_TOKEN`; use `ANTHROPIC_API_KEY` or `apiKeyHelper` ([authentication](https://docs.anthropic.com/en/docs/claude-code/authentication#generate-a-long-lived-token), [env-vars](https://docs.anthropic.com/en/docs/claude-code/env-vars)).

---

## Credential and config locations (containers / Provider home)

### Files Claude Code writes

| Item | Default path (Linux) | Notes |
| --- | --- | --- |
| Login credentials | `~/.claude/.credentials.json` (mode **0600**) | Managed by `/login` / `/logout`. macOS uses Keychain instead. ([Credential management](https://docs.anthropic.com/en/docs/claude-code/authentication#credential-management)) |
| User settings | `~/.claude/settings.json` | Can set `env.DISABLE_AUTOUPDATER`, etc. |
| Global app state | **`~/.claude.json`** (home directory, **outside** `~/.claude/`) | Sign-in session, personal MCP, per-project trust, global `/config` keys ([settings](https://code.claude.com/docs/en/settings), [claude-directory](https://code.claude.com/docs/en/claude-directory)) |
| Install tree (native) | `~/.local/share/claude/`, `~/.local/bin/claude` | Separate from auth |

### `CLAUDE_CONFIG_DIR` (critical for persistent volumes)

[`CLAUDE_CONFIG_DIR`](https://docs.anthropic.com/en/docs/claude-code/env-vars) overrides the configuration directory (default `~/.claude`). On Linux/Windows, **credentials**, settings, session history, and plugins live under that directory. Official **devcontainer** guidance ([Persist authentication](https://docs.anthropic.com/en/docs/claude-code/devcontainer#persist-authentication-and-settings-across-rebuilds)):

> Mounting a volume at `~/.claude` alone doesn’t keep you signed in [because `~/.claude.json` is outside that directory]. Mount a named volume at `~/.claude` and set `CLAUDE_CONFIG_DIR` to the same path so Claude Code writes `.claude.json` inside the volume.

Example pattern:

```bash
export CLAUDE_CONFIG_DIR=/data/home/claude   # under Provider home
# credentials → $CLAUDE_CONFIG_DIR/.credentials.json
# settings    → $CLAUDE_CONFIG_DIR/settings.json
# .claude.json also under that dir when CLAUDE_CONFIG_DIR is set
```

**Implication for this Add-on:** process `HOME` stays the Workspace (`/config`) per [`CONTEXT.md`](../../CONTEXT.md) Provider home. Do **not** rely on `~/.claude` under `/config` for secrets. Point **`CLAUDE_CONFIG_DIR`** (and any native install’s binary install home, if build-time `HOME` differs) at a path under **`/data/home`**. Claude Code does **not** use `XDG_CONFIG_HOME` as its primary credential root the way Cursor’s `auth.json` does; `CLAUDE_CONFIG_DIR` is the documented override.

---

## Auto-update and pinning

### Behavior by install method

| Method | Background auto-update | Manual upgrade |
| --- | --- | --- |
| Native (`install.sh`) | **Yes** (startup + periodic) | `claude update` |
| Homebrew / WinGet | No (unless `CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1`) | brew / winget upgrade |
| apt / dnf / apk | No via Claude Code | package manager |
| npm | No via Claude Code | `npm install -g @anthropic-ai/claude-code@latest` |

([Update Claude Code](https://docs.anthropic.com/en/docs/claude-code/setup#update-claude-code))

### Disable updates (required for a pin matrix)

```json
{
  "env": {
    "DISABLE_AUTOUPDATER": "1"
  }
}
```

Or set the env var in the container:

| Variable | Effect |
| --- | --- |
| `DISABLE_AUTOUPDATER=1` | Stops background checks; `claude update` / `claude install` still work ([setup](https://docs.anthropic.com/en/docs/claude-code/setup#disable-auto-updates), [env-vars](https://docs.anthropic.com/en/docs/claude-code/env-vars)) |
| `DISABLE_UPDATES=1` | Blocks **all** updates including manual `claude update` / `claude install` — use when the image is the only distribution channel |

Optional floor/ceiling: settings `minimumVersion`, managed `requiredMinimumVersion` / `requiredMaximumVersion`, channel `autoUpdatesChannel`: `"latest"` \| `"stable"` ([setup](https://docs.anthropic.com/en/docs/claude-code/setup#configure-release-channel)).

### Pin-friendly recipes for a Debian HA Add-on image

**A — Native install, version arg (matches Cursor-style curl bake):**

```dockerfile
# Build as root; CLAUDE_INSTALL_ALLOW_SUDO only needed if SUDO_USER is set
ARG CLAUDE_CODE_VERSION=2.1.241
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
  && curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}" \
  && ln -sf /root/.local/bin/claude /usr/local/bin/claude \
  && claude --version \
  && rm -rf /var/lib/apt/lists/*
ENV DISABLE_AUTOUPDATER=1
ENV DISABLE_UPDATES=1
```

**B — apt channel (stable), hold package (Debian-native):**

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends curl gnupg ca-certificates \
  && install -d -m 0755 /etc/apt/keyrings \
  && curl -fsSL https://downloads.claude.ai/keys/claude-code.asc \
       -o /etc/apt/keyrings/claude-code.asc \
  && echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" \
       > /etc/apt/sources.list.d/claude-code.list \
  && apt-get update && apt-get install -y claude-code \
  && apt-mark hold claude-code \
  && claude --version \
  && rm -rf /var/lib/apt/lists/*
# apt installs do not use Claude's background updater; hold keeps apt from floating on later rebuilds unless hold is lifted
```

Exact `claude-code=<debian-version>` pinning depends on what the Anthropic apt repo publishes for that suite (not enumerated in prose docs); verify with `apt-cache policy claude-code` at build time if a semver ARG is required.

**C — npm pin (Anthropic’s documented reproducible container pin):**

```dockerfile
ARG CLAUDE_CODE_VERSION=2.1.241
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"
ENV DISABLE_AUTOUPDATER=1
ENV DISABLE_UPDATES=1
```

([devcontainer](https://docs.anthropic.com/en/docs/claude-code/devcontainer#enforce-organization-policy))

**Runtime auth injection (any recipe):** prefer Add-on options/secrets → `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`, plus `CLAUDE_CONFIG_DIR` under Provider home (`/data/home/…`) so file-stored logins survive restarts.

---

## Implications for map #27 (decisions material)

1. **Arch:** Official **linux-x64** and **linux-arm64** glibc binaries exist; both HA Add-on arches can carry Claude Code without a Cursor-style musl carve-out.
2. **Install:** Prefer **native versioned install** or **apt** on the existing Debian base (ADR-0001); disable updates with `DISABLE_AUTOUPDATER` / `DISABLE_UPDATES` so the pin matrix stays image-controlled (same spirit as ADR-0007).
3. **Auth for HA OS:** Document **API key** and **`setup-token` → `CLAUDE_CODE_OAUTH_TOKEN`** as first-class headless paths; browser/`claude auth login` remains available with paste-code for one-shot operator login into a persistent `CLAUDE_CONFIG_DIR`.
4. **Provider home:** Wire **`CLAUDE_CONFIG_DIR`** (not only XDG) so `.credentials.json` and `.claude.json` do not land in the Workspace or evaporate on restart.

---

## Sources

| Source | URL |
| --- | --- |
| Advanced setup | https://docs.anthropic.com/en/docs/claude-code/setup |
| Authentication | https://docs.anthropic.com/en/docs/claude-code/authentication |
| Environment variables | https://docs.anthropic.com/en/docs/claude-code/env-vars |
| Settings | https://code.claude.com/docs/en/settings |
| `.claude` directory | https://code.claude.com/docs/en/claude-directory |
| Dev containers | https://docs.anthropic.com/en/docs/claude-code/devcontainer |
| GitHub Actions | https://docs.anthropic.com/en/docs/claude-code/github-actions |
| Week 18 (auth login paste) | https://code.claude.com/docs/en/whats-new/2026-w18.md |
| Native install script | https://claude.ai/install.sh |
| Releases / manifest | https://downloads.claude.ai/claude-code-releases/ |
| Docs index | https://code.claude.com/docs/llms.txt |
