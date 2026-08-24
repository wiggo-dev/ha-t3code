# T3 Code non-Cursor providers on a headless Linux server

Research for [ha-t3code#28](https://github.com/wiggo-dev/ha-t3code/issues/28). Primary sources: [pingdotgg/t3code](https://github.com/pingdotgg/t3code) tag **`v0.0.33`** (the version pinned in this Add-on’s [`t3code/Dockerfile`](../../t3code/Dockerfile)); T3 user docs ([`docs/user/install.md`](https://github.com/pingdotgg/t3code/blob/v0.0.33/docs/user/install.md), [`providers-codex.md`](https://github.com/pingdotgg/t3code/blob/v0.0.33/docs/user/providers-codex.md), [`providers-claude.md`](https://github.com/pingdotgg/t3code/blob/v0.0.33/docs/user/providers-claude.md)); T3 internals ([`docs/internals/providers.md`](https://github.com/pingdotgg/t3code/blob/v0.0.33/docs/internals/providers.md)); official provider docs for [Codex](https://developers.openai.com/codex/auth), [Claude Code](https://code.claude.com/docs/en/authentication), [Grok Build](https://docs.x.ai/build/overview), and [OpenCode](https://opencode.ai/docs/cli/). Related: [t3-cursor-provider.md](./t3-cursor-provider.md).

**Scope:** how T3 discovers, enables, spawns, and authenticates **Codex**, **Claude**, **Grok Build**, and **OpenCode** on the machine running `t3 serve` (Add-on container), compared to Cursor. Facts only; Add-on bake/auth policy is deferred.

---

## Summary

T3 does **not** ship any of these CLIs. On a headless server (`t3 serve`), each provider is a **server-side** driver that resolves a binary on the server’s `PATH` (or Settings **Binary path**), probes health on startup / ~5-minute refresh, and spawns a per-session child process. Auth is delegated to that CLI on the **server** (login / API key / seeded credential files) — never to the pairing desktop/phone client.

| Provider | Default binary | Settings `enabled` default | Session transport | Auth probe (T3) |
| --- | --- | --- | --- | --- |
| **Cursor** (baseline) | `cursor-agent` | **`false`** (opt-in) | ACP: `cursor-agent acp` | `cursor-agent about` → email / login |
| **Codex** | `codex` | **`true`** | JSON-RPC over stdio: `codex app-server` | app-server `account/read` |
| **Claude** | `claude` | **`true`** | Claude Agent SDK (spawns resolved `claude` executable) | SDK init → account / tokenSource |
| **Grok** | `grok` | **`true`** | ACP: `grok agent stdio` | `grok --version` + ACP model discovery; **auth always `unknown` in probe** |
| **OpenCode** | `opencode` | **`true`** | HTTP: T3 spawns `opencode serve` (or connects to **Server URL**) | `opencode --version` + models inventory; auth ≈ “≥1 upstream provider connected” |

Common Add-on implications: bake each CLI into the image, put it on `PATH` (or set absolute **Binary path**), persist provider home/auth under `/data`, run login (or inject API keys) **inside** the container, and remember Cursor is the only built-in driver that defaults to **disabled**.

---

## Shared T3 server behavior

Sources: [`docs/user/install.md`](https://github.com/pingdotgg/t3code/blob/v0.0.33/docs/user/install.md), [`docs/internals/providers.md`](https://github.com/pingdotgg/t3code/blob/v0.0.33/docs/internals/providers.md), [`packages/contracts/src/settings.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/packages/contracts/src/settings.ts), [`ProviderInstanceEnvironment.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/ProviderInstanceEnvironment.ts), [`makeManagedServerProvider`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/makeManagedServerProvider.ts) (same cadence as Cursor research).

- **Five built-in drivers:** `codex`, `claudeAgent`, `cursor`, `grok`, `opencode`.
- **Discovery runs on the T3 server process** (Add-on), not on the client.
- **Binary discovery:** CLI on server `PATH`, or Settings → provider instance → **Binary path** (command name or absolute path).
- **Auth timing:** required before starting a session with that provider, not before starting T3.
- **Login location:** run provider login on the machine running `t3 serve`.
- **Env overrides:** per-instance **Environment** vars merge over `process.env` (`mergeProviderInstanceEnvironment`).
- **Health refresh:** `DEFAULT_PROVIDER_HEALTH_REFRESH_INTERVAL` = **5 minutes**.
- **Multi-instance:** Codex, Claude, Grok, and OpenCode drivers all declare `supportsMultipleInstances: true`. Cursor baseline is covered in [t3-cursor-provider.md](./t3-cursor-provider.md).

User-facing login cheat sheet from T3 install docs:

| Provider | CLI docs | Default binary | Log in with |
| --- | --- | --- | --- |
| Codex | [Codex CLI](https://developers.openai.com/codex/cli) | `codex` | `codex login` |
| Claude | [Claude Code](https://claude.com/product/claude-code) | `claude` | `claude auth login` |
| Cursor | [Cursor CLI](https://cursor.com/cli) | `cursor-agent` | `agent login` |
| Grok Build | [Grok Build CLI](https://x.ai/cli) | `grok` | `grok login` |
| OpenCode | [OpenCode](https://opencode.ai) | `opencode` | `opencode auth login` |

---

## Codex

### Settings defaults

From [`CodexSettings`](https://github.com/pingdotgg/t3code/blob/v0.0.33/packages/contracts/src/settings.ts):

| Field | Default | Notes |
| --- | --- | --- |
| `enabled` | **`true`** | Hidden in settings form |
| `binaryPath` | `codex` | Empty → `codex` |
| `homePath` | `""` | UI: **CODEX_HOME path** (placeholder `~/.codex`) |
| `shadowHomePath` | `""` | Account-specific overlay; keeps `auth.json` separate |
| `launchArgs` | `""` | Extra args after `app-server` |
| `customModels` | `[]` | Hidden |

Package hints in [`CodexDriver.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Drivers/CodexDriver.ts): npm `@openai/codex`, Homebrew `codex`.

### Spawn / protocol

Probe and sessions use **`codex app-server`** (stdio JSON-RPC via `effect-codex-app-server`):

```text
<binaryPath> app-server [<launchArgs…>]
```

- Args builder: [`codexAppServerArgs`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Layers/codexLaunchArgs.ts).
- Optional env override: `T3CODE_CODEX_LAUNCH_ARGS` wins over Settings `launchArgs`.
- `CODEX_HOME` is set from expanded `homePath` / shadow layout; `~` is expanded in T3 because spawn does not shell-expand env values ([`CodexProvider.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Layers/CodexProvider.ts)).
- Text generation uses `codex exec` with a filtered subset of launch args (`codexExecLaunchArgs`).

Shadow-home mode ([`CodexHomeLayout.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Drivers/CodexHomeLayout.ts), [`providers-codex.md`](https://github.com/pingdotgg/t3code/blob/v0.0.33/docs/user/providers-codex.md)): shared `CODEX_HOME` + `shadowHomePath` with private `auth.json` and symlinks for shared state — for multi-account on one workspace.

### Auth probe

[`checkCodexProviderStatus`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Layers/CodexProvider.ts) / `probeCodexAppServerProvider`:

1. Enabled gate (default on).
2. Spawn `codex app-server`, `initialize`, then **`account/read`**.
3. Timeout: `AUTH_PROBE_TIMEOUT_MS` = **10s** ([`providerSnapshot.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/providerSnapshot.ts)).
4. If no account and `requiresOpenaiAuth` → **unauthenticated**, message: run `` `codex login` ``.
5. If authenticated → also `skills/list` + model list.

Version is parsed from app-server `userAgent`, not from `codex --version`.

### Env / path overrides

| Mechanism | Role |
| --- | --- |
| Settings **Binary path** | Override `codex` |
| Settings **CODEX_HOME path** / **Shadow home path** | Home + multi-account |
| Settings **Launch arguments** / `T3CODE_CODEX_LAUNCH_ARGS` | Extra `app-server` args |
| Instance **Environment** | Arbitrary env (API keys, etc.) |
| `CODEX_HOME` | Set by T3 when home/shadow resolved |

### Official auth (headless-relevant)

From [Codex authentication](https://developers.openai.com/codex/auth) and [CI/CD auth](https://developers.openai.com/codex/auth/ci-cd-auth):

- Interactive: `codex login` (browser OAuth) or `printenv OPENAI_API_KEY | codex login --with-api-key`.
- Headless ChatGPT login: `codex login --device-auth` (when enabled on the account), or **seed** `~/.codex/auth.json` from a trusted machine and persist it (treat as a secret; allow refresh in place).
- Automation docs also describe `CODEX_API_KEY` for **`codex exec`** only — T3 sessions use **app-server**, so prefer cached `auth.json` / `codex login --with-api-key` / OpenAI auth wired into Codex home, not assuming `CODEX_API_KEY` alone authenticates app-server the way Cursor’s `CURSOR_API_KEY` does for ACP.

### Add-on caveats

- Persist `CODEX_HOME` (default `~/.codex`) under Provider home / `/data`.
- Prefer device-code or seeded `auth.json` / API-key login over browser OAuth in the container.
- Expand home paths in Settings (T3 expands `~`; raw `CODEX_HOME=~/...` in env without expansion fails).

---

## Claude

### Settings defaults

From [`ClaudeSettings`](https://github.com/pingdotgg/t3code/blob/v0.0.33/packages/contracts/src/settings.ts):

| Field | Default | Notes |
| --- | --- | --- |
| `enabled` | **`true`** | Hidden |
| `binaryPath` | `claude` | |
| `homePath` | `""` | UI: **CLAUDE_CONFIG_DIR path** |
| `launchArgs` | `""` | Extra CLI args on session start |
| `customModels` | `[]` | Hidden |

Driver kind: `claudeAgent`. Package hints: npm `@anthropic-ai/claude-code`, Homebrew `claude-code`, native `claude update` ([`ClaudeDriver.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Drivers/ClaudeDriver.ts)).

### Spawn / protocol

Sessions are **not** a simple `claude acp` CLI. T3 uses **`@anthropic-ai/claude-agent-sdk`** `query()` ([`ClaudeAdapter.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Layers/ClaudeAdapter.ts)), with `pathToClaudeCodeExecutable` resolved from Settings binary ([`ClaudeExecutable.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Drivers/ClaudeExecutable.ts)).

- Bare `claude` is resolved against `PATH` for the SDK (SDK spawn has no shell/`PATHEXT` resolution).
- Config isolation uses **`CLAUDE_CONFIG_DIR`**, not `HOME` ([`ClaudeHome.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Drivers/ClaudeHome.ts), [`providers-claude.md`](https://github.com/pingdotgg/t3code/blob/v0.0.33/docs/user/providers-claude.md)): overriding `HOME` breaks keychain / OAuth lookup (“Not logged in”).

### Auth probe

[`checkClaudeProviderStatus`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Layers/ClaudeProvider.ts):

1. Enabled gate.
2. **`claude --version`** (timeout `DEFAULT_TIMEOUT_MS` = **4s**).
3. Capabilities via **`probeClaudeCapabilities`**: lightweight Agent SDK session (never yields a user prompt); reads init account (`email`, `subscriptionType`, `tokenSource`, `apiProvider`). Timeout **25s** (Bedrock-friendly). Cached ~5 minutes per instance.
4. Success → `auth.status: "authenticated"` (+ email / subscription or API-key label). Failure to get capabilities → **warning**, auth `unknown` (“Could not verify Claude authentication status…”).
5. Model list gated by CLI semver (Opus 4.7 / 4.8 / Fable 5 / Opus 5 minima in source).

T3 user docs login: **`claude auth login`**. Multi-account: separate `CLAUDE_CONFIG_DIR` per instance. OpenRouter / routers: instance env (`ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, empty `ANTHROPIC_API_KEY`, etc.) per [`providers-claude.md`](https://github.com/pingdotgg/t3code/blob/v0.0.33/docs/user/providers-claude.md).

### Env / path overrides

| Mechanism | Role |
| --- | --- |
| Settings **Binary path** | `claude` executable |
| Settings **CLAUDE_CONFIG_DIR path** | Sets `CLAUDE_CONFIG_DIR` only |
| Settings **Launch arguments** | Passed into SDK/CLI launch |
| Instance env | e.g. `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `CLAUDE_CODE_OAUTH_TOKEN` |

### Official auth (headless-relevant)

From [Claude Code authentication](https://code.claude.com/docs/en/authentication) / [env vars](https://code.claude.com/docs/en/env-vars):

- Default interactive: browser `/login` / first-run OAuth.
- Headless-friendly: **`ANTHROPIC_API_KEY`** (Console key; used in non-interactive mode when set), **`ANTHROPIC_AUTH_TOKEN`**, or **`CLAUDE_CODE_OAUTH_TOKEN`** from `claude setup-token` (setup-token itself still needs a one-time browser approval somewhere).
- Do not confuse T3’s documented `claude auth login` with Claude’s in-TUI `/login` — both target Claude Code credentials; use whichever the installed CLI version documents.

### Add-on caveats

- Persist Claude config dir (default under `~/.claude` / `.claude.json` layout) on `/data`; set **CLAUDE_CONFIG_DIR path** if not using default `HOME`.
- **Never** point Claude at a fake `HOME` for isolation — use `CLAUDE_CONFIG_DIR`.
- API-key / OAuth-token env on the provider instance is the cleanest Add-on path; browser login inside HA OS is awkward.

---

## Grok Build

### Settings defaults

From [`GrokSettings`](https://github.com/pingdotgg/t3code/blob/v0.0.33/packages/contracts/src/settings.ts):

| Field | Default | Notes |
| --- | --- | --- |
| `enabled` | **`true`** | Hidden |
| `binaryPath` | `grok` | |
| `customModels` | `[]` | Hidden |

No home-path setting in schema. Maintenance is **manual-only** resolver ([`GrokDriver.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Drivers/GrokDriver.ts)) — no npm/Homebrew auto-update metadata like Codex/Claude/OpenCode.

### Spawn / protocol

ACP over stdio ([`GrokAcpSupport.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/acp/GrokAcpSupport.ts)):

```text
<binaryPath> agent stdio
```

Default binary `grok` → `grok agent stdio`. Env injected: `GROK_OAUTH2_REFERRER=t3code`. ACP auth method id: `xai.api_key` if `XAI_API_KEY` is set, else `cached_token`.

Matches official [Headless & Scripting / ACP](https://docs.x.ai/build/cli/headless-scripting) (`grok agent stdio`).

### Auth probe

[`checkGrokProviderStatus`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Layers/GrokProvider.ts):

1. Enabled gate.
2. **`grok --version`** (4s timeout).
3. ACP model discovery (15s) via same `grok agent stdio` runtime.
4. On success → `status: "ready"` but **`auth: { status: "unknown" }`** always — T3 does **not** surface Grok login email/tier in the health probe (unlike Cursor/Codex/Claude).

Missing binary message: ``Grok CLI (`grok`) is not installed or not on PATH.``

### Env / path overrides

| Mechanism | Role |
| --- | --- |
| Settings **Binary path** | Override `grok` |
| Instance / process `XAI_API_KEY` | Selects ACP `xai.api_key` auth method |
| Official `~/.grok/` | Config + `auth.json` from `grok login` ([install script](https://x.ai/cli/install.sh)) |

### Official auth (headless-relevant)

From [Grok overview](https://docs.x.ai/build/overview), [CLI reference](https://docs.x.ai/build/cli/reference), [enterprise auth](https://docs.x.ai/build/enterprise):

- Browser: `grok login`.
- Headless/SSH/containers: **`grok login --device-auth`**.
- Automation: **`XAI_API_KEY`**.
- Install places binaries under `~/.grok/bin` and symlinks **both `grok` and `agent`** onto PATH candidates ([`install.sh`](https://x.ai/cli/install.sh)).

### Add-on caveats — PATH collision with Cursor

This is the collision T3 already fixed for Cursor:

- Grok installer symlinks **`agent`** → same binary as `grok` ([install script](https://x.ai/cli/install.sh); [t3code#3478](https://github.com/pingdotgg/t3code/issues/3478), [PR #4094](https://github.com/pingdotgg/t3code/pull/4094)).
- Cursor’s old default binary was `agent`; with Grok earlier on `PATH`, T3 spawned Grok for Cursor ACP.
- Current T3 default is **`cursor-agent`**; this Add-on already wraps/installs `cursor-agent` and also links `agent` → Cursor ([`t3code/Dockerfile`](../../t3code/Dockerfile)). **If Grok is later baked in and its installer rewrites `/usr/local/bin/agent` (or prepends `~/.grok/bin`), Cursor’s `agent` symlink and any leftover Settings `binaryPath: agent` can break.** Prefer keeping Cursor on absolute/`cursor-agent` and Grok on `grok` only; avoid relying on the bare `agent` name when both exist.

---

## OpenCode

### Settings defaults

From [`OpenCodeSettings`](https://github.com/pingdotgg/t3code/blob/v0.0.33/packages/contracts/src/settings.ts):

| Field | Default | Notes |
| --- | --- | --- |
| `enabled` | **`true`** | Hidden |
| `binaryPath` | `opencode` | |
| `serverUrl` | `""` | Blank → T3 spawns server when needed |
| `serverPassword` | `""` | “Stored in plain text on disk”; Basic auth |
| `customModels` | `[]` | Hidden |

Minimum CLI version: **`1.14.19`** ([`OpenCodeProvider.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Layers/OpenCodeProvider.ts)). Package hints: npm `opencode-ai`, Homebrew `anomalyco/tap/opencode`, native `opencode upgrade` ([`OpenCodeDriver.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Drivers/OpenCodeDriver.ts)).

No dedicated `docs/user/providers-opencode.md` at v0.0.33 (unlike Codex/Claude).

### Spawn / protocol

[`opencodeRuntime.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/opencodeRuntime.ts) + [`OpenCodeAdapter.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Layers/OpenCodeAdapter.ts):

- **Default:** spawn local server:

  ```text
  <binaryPath> serve --hostname=<host> --port=<port>
  ```

  Wait for stdout line prefix `opencode server listening` (default start timeout 30s). Sets `OPENCODE_CONFIG_CONTENT={}`.
- **External:** Settings **Server URL** → connect only (no spawn); optional **Server password** → HTTP Basic `opencode:<password>` (same convention as OpenCode’s `OPENCODE_SERVER_PASSWORD`).
- Session API is HTTP SDK against that server (not ACP/stdio like Cursor/Grok).

### Auth probe

[`checkOpenCodeProviderStatus`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Layers/OpenCodeProvider.ts):

1. Enabled gate.
2. If **not** external: `opencode --version`; enforce ≥ `1.14.19`.
3. Inventory:
   - Local: CLI `opencode models --verbose` + `opencode agent list` (`loadInventoryFromCli`).
   - External: connect to server → SDK `provider.list` (+ agents).
4. Auth semantics: if `providerList.connected.length > 0` → `auth.status: "authenticated"` / ready; else warning + auth `unknown` (“no connected upstream providers”).
5. Unauthorized / bad password → explicit server auth error message.

So T3 “auth” for OpenCode means **at least one Models.dev / configured upstream provider has credentials**, not a single OpenCode account email.

### Env / path overrides

| Mechanism | Role |
| --- | --- |
| Settings **Binary path** | `opencode` |
| Settings **Server URL** / **Server password** | External or password-protected serve |
| Instance env | Provider API keys; OpenCode also reads `~/.local/share/opencode/auth.json` and project `.env` ([OpenCode CLI docs](https://opencode.ai/docs/cli/)) |
| Official `OPENCODE_SERVER_PASSWORD` / `OPENCODE_SERVER_USERNAME` | Protect `serve` / `web` |

### Official auth (headless-relevant)

From [OpenCode CLI](https://opencode.ai/docs/cli/) / [Providers](https://opencode.ai/docs/providers/):

- `opencode auth login` (or TUI `/connect`) stores keys in **`~/.local/share/opencode/auth.json`**.
- `opencode serve` for headless HTTP; password via `OPENCODE_SERVER_PASSWORD`.
- Upstream providers are plural (Anthropic, OpenAI, OpenCode Zen, etc.) — each needs its own credential.

### Add-on caveats

- Persist OpenCode data dir (`~/.local/share/opencode/`) under `/data` / Provider home.
- Auth is **multi-provider**: bake CLI + run `opencode auth login` (or drop `auth.json` / env keys) until T3 reports connected upstreams.
- If using T3-spawned `serve`, no need for a long-lived external OpenCode server; leave **Server URL** blank.
- OpenCode’s own skill paths (`.opencode/skills/`, `~/.config/opencode/skills/`) differ from this Add-on’s `/config/.agents/skills/` Cursor/Workspace layout — see [skill-discovery-paths.md](./skill-discovery-paths.md); not re-litigated here.

---

## Cursor baseline (comparison only)

Full detail: [t3-cursor-provider.md](./t3-cursor-provider.md). Short deltas vs the four above:

| Topic | Cursor | Codex / Claude / Grok / OpenCode |
| --- | --- | --- |
| Default enabled | **Off** | **On** |
| Default binary | `cursor-agent` (not `agent`) | `codex` / `claude` / `grok` / `opencode` |
| Transport | ACP `acp` | app-server / Agent SDK / ACP `agent stdio` / HTTP `serve` |
| Auth probe | `about` email | account/read / SDK init / (Grok: none) / connected providers |
| Headless auth knobs | `CURSOR_API_KEY`, file store, `agent login` | Per-CLI (above) |

---

## Implications checklist for the Home Assistant Add-on

For each of Codex / Claude / Grok / OpenCode (alongside existing Cursor):

1. **Install CLI in the image** (pin versions separately; OpenCode ≥ 1.14.19 for T3 0.0.33).
2. **PATH / Binary path** — prefer unambiguous names (`grok`, `cursor-agent`); do not let Grok’s `agent` symlink steal Cursor.
3. **Enablement** — these four default **on** in T3 settings once the server has empty/default provider settings; Cursor still needs an explicit enable.
4. **Persist homes** under `/data` (`CODEX_HOME`, `CLAUDE_CONFIG_DIR`, `~/.grok`, `~/.local/share/opencode`, Cursor `~/.cursor`).
5. **Authenticate in-container** with API key / device-code / seeded auth files; assume no interactive browser on HA OS.
6. **Prove** one successful `/config` session per provider (map destination — out of scope for this note).

---

## Version note

Add-on pins **`t3@0.0.33`**. All T3 source citations above are that tag. Newer `t3` releases may change probe messages, OpenCode minimum version, or Grok auth surfacing — re-check when bumping the pin.

---

## References

- T3 install / providers table: https://github.com/pingdotgg/t3code/blob/v0.0.33/docs/user/install.md
- T3 Codex multi-account: https://github.com/pingdotgg/t3code/blob/v0.0.33/docs/user/providers-codex.md
- T3 Claude multi-account / OpenRouter: https://github.com/pingdotgg/t3code/blob/v0.0.33/docs/user/providers-claude.md
- T3 provider internals: https://github.com/pingdotgg/t3code/blob/v0.0.33/docs/internals/providers.md
- Settings schema: https://github.com/pingdotgg/t3code/blob/v0.0.33/packages/contracts/src/settings.ts
- Codex / Claude / Grok / OpenCode provider + driver sources under `apps/server/src/provider/` at `v0.0.33`
- Cursor default binary change (Grok `agent` collision): https://github.com/pingdotgg/t3code/pull/4094 , https://github.com/pingdotgg/t3code/issues/3478
- Codex auth: https://developers.openai.com/codex/auth
- Claude Code auth: https://code.claude.com/docs/en/authentication
- Grok Build CLI / ACP / enterprise auth: https://docs.x.ai/build/overview , https://docs.x.ai/build/cli/headless-scripting , https://docs.x.ai/build/enterprise , https://x.ai/cli/install.sh
- OpenCode CLI / auth / serve: https://opencode.ai/docs/cli/ , https://opencode.ai/docs/providers/
