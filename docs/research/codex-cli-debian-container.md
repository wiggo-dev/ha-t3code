# Codex CLI install and auth in Debian containers

Research for [ha-t3code#29](https://github.com/wiggo-dev/ha-t3code/issues/29). Primary sources: [Codex CLI overview](https://developers.openai.com/codex/cli), [Authentication](https://developers.openai.com/codex/auth), [CLI reference](https://developers.openai.com/codex/cli/reference), [config reference](https://developers.openai.com/codex/config-reference) / [`config.schema.json`](https://github.com/openai/codex/blob/main/codex-rs/core/config.schema.json), [openai/codex README](https://github.com/openai/codex/blob/main/README.md), [docs/install.md](https://github.com/openai/codex/blob/main/docs/install.md), live installer [`https://chatgpt.com/codex/install.sh`](https://chatgpt.com/codex/install.sh) (fetched 2026-08-24; same logic as [`scripts/install/install.sh`](https://github.com/openai/codex/blob/main/scripts/install/install.sh)), [`find_codex_home`](https://github.com/openai/codex/blob/main/codex-rs/utils/home-dir/src/lib.rs), [`auth/storage.rs`](https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/storage.rs), [`tui/src/updates.rs`](https://github.com/openai/codex/blob/main/codex-rs/tui/src/updates.rs) + [`update_action.rs`](https://github.com/openai/codex/blob/main/codex-rs/tui/src/update_action.rs), and GitHub Release `rust-v0.149.1` asset list.

Related: [ADR-0001](../adr/0001-debian-base-server-side-cursor.md) (Debian glibc base), [ADR-0002](../adr/0002-cursor-credential-schema.md) (Provider home `/data/home` + `HOME=/config`), [cursor-cli-container-auth.md](./cursor-cli-container-auth.md).

**Scope:** facts for baking Codex CLI into a Debian (glibc) HA Add-on image for T3 server-side use. No Add-on implementation in this ticket.

---

## Summary

| Topic | Finding |
| --- | --- |
| **Official Linux binary** | **musl** targets only: `x86_64-unknown-linux-musl` / `aarch64-unknown-linux-musl` (not `*-linux-gnu`). Static musl builds are what the installer and README ship for Linux; they are the intended path on Debian/Ubuntu hosts ([README](https://github.com/openai/codex/blob/main/README.md), [install.sh](https://github.com/openai/codex/blob/main/scripts/install/install.sh), Release `rust-v0.149.1`). |
| **glibc vs musl host** | Unlike Cursor CLI (glibc-only), Codex’s official Linux packages are musl-tagged and meant for Linux generally; system matrix lists Ubuntu 20.04+/Debian 10+ ([docs/install.md](https://github.com/openai/codex/blob/main/docs/install.md)). No separate glibc Linux CLI asset in current releases. |
| **Arch** | Installer maps `x86_64`/`amd64` → `x86_64-unknown-linux-musl`, `aarch64`/`arm64` → `aarch64-unknown-linux-musl`. |
| **Auth for headless / CI** | Prefer **API key** via `printenv OPENAI_API_KEY \| codex login --with-api-key` (stores under `CODEX_HOME`). ChatGPT login works via browser OAuth or **`codex login --device-auth`**; docs also allow copying `~/.codex/auth.json`. Enterprise: `CODEX_ACCESS_TOKEN` + `--with-access-token` ([auth docs](https://developers.openai.com/codex/auth), [CLI reference](https://developers.openai.com/codex/cli/reference)). |
| **Credential path** | **`$CODEX_HOME/auth.json`** (default `~/.codex/auth.json`). Codex does **not** honor `XDG_CONFIG_HOME` for its home; only `CODEX_HOME` or `$HOME/.codex` ([`find_codex_home`](https://github.com/openai/codex/blob/main/codex-rs/utils/home-dir/src/lib.rs)). |
| **Auto-update** | Startup check defaults **on** (`check_for_update_on_startup`, schema default `true`). Standalone self-update re-runs the **unpinned** installer (`curl …/install.sh \| CODEX_NON_INTERACTIVE=1 sh`) ([update_action.rs](https://github.com/openai/codex/blob/main/codex-rs/tui/src/update_action.rs)). |
| **Pin** | `install.sh --release X.Y.Z` or `CODEX_RELEASE=X.Y.Z`; disable startup update checks for centrally managed images. |

---

## Install method

### Official one-liner (macOS/Linux)

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

([CLI docs](https://developers.openai.com/codex/cli), [README](https://github.com/openai/codex/blob/main/README.md))

Update is the same command ([CLI docs](https://developers.openai.com/codex/cli)).

Alternatives from the same primary sources:

| Method | Command / asset |
| --- | --- |
| npm | `npm install -g @openai/codex` (pin with `@openai/codex@X.Y.Z`; npm `latest` was `0.149.1` on 2026-08-24) |
| Homebrew | `brew install --cask codex` (macOS; not the HA path) |
| Direct GitHub Release | `codex-x86_64-unknown-linux-musl.tar.gz` / `codex-aarch64-unknown-linux-musl.tar.gz` (single binary; rename to `codex`) |

Installer download preference: `https://releases.openai.com/codex` first, GitHub Releases fallback. Force GitHub with `CODEX_INSTALLER_USE_RELEASES_OPENAI_COM=false` ([README](https://github.com/openai/codex/blob/main/README.md), [install.sh](https://github.com/openai/codex/blob/main/scripts/install/install.sh)).

### What the standalone installer does

From [`install.sh`](https://github.com/openai/codex/blob/main/scripts/install/install.sh) / live `chatgpt.com/codex/install.sh` (2026-08-24):

1. Detects OS (`linux` \| `darwin`) and arch (`x86_64` \| `aarch64`).
2. On Linux always selects **`vendor_target=*-unknown-linux-musl`** (no glibc variant).
3. Resolves version (`latest` or pinned); prefers package asset `codex-package-<vendor_target>.tar.gz` + `codex-package_SHA256SUMS`.
4. Extracts under **`$CODEX_HOME/packages/standalone/releases/<version>-<vendor_target>/`** (default `CODEX_HOME=$HOME/.codex`).
5. Symlinks **`$CODEX_INSTALL_DIR/codex`** (default `$HOME/.local/bin/codex`) to the active release; may also install `codex-code-mode-host` on some platforms.
6. Appends `PATH` export for `$BIN_DIR` into a shell profile when needed.

Requires `mktemp`, `tar`, and `curl` or `wget`; checksum via `sha256sum` / `shasum` / `openssl`.

Checksum parsing uses a **mawk-portable** awk matcher (`length($1) == 64 && …`) in both the live installer and `main` as of this fetch — older reports of Debian `mawk` + `{64}` failures refer to prior installer revisions ([openai/codex#24869](https://github.com/openai/codex/issues/24869) et al.).

### Version pin knobs

```text
Usage: install.sh [--release VERSION]

Environment:
  CODEX_RELEASE          Version to install; overridden by --release.
  CODEX_NON_INTERACTIVE  Set to 1, true, or yes to skip prompts.
  CODEX_INSTALLER_USE_RELEASES_OPENAI_COM
                         Set to 0, false, or no to use GitHub Releases.
```

Also used by the script (not listed in `--help`): `CODEX_INSTALL_DIR` (bin dir), `CODEX_HOME` (package + config root during install).

Valid pinned forms: `x.y.z`, optional `-alpha…` / `-beta…`; tags like `rust-v0.149.1` normalize to `0.149.1`.

### Arch matrix (Linux)

| `uname -m` | Installer `vendor_target` / package |
| --- | --- |
| `x86_64`, `amd64` | `x86_64-unknown-linux-musl` → `codex-package-x86_64-unknown-linux-musl.tar.gz` |
| `aarch64`, `arm64` | `aarch64-unknown-linux-musl` → `codex-package-aarch64-unknown-linux-musl.tar.gz` |

Other arches: installer exits unsupported.

Release `rust-v0.149.1` ships those musl package and binary assets; there are **no** `codex-*-unknown-linux-gnu` CLI packages in that release (only unrelated `argument-comment-lint-*-linux-gnu` tooling).

---

## Auth (login vs API key)

Official surface: two person sign-in methods for OpenAI models — **ChatGPT** (subscription) and **API key** (usage-based). Docs explicitly recommend API key for programmatic / CI-style CLI workflows ([auth docs](https://developers.openai.com/codex/auth)).

| Method | How | Best fit for HA Add-on |
| --- | --- | --- |
| API key | `printenv OPENAI_API_KEY \| codex login --with-api-key` | **Primary** headless path; persists into credential store |
| ChatGPT OAuth | `codex login` (browser / localhost callback, default port `1455`) | Awkward without browser or SSH `-L 1455:localhost:1455` |
| Device code (beta) | `codex login --device-auth` | Preferred ChatGPT path on headless hosts when workspace allows it |
| Access token | `printenv CODEX_ACCESS_TOKEN \| codex login --with-access-token` | Enterprise automation with ChatGPT workspace entitlements |
| Copy cache | Copy `auth.json` from a machine that completed login | Documented Docker/SSH fallback |

Status / clear: `codex login status` (exit `0` when credentials present); `codex logout` clears stored credentials ([CLI reference](https://developers.openai.com/codex/cli/reference)).

Source also defines env names `OPENAI_API_KEY`, `CODEX_API_KEY`, and `CODEX_ACCESS_TOKEN` ([`auth/mod.rs`](https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/mod.rs)). **Documented container/CI practice is still to run `codex login --with-api-key` (or access-token) so credentials land in the store**, not to rely on an undocumented “env-only, no login” contract for the interactive CLI.

Managed restrictions (optional): `forced_login_method = "chatgpt" \| "api"`, `forced_chatgpt_workspace_id` ([auth docs](https://developers.openai.com/codex/auth), config reference).

---

## Credential paths vs Provider home / XDG

### Codex home resolution

From [`find_codex_home`](https://github.com/openai/codex/blob/main/codex-rs/utils/home-dir/src/lib.rs):

- If **`CODEX_HOME` is set** (non-empty): path **must already exist as a directory**; it is canonicalized. Missing path → hard error.
- If unset: **`$HOME/.codex`** (no existence check at resolve time).

**`XDG_CONFIG_HOME` / `XDG_DATA_HOME` / `XDG_CACHE_HOME` are not used** to locate Codex home. That differs from Cursor CLI under ADR-0002 (tokens under `$XDG_CONFIG_HOME/cursor/…`).

### Where credentials and config live

| Artifact | Path | Source |
| --- | --- | --- |
| Cached login | `$CODEX_HOME/auth.json` | [auth docs](https://developers.openai.com/codex/auth), [`get_auth_file`](https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/storage.rs) |
| User config | `$CODEX_HOME/config.toml` | CLI / config docs |
| Standalone packages (installer) | `$CODEX_HOME/packages/standalone/…` | [install.sh](https://github.com/openai/codex/blob/main/scripts/install/install.sh) |
| MCP OAuth file store (if file mode) | `$CODEX_HOME/.credentials.json` | config types / defaults |

`cli_auth_credentials_store`: `file` \| `keyring` \| `auto` (packaged defaults.toml sets `cli_auth_credentials_store = "file"`). For containers without a useful OS keyring, **`file`** keeps tokens on disk under `CODEX_HOME` ([auth docs](https://developers.openai.com/codex/auth), [defaults.toml](https://github.com/openai/codex/blob/main/codex-rs/config/defaults.toml)).

### Implication for this Add-on’s ADR-0002 layout

Today: `HOME=/config`, Provider home via `XDG_*` → `/data/home`, T3 state `/data/t3`.

Without an extra env var, Codex would write **`/config/.codex/auth.json`** (Workspace), not under `/data/home`. For credentials to survive on Provider home like Cursor:

1. `mkdir -p /data/home/.codex`
2. Export **`CODEX_HOME=/data/home/.codex`** at runtime
3. Prefer `cli_auth_credentials_store = "file"` in `$CODEX_HOME/config.toml` if keyring would otherwise be chosen

Keep **image-baked binaries** under the build user’s install tree (e.g. `/root/.local/bin` + `/root/.codex/packages/…`) and **do not** point build-time `CODEX_HOME` at the persistent volume unless you intentionally want packages on `/data` too. Runtime `CODEX_HOME` for auth/config can differ from the directory that held the standalone package at image build time; the `codex` symlink target remains the image-local release dir.

---

## Auto-update behaviour

| Mechanism | Behaviour |
| --- | --- |
| Docs “Update” | Re-run `curl -fsSL https://chatgpt.com/codex/install.sh \| sh` ([CLI docs](https://developers.openai.com/codex/cli)) |
| `codex update` | Applies an update when the install method supports self-update ([CLI reference](https://developers.openai.com/codex/cli/reference)) |
| Startup check | `check_for_update_on_startup` — schema: *defaults to `true`*; set `false` when updates are centrally managed ([config.schema.json](https://github.com/openai/codex/blob/main/codex-rs/core/config.schema.json)) |
| Standalone apply command | `sh -c 'curl -fsSL https://chatgpt.com/codex/install.sh \| CODEX_NON_INTERACTIVE=1 sh'` — **no `--release`**, so it floats to current latest ([update_action.rs](https://github.com/openai/codex/blob/main/codex-rs/tui/src/update_action.rs)) |

For a pin-friendly Add-on image: bake a fixed `CODEX_RELEASE`, put `check_for_update_on_startup = false` in managed/`CODEX_HOME` config (or equivalent requirements layer), and treat Add-on rebuild as the upgrade path—same idea as pinning `t3` while controlling Cursor float ([t3-cursor-pin-upgrade.md](./t3-cursor-pin-upgrade.md)).

---

## Pin-friendly install recipe (Debian glibc container)

Illustrative Dockerfile fragment for `ghcr.io/home-assistant/base-debian` (or bookworm/trixie slim). Replace `0.149.1` with the chosen pin.

```dockerfile
ARG CODEX_VERSION=0.149.1
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl tar \
  && curl -fsSL https://chatgpt.com/codex/install.sh \
     | CODEX_RELEASE="${CODEX_VERSION}" CODEX_NON_INTERACTIVE=1 sh \
  && ln -sf /root/.local/bin/codex /usr/local/bin/codex \
  && codex --version \
  && rm -rf /var/lib/apt/lists/*
ENV PATH="/root/.local/bin:${PATH}"
```

Runtime (align with ADR-0002 Provider home; not implemented here):

```bash
mkdir -p /data/home/.codex
export CODEX_HOME=/data/home/.codex
# optional: force file store via $CODEX_HOME/config.toml
# cli_auth_credentials_store = "file"
# check_for_update_on_startup = false
printenv OPENAI_API_KEY | codex login --with-api-key   # or device-auth / copied auth.json
codex login status
```

Direct-pin alternative without the installer script: download checksummed `codex-package-<arch>-unknown-linux-musl.tar.gz` (or the single-binary tarball) from `https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/…` or `https://releases.openai.com/codex/releases/${CODEX_VERSION}/…`, verify digests, place under a fixed image path, and symlink `codex` onto `PATH`.

npm pin alternative (needs Node already in the image, as with current T3 bake): `npm install -g "@openai/codex@${CODEX_VERSION}"`.

---

## Open points (facts only; not decided here)

- Whether T3’s Codex provider expects `OPENAI_API_KEY` in the process env, a completed `codex login`, or both — out of scope for this CLI research ticket; verify against T3 provider wiring when implementing.
- Image size cost of shipping both `amd64` and `aarch64` musl packages — map fog in [#27](https://github.com/wiggo-dev/ha-t3code/issues/27).
- Multi-account Codex — deferred on the same map.
