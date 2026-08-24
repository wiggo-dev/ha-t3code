# OpenCode CLI install and auth in Debian (glibc) containers

Research for [ha-t3code#32](https://github.com/wiggo-dev/ha-t3code/issues/32) (map [#27](https://github.com/wiggo-dev/ha-t3code/issues/27)). Primary sources only: [opencode.ai/docs](https://opencode.ai/docs/), [CLI](https://opencode.ai/docs/cli/), [Providers](https://opencode.ai/docs/providers/), [Config](https://opencode.ai/docs/config/), [Skills](https://opencode.ai/docs/skills/), [Troubleshooting](https://opencode.ai/docs/troubleshooting/), the live [install script](https://opencode.ai/install) (fetched 2026-08-24), and [anomalyco/opencode GitHub Releases](https://github.com/anomalyco/opencode/releases) (tag `v1.18.22` checked 2026-08-24). Related in-repo notes: [skill-discovery-paths.md](./skill-discovery-paths.md), [cursor-cli-container-auth.md](./cursor-cli-container-auth.md), [ADR-0001](../adr/0001-debian-base-server-side-cursor.md).

**Scope:** facts for baking `opencode` into a Debian glibc Home Assistant Add-on image. No implementation in this ticket.

---

## Summary

**OpenCode ships first-class Linux glibc and musl binaries for `x64` and `arm64`.** On Debian (glibc), the install script selects the non-`musl` tarball (e.g. `opencode-linux-arm64.tar.gz`). Empirically, that binary is an ELF dynamically linked against `/lib/ld-linux-aarch64.so.1` (glibc), so it matches the Add-on’s Debian base (ADR-0001) rather than Alpine/musl.

**Auth is BYOK-friendly for headless containers:** API keys via `opencode auth login` / TUI `/connect` land in `~/.local/share/opencode/auth.json`; startup also loads keys from the environment and a project `.env`. Config can inject keys with `{env:VAR}` / `{file:path}`. Browser OAuth exists for some subscriptions (e.g. ChatGPT Plus/Pro, Claude Pro/Max) and is a poor fit for HA OS without a workaround.

**Skills:** upstream OpenCode discovers workspace `.agents/skills/<name>/SKILL.md` (and global `~/.agents/skills/`) alongside `.opencode/skills/` and `.claude/skills/`. That aligns with this repo’s Workspace Skills layout. A separate community OpenCode HA add-on uses different paths (`.opencode/skills` under `/config`, bundled skills under `/data/.config/opencode/skills/`) — operator confusion risk, not a filesystem conflict if T3 stays on `.agents/skills/`.

**Pinning:** install script accepts `--version` / `VERSION`; releases are tagged on GitHub. **Auto-update downloads on startup by default** (`autoupdate` config / `OPENCODE_DISABLE_AUTOUPDATE`) — must be disabled for a stable Add-on pin.

---

## Install methods

### Official one-liner ([Intro](https://opencode.ai/docs/))

```bash
curl -fsSL https://opencode.ai/install | bash
```

Also documented:

| Method | Command / surface |
| --- | --- |
| npm | `npm install -g opencode-ai` |
| Homebrew | `brew install anomalyco/tap/opencode` (recommended tap); `brew install opencode` (less frequent) |
| Arch | `pacman` / AUR |
| Windows | Chocolatey, Scoop, npm, Mise |
| Docker | `docker run -it --rm ghcr.io/anomalyco/opencode` |
| Manual | [GitHub Releases](https://github.com/anomalyco/opencode/releases) binaries |

Binary command name: **`opencode`**.

### What the install script does ([opencode.ai/install](https://opencode.ai/install), 2026-08-24)

1. Resolves OS (`linux` | `darwin` | `windows`) and arch (`x64` | `arm64`; maps `x86_64`→`x64`, `aarch64`→`arm64`).
2. Supported combos: `linux-x64`, `linux-arm64`, `darwin-x64`, `darwin-arm64`, `windows-x64` only — anything else exits.
3. On Linux, detects **musl** if `/etc/alpine-release` exists or `ldd --version` reports musl → appends `-musl` to the target.
4. On **x64**, if AVX2 is missing from `/proc/cpuinfo`, appends `-baseline`.
5. Downloads `opencode-<target>.tar.gz` (Linux) from GitHub Releases (`…/latest/download/…` or `…/download/v<ver>/…`).
6. Extracts binary to **`$HOME/.opencode/bin/opencode`** (mode `755`).
7. Optionally appends that dir to the user’s shell rc unless `--no-modify-path`.
8. Version pin: `--version <ver>`, or env `VERSION=<ver>` (leading `v` stripped).

Dependencies implied by the script: `bash`, `curl`, `tar` (Linux).

**Install dir note:** the live installer hardcodes `$HOME/.opencode/bin`. It does **not** honor alternate install-dir env vars in the fetched script. For containers, set `HOME` deliberately and put `$HOME/.opencode/bin` (or a symlink) on `PATH`.

### Linux release asset matrix (`v1.18.22`)

| Asset | Intended libc / CPU |
| --- | --- |
| `opencode-linux-x64.tar.gz` | glibc, AVX2 |
| `opencode-linux-x64-baseline.tar.gz` | glibc, no AVX2 |
| `opencode-linux-x64-musl.tar.gz` | musl, AVX2 |
| `opencode-linux-x64-baseline-musl.tar.gz` | musl, no AVX2 |
| `opencode-linux-arm64.tar.gz` | glibc |
| `opencode-linux-arm64-musl.tar.gz` | musl |

Desktop `.deb` / `.rpm` / AppImage assets also exist; for an Add-on bake, the CLI tarball (or npm) is the relevant surface.

### Empirical glibc check (2026-08-24)

Downloaded `opencode-linux-arm64.tar.gz` @ `v1.18.22`:

- `file`: `ELF 64-bit LSB executable, ARM aarch64`, **dynamically linked**, interpreter **`/lib/ld-linux-aarch64.so.1`**, `for GNU/Linux 3.7.0`.
- Size ≈ 176 MB uncompressed binary.

That interpreter is the glibc dynamic linker, not musl’s `ld-musl-*`. **Debian glibc is the correct Add-on base** (same conclusion as Cursor — ADR-0001). On Alpine/musl the installer would pick `*-musl` assets instead.

### Container pin recipe (Debian glibc)

Prefer pinning at **image build**, not at container start:

```dockerfile
ARG OPENCODE_VERSION=1.18.22
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates tar bash \
  && curl -fsSL https://opencode.ai/install | bash -s -- --version "${OPENCODE_VERSION}" --no-modify-path \
  && ln -sf /root/.opencode/bin/opencode /usr/local/bin/opencode \
  && opencode --version \
  && rm -rf /var/lib/apt/lists/*
ENV PATH="/root/.opencode/bin:${PATH}"
# Disable runtime auto-update (see Autoupdate section)
ENV OPENCODE_DISABLE_AUTOUPDATE=1
```

Alternatives with the same pin:

```bash
# Direct release URL (explicit arch/libc)
curl -fsSL -o /tmp/oc.tgz \
  "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-arm64.tar.gz"
tar -xzf /tmp/oc.tgz -C /usr/local/bin opencode

# npm
npm install -g "opencode-ai@${OPENCODE_VERSION}"
```

Use `linux-x64` / `linux-x64-baseline` / `linux-arm64` to match the build arch; do **not** use `*-musl` on Debian.

---

## Auth and BYOK

### CLI / TUI surfaces ([CLI](https://opencode.ai/docs/cli/), [Providers](https://opencode.ai/docs/providers/))

| Surface | Role |
| --- | --- |
| `opencode auth login` | Interactive provider login; flags `--provider` / `-p`, `--method` / `-m` |
| `opencode auth list` / `ls` | List credentials file entries |
| `opencode auth logout` | Clear a provider from the credentials file |
| TUI `/connect` | Same credential store; documented throughout Providers |

Credentials from `/connect` / `auth login` are stored in **`~/.local/share/opencode/auth.json`**.

On startup, OpenCode loads providers from that file **and** any keys in the **environment** or a project **`.env`** ([CLI auth](https://opencode.ai/docs/cli/)).

### BYOK / headless-friendly patterns

1. **API key via `auth login` / `/connect` “Manually enter API Key”** — works for OpenCode Zen/Go, OpenRouter, Groq, Anthropic (manual key), OpenAI (manual key), and most listed providers. Result: `auth.json` on disk → persist under a durable `HOME`.
2. **Environment / `.env`** — documented load path; good for Add-on secrets injected at start (no interactive TUI).
3. **Config substitution** ([Config](https://opencode.ai/docs/config/)) — e.g. `"apiKey": "{env:ANTHROPIC_API_KEY}"` or `"{file:~/.secrets/openai-key}"` under `provider.<id>.options`.
4. **Provider-native env-only auth** — e.g. Amazon Bedrock (`AWS_*` / `AWS_BEARER_TOKEN_BEDROCK`), Google Vertex (`GOOGLE_APPLICATION_CREDENTIALS`, etc.); Providers doc notes Bedrock-style env auth may not appear in `opencode auth list`.

### Browser / subscription OAuth (worse for HA OS)

| Provider | Documented methods |
| --- | --- |
| OpenAI | ChatGPT Plus/Pro (opens browser) **or** Manually enter API Key |
| Anthropic | Claude Pro/Max (opens browser) **or** Manually enter API Key; docs state Anthropic prohibits third-party Claude Pro/Max plugins; bundled plugins removed as of 1.3.0 |
| OpenCode Zen / Go | Sign in at [opencode.ai/auth](https://opencode.ai/auth), paste API key (no subscription OAuth required for the key itself) |
| DigitalOcean / others | Some offer OAuth **or** paste key / env |

For server-side Add-on use, prefer **API keys (or env/config injection)** over browser OAuth.

### Headless / non-TUI execution

- `opencode run "…"` — non-interactive prompt ([CLI](https://opencode.ai/docs/cli/)).
- `opencode serve` / `opencode web` / `opencode acp` — headless server / ACP; optional `OPENCODE_SERVER_PASSWORD` / `OPENCODE_SERVER_USERNAME` for HTTP basic auth.
- T3 wiring of OpenCode is out of scope here; this note only covers the upstream CLI auth/install surface.

---

## Credential and data paths

Paths are under `HOME` (and standard XDG layouts). In HA Add-ons, point `HOME` (or bind-mount the dirs below) at a **persistent volume**.

| Path | Contents | Source |
| --- | --- | --- |
| `~/.local/share/opencode/auth.json` | API keys, OAuth tokens | [Providers](https://opencode.ai/docs/providers/), [Troubleshooting](https://opencode.ai/docs/troubleshooting/), [CLI](https://opencode.ai/docs/cli/) |
| `~/.local/share/opencode/log/` | Timestamped logs (keeps recent 10) | Troubleshooting |
| `~/.local/share/opencode/project/` | Session / message storage | Troubleshooting |
| `~/.config/opencode/opencode.json` (or `.jsonc`) | Global config (providers, `autoupdate`, permissions, …) | [Config](https://opencode.ai/docs/config/) |
| `~/.config/opencode/tui.json` | TUI-only settings | Config |
| `~/.config/opencode/skills/` | Global OpenCode-native skills | [Skills](https://opencode.ai/docs/skills/) |
| `~/.cache/opencode` | Cached provider packages (clear on package errors) | Troubleshooting |
| `$HOME/.opencode/bin/opencode` | Installed CLI binary (install script) | [install script](https://opencode.ai/install) |

Overrides: `OPENCODE_CONFIG`, `OPENCODE_CONFIG_DIR`, `OPENCODE_CONFIG_CONTENT`, `OPENCODE_TUI_CONFIG` ([CLI](https://opencode.ai/docs/cli/) / [Config](https://opencode.ai/docs/config/)).

Linux managed config (admin): `/etc/opencode/` ([Config](https://opencode.ai/docs/config/)).

---

## Skills paths vs Workspace `.agents/skills`

Upstream OpenCode ([Skills](https://opencode.ai/docs/skills/)) loads:

| Scope | Path |
| --- | --- |
| Project | `.opencode/skills/<name>/SKILL.md` |
| Global | `~/.config/opencode/skills/<name>/SKILL.md` |
| Project Claude-compat | `.claude/skills/<name>/SKILL.md` |
| Global Claude-compat | `~/.claude/skills/<name>/SKILL.md` |
| Project agent-compat | **`.agents/skills/<name>/SKILL.md`** |
| Global agent-compat | **`~/.agents/skills/<name>/SKILL.md`** |

Project-local discovery walks from cwd up to the git worktree. Required frontmatter: `name`, `description` (`name` must match directory).

**Implication for T3 / this Add-on:** digest-synced Workspace Skills under `/config/.agents/skills/` (or repo `.agents/skills/`) are on OpenCode’s documented discovery list. No symlink into `.opencode/skills/` is required for upstream OpenCode to see them.

**OpenCode HA add-on (separate product):** uses `/config/.opencode/skills/` for user skills and copies bundled HA skills into `/data/.config/opencode/skills/` ([skill-discovery-paths.md](./skill-discovery-paths.md)). Operators who have used that add-on may look for `.opencode/skills` first. Shipping OpenCode inside **this** Add-on does not by itself install those HA-bundled skills; document the `.agents/skills` Workspace path to avoid mixed expectations.

Disable Claude-compat skill loading if needed: `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS` / related flags ([CLI](https://opencode.ai/docs/cli/)).

---

## Autoupdate and pinning policy surface

| Mechanism | Behavior | Source |
| --- | --- | --- |
| Config `autoupdate` | Default example shows `true`; **downloads updates on startup**. Set `false` to disable, or `"notify"` to notify only (not for package-manager installs) | [Config](https://opencode.ai/docs/config/) |
| `OPENCODE_DISABLE_AUTOUPDATE` | Env boolean to disable automatic update checks | [CLI](https://opencode.ai/docs/cli/) |
| `opencode upgrade` / `opencode upgrade vX.Y.Z` | Manual upgrade; `--method` for curl/npm/pnpm/bun/brew | [CLI](https://opencode.ai/docs/cli/) |
| Install `--version` / `VERSION` | Pins the binary fetched at install time | [install script](https://opencode.ai/install) |

For an Add-on image:

1. Pin version at **build** (`--version` or pinned npm / direct tarball URL).
2. Set **`autoupdate: false`** in global config and/or **`OPENCODE_DISABLE_AUTOUPDATE=1`** so the container does not float the CLI at runtime.
3. Bump the pin by rebuilding the Add-on (same pattern as `t3` npm pin in [t3-cursor-pin-upgrade.md](./t3-cursor-pin-upgrade.md)).

---

## Architecture checklist for HA OS

| Concern | Finding |
| --- | --- |
| glibc Debian Add-on | Supported via non-`musl` Linux tarballs; matches ADR-0001 |
| Alpine / musl | Separate `*-musl` assets; installer auto-selects when musl detected |
| `amd64` / `aarch64` | Both `linux-x64` and `linux-arm64` published |
| Old x86_64 without AVX2 | Use `linux-x64-baseline` (installer detects) |
| Binary size | ~40–45 MB compressed tarball; ~176 MB arm64 binary (v1.18.22) — image-size fog for map #27 |
| Command | `opencode` (not `agent` / `cursor-agent`) |

---

## Gaps / unknowns (not claimed)

- Exact T3 Code OpenCode provider spawn flags, settings keys, and skills picker wiring — not covered by OpenCode primary docs; defer to T3 sources when implementing.
- Whether browser OAuth can complete headlessly inside HA (device-code / printed URL) — **not documented** on opencode.ai for Anthropic/OpenAI; treat as unsupported unless proven.
- Checksums / cosign for release assets — not verified in this pass; pin by tag + HTTPS GitHub URL only.
- npm package contents vs GitHub binary parity beyond shared version `1.18.22` and bin name `opencode` — assumed equivalent for install purposes; prefer one install path in the Dockerfile.

---

## Sources checklist

1. https://opencode.ai/docs/ (install methods, `/connect` intro)
2. https://opencode.ai/docs/cli/ (auth, upgrade, env vars, `run`/`serve`/`acp`)
3. https://opencode.ai/docs/providers/ (`auth.json`, Zen/Go, Anthropic/OpenAI methods, env-based providers)
4. https://opencode.ai/docs/config/ (paths, `{env:}`/`{file:}`, `autoupdate`)
5. https://opencode.ai/docs/skills/ (`.agents/skills` and siblings)
6. https://opencode.ai/docs/troubleshooting/ (storage layout, cache)
7. https://opencode.ai/install (arch/musl/baseline, `$HOME/.opencode/bin`, `--version`)
8. https://github.com/anomalyco/opencode/releases (asset names; `v1.18.22` sample)
9. Empirical: `file` on `opencode-linux-arm64` @ `v1.18.22`
