# Grok Build CLI install and auth in Debian containers

Research for [ha-t3code#31](https://github.com/wiggo-dev/ha-t3code/issues/31) (map [#27](https://github.com/wiggo-dev/ha-t3code/issues/27)). Primary sources only: [Grok Build overview](https://docs.x.ai/build/overview), [CLI reference](https://docs.x.ai/build/cli/reference), [Headless & Scripting](https://docs.x.ai/build/cli/headless-scripting), [Enterprise Deployments](https://docs.x.ai/build/enterprise), [Settings reference](https://docs.x.ai/build/settings/reference), [Settings](https://docs.x.ai/build/settings), and the [official install script](https://x.ai/cli/install.sh) (fetched 2026-08-24). Artifact probes against `https://x.ai/cli/` the same day.

Related: [cursor-cli-container-auth.md](./cursor-cli-container-auth.md) (Cursor `agent` PATH collision).

## Summary

**Official install is a native `grok` binary**, not a Node wrapper. The documented one-liner is `curl -fsSL https://x.ai/cli/install.sh | bash` ([overview](https://docs.x.ai/build/overview)). The script installs **two command names** into `$GROK_BIN_DIR` (default `~/.grok/bin`): `grok` and **`agent`**, both symlinks to the same binary ([install script](https://x.ai/cli/install.sh)). That **`agent` name collides with Cursor’s primary CLI symlink**.

**Auth for HA OS / headless Add-ons:** prefer `XAI_API_KEY` for automation, or `grok login --device-auth` for interactive operator login without a browser in the container ([enterprise](https://docs.x.ai/build/enterprise), [overview](https://docs.x.ai/build/overview)). Session/file credentials live under `$GROK_HOME` (default `~/.grok`), including `auth.json`.

**Pinning is first-class:** pass a semver to the install script (`bash -s X.Y.Z`), or `grok update --version <ver>`. Disable runtime drift with `GROK_DISABLE_AUTOUPDATER`, `[cli] auto_update = false`, and/or `--no-auto-update` on headless runs.

**Arch:** documented Linux platforms are `linux-x86_64` and `linux-aarch64`. Official Linux artifacts for stable `1.0.5` (2026-08-24) are published for both arches; the `linux-aarch64` blob is a **statically linked ELF** (no `PT_INTERP`), so that build does not depend on host glibc vs musl for the dynamic linker. Debian glibc remains the Add-on’s chosen base for Cursor; Grok does not force that choice.

---

## Install method

### Official one-liner

```bash
curl -fsSL https://x.ai/cli/install.sh | bash
```

([overview](https://docs.x.ai/build/overview); product page [x.ai/build](https://x.ai/build))

Windows PowerShell variant exists (`install.ps1`) but is out of scope for the Add-on.

### What the install script does

From [https://x.ai/cli/install.sh](https://x.ai/cli/install.sh) (fetched 2026-08-24):

1. Optional version arg: `bash -s 0.1.42` (semver `X.Y.Z` or `X.Y.Z-suffix`); otherwise reads channel pointer.
2. Channel via `GROK_CHANNEL` (`stable` | `alpha` | `enterprise`, default `stable`).
3. Detects OS (`macos` | `linux` | `windows`) and arch (`x86_64` | `aarch64`).
4. Resolves version from `https://x.ai/cli/${CHANNEL}` (fallback `https://storage.googleapis.com/grok-build-public-artifacts/cli/${CHANNEL}`).
5. Downloads `…/grok-${version}-${os}-${arch}` into `~/.grok/downloads/`.
6. Symlinks (Unix) into `${GROK_BIN_DIR:-$HOME/.grok/bin}`:
   - `grok` → downloaded binary
   - `agent` → same binary
7. If `~/.grok/bin` is not already on `PATH`, may also symlink **`grok` and `agent`** into the first writable of `$HOME/.local/bin` or `/usr/local/bin` that is already on `PATH`.
8. Appends a PATH block to `.bashrc` / `.zshrc` / fish config so `~/.grok/bin` is first.
9. Writes `[cli] installer = "internal"` (and optional `channel`) into `~/.grok/config.toml`.
10. Optionally uses `GROK_DEPLOYMENT_KEY` to fetch managed config from the inference proxy.

Runtime deps for install: `curl` or `wget`, `bash`, writable `$HOME`. No Node/npm required for the shell-script path.

### Alternative distribution (npm)

[Enterprise](https://docs.x.ai/build/enterprise) documents `npm install -g @xai-official/grok` as an install path that does **not** need `x.ai` / `storage.googleapis.com` for binary download (those hosts are only for the shell installer and `grok update`). Prefer the shell installer for Add-on bake unless npm packaging is already the image’s distribution style.

### Container-oriented recipe (Debian / glibc HA Add-on)

Pin at image build; put `grok` on PATH **without** installing the colliding `agent` name into shared dirs Cursor also uses:

```dockerfile
ARG GROK_VERSION=1.0.5
ENV GROK_BIN_DIR=/opt/grok/bin
ENV GROK_HOME=/data/grok
ENV GROK_DISABLE_AUTOUPDATER=1
RUN apt-get update && apt-get install -y curl ca-certificates bash \
  && mkdir -p "$GROK_BIN_DIR" \
  && curl -fsSL https://x.ai/cli/install.sh | bash -s "$GROK_VERSION" \
  && ln -sf "$GROK_BIN_DIR/grok" /usr/local/bin/grok \
  && rm -f /usr/local/bin/agent "$HOME/.local/bin/agent" \
  && rm -rf /var/lib/apt/lists/*
# Ensure Cursor’s agent / cursor-agent remain the only `agent` on PATH.
ENV PATH="/usr/local/bin:${GROK_BIN_DIR}:${PATH}"
```

Notes for Add-on wiring (facts from install script + settings docs; wiring itself is out of scope for this ticket):

- Override `HOME` / `GROK_HOME` onto a persistent volume (e.g. under `/data`) so `auth.json`, sessions, and config survive restarts ([settings](https://docs.x.ai/build/settings): `$GROK_HOME` defaults to `~/.grok`).
- Prefer invoking the **`grok`** binary name everywhere (T3 provider, health probes, docs) so PATH order never selects Grok’s `agent` alias over Cursor’s.
- If the installer already created `$GROK_BIN_DIR/agent`, leave it or remove it; do **not** copy/symlink that name into `/usr/local/bin` or `~/.local/bin` when Cursor’s `agent` lives there ([cursor-cli-container-auth.md](./cursor-cli-container-auth.md)).

Stable channel pointer on 2026-08-24: **`1.0.5`** (`https://x.ai/cli/stable`). Confirm at bake time; pin that value in the Dockerfile `ARG`.

---

## Architecture and libc

| Platform id (install script) | Host `uname -m` accepted |
| --- | --- |
| `linux-x86_64` | `x86_64`, `amd64` |
| `linux-aarch64` | `arm64`, `aarch64` |

Unsupported OS/arch exits with an error from the install script. macOS and Windows builds exist; not needed for the Add-on image.

**glibc / musl:** official docs do not publish a musl-specific build name. Both `linux-x86_64` and `linux-aarch64` artifacts for stable `1.0.5` return HTTP 200 from `https://x.ai/cli/` (2026-08-24). The `linux-aarch64` blob is a **statically linked ELF** (no `PT_INTERP` in the program headers). TLS is documented as **`rustls` with no OpenSSL dependency**, loading roots from the OS trust store ([enterprise](https://docs.x.ai/build/enterprise)) — so the image still needs CA certs (`ca-certificates` on Debian).

Implication for this repo: Grok does not require the Debian/glibc base the way Cursor’s Node/`*.gnu.node` stack does ([cursor-cli-container-auth.md](./cursor-cli-container-auth.md), ADR-0001). The Add-on’s Debian base remains driven by Cursor; Grok fits that base and is not the musl blocker.

---

## PATH and binary names

| Name | Role | Source |
| --- | --- | --- |
| `grok` | Primary documented command | [overview](https://docs.x.ai/build/overview), [CLI reference](https://docs.x.ai/build/cli/reference) |
| `agent` | **Alias of the same binary** installed by the shell script | [install script](https://x.ai/cli/install.sh) (`ln -sf … "$BIN_DIR/agent"`; Windows copies `agent.exe`) |
| `grok agent stdio` | ACP mode over stdin/stdout (subcommand, not the `agent` symlink) | [CLI reference](https://docs.x.ai/build/cli/reference), [headless](https://docs.x.ai/build/cli/headless-scripting) |

Default layout:

| Path | Contents |
| --- | --- |
| `~/.grok/bin/grok` | Symlink to `~/.grok/downloads/grok-{os}-{arch}` |
| `~/.grok/bin/agent` | Same target |
| `~/.grok/downloads/` | Downloaded binary blob |
| Optional `$HOME/.local/bin/{grok,agent}` or `/usr/local/bin/{grok,agent}` | Extra symlinks if `~/.grok/bin` was not on `PATH` |

### Collision with Cursor

Cursor’s official CLI installs **`agent`** (primary) and `cursor-agent` (legacy) under `~/.local/bin` ([cursor-cli-container-auth.md](./cursor-cli-container-auth.md)). Grok’s installer also creates an **`agent`** symlink and may place it in `~/.local/bin` or `/usr/local/bin`.

Whichever directory appears first on `PATH` wins. In a multi-provider Add-on image that already ships Cursor:

1. Always call Grok as **`grok`**, never as bare `agent`.
2. Do not install Grok’s `agent` into the same bin dir Cursor uses for `agent` / `cursor-agent`.
3. Prefer `GROK_BIN_DIR` outside `~/.local/bin` (e.g. `/opt/grok/bin`) and symlink only `grok` into `/usr/local/bin`.

`grok agent stdio` remains available as a **subcommand** of `grok` and does not require the `agent` symlink.

---

## Auth and credentials

### Methods ([enterprise](https://docs.x.ai/build/enterprise))

| Method | Trigger | Refreshable | Best for HA Add-on |
| --- | --- | --- | --- |
| Browser OIDC | `grok login` (default) | Yes | Poor fit (no browser in container) |
| Device code | `grok login --device-auth` | Yes | Operator one-time login via SSH/console; complete URL+code on another device |
| External auth provider | `auth_provider_command` in config | Yes | Enterprise IdP brokers |
| API key | `XAI_API_KEY` or `model.api_key` in config | No | **Recommended for headless / secrets injection** |

Credential resolution order when multiple are present: `model.api_key` > `model.env_key` > active session token > `XAI_API_KEY` ([enterprise](https://docs.x.ai/build/enterprise)).

Overview also states: on first launch Grok opens a browser; in non-browser environments use an API key ([overview](https://docs.x.ai/build/overview)).

### Headless examples

```bash
export XAI_API_KEY="xai-..."
grok -p "Explain this codebase" --output-format streaming-json
```

```bash
grok login --device-auth
```

([enterprise](https://docs.x.ai/build/enterprise), [CLI reference](https://docs.x.ai/build/cli/reference) for `grok login` / `grok logout`)

ACP headless auth can use cached token or `xai.api_key` when `XAI_API_KEY` is set ([headless](https://docs.x.ai/build/cli/headless-scripting)).

### Paths and env ([settings reference](https://docs.x.ai/build/settings/reference), [settings](https://docs.x.ai/build/settings), install script)

| Item | Default / location | Notes |
| --- | --- | --- |
| `GROK_HOME` | `~/.grok` | Home for config, auth, sessions, skills, plugins, logs |
| `XAI_API_KEY` | unset | API key when not using browser/session login |
| Auth file | `~/.grok/auth.json` (i.e. `$GROK_HOME/auth.json`) | Install script reads OIDC/legacy scoped tokens from this file; `grok logout` clears cached credentials |
| User config | `$GROK_HOME/config.toml` | Preferences including `[cli] auto_update` / `channel` |
| Sessions | `$GROK_HOME/sessions` | Headless session storage ([headless](https://docs.x.ai/build/cli/headless-scripting)) |
| Managed / requirements | `$GROK_HOME/managed_config.toml`, `$GROK_HOME/requirements.toml`; system `/etc/grok/*` | Enterprise policy layers ([enterprise](https://docs.x.ai/build/enterprise)) |

For Add-on persistence: point `GROK_HOME` (and usually `HOME`) at a volume under `/data`, or bind-mount `$GROK_HOME`, so device-code login survives restarts. API-key auth needs no auth file if the key is injected per start from Add-on secrets.

### Network (auth + inference)

Required for core use ([enterprise](https://docs.x.ai/build/enterprise)):

| Host | Purpose |
| --- | --- |
| `cli-chat-proxy.grok.com` | Inference proxy, settings |
| `auth.x.ai` | OAuth2/OIDC |

Also needed for API-key path and install/update respectively: `api.x.ai`, `x.ai`, `storage.googleapis.com` (see enterprise table for when each can be blocked).

---

## Auto-update and version pin

### Runtime update surfaces

| Surface | Behavior | Source |
| --- | --- | --- |
| `grok update` | Check or install a specific version: `--check`, `--version <ver>`, `--alpha`, `--stable` | [CLI reference](https://docs.x.ai/build/cli/reference) |
| `[cli] auto_update` | Default **on** when unset; set `false` to disable launch checks | [settings reference](https://docs.x.ai/build/settings/reference) |
| `GROK_DISABLE_AUTOUPDATER` | If set, suppress auto-updater for this process (docs call out CI/containers) | [settings reference](https://docs.x.ai/build/settings/reference) |
| `--no-auto-update` | Skip background update checks for headless (`-p`) or ACP (`grok agent stdio`) | [headless](https://docs.x.ai/build/cli/headless-scripting) |
| `GROK_CHANNEL` / `[cli] channel` | `stable` or `alpha` preference for installer / config | install script; [settings reference](https://docs.x.ai/build/settings/reference) |

In-app / shell updates download binaries from `x.ai` (fallback GCS) ([enterprise](https://docs.x.ai/build/enterprise)).

### Pin-friendly recipe (Add-on image)

1. **Bake a pinned version:** `curl -fsSL https://x.ai/cli/install.sh | bash -s "$GROK_VERSION"` with `GROK_VERSION` as a Dockerfile `ARG` (semver from `https://x.ai/cli/stable` or a chosen release).
2. **Freeze at runtime:** `ENV GROK_DISABLE_AUTOUPDATER=1` and/or write into config:

   ```toml
   [cli]
   auto_update = false
   channel = "stable"
   ```

3. **Headless invocations:** pass `--no-auto-update` on `grok -p …` / `grok agent stdio` as defense in depth.
4. **Upgrade path:** bump `GROK_VERSION` and rebuild the Add-on image (same operator unit as other baked CLIs); optionally `grok update --version <ver>` in a controlled maintenance task if runtime upgrade is ever allowed.

`requirements.toml` can pin **policy** settings fail-closed ([enterprise](https://docs.x.ai/build/enterprise)); it is not a substitute for pinning the CLI binary version via the install/`update --version` mechanism above.

---

## Useful commands

| Command | Purpose |
| --- | --- |
| `grok version` | Print version |
| `grok update --check` / `grok update --version X.Y.Z` | Update control |
| `grok login` / `grok login --device-auth` / `grok logout` | Auth |
| `grok -p "…"` / `--output-format streaming-json` | Headless |
| `grok agent stdio` | ACP |
| `grok inspect` | Show discovered config/rules/skills/MCP |

---

## Open points for later map tickets (not blocking this research)

- Exact T3 Code server-side provider binary name / env for Grok (upstream T3, not x.ai docs).
- Whether device-code `auth.json` refresh behaviour matches the Add-on’s restart cadence in practice (prove session ticket).
- Image size cost of shipping `grok` (~130–170 MiB per arch for `1.0.5` Linux artifacts as of 2026-08-24) vs optional provider installs.
