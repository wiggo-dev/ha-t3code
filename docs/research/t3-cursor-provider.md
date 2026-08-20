# T3 Code Cursor provider requirements (remote/headless server)

Research for [ha-t3code#6](https://github.com/wiggo-dev/ha-t3code/issues/6). Primary sources: [pingdotgg/t3code](https://github.com/pingdotgg/t3code) (v0.0.33, the version pinned in this add-on), [Cursor CLI docs](https://cursor.com/docs/cli).

## Summary

T3 Code does **not** ship the Cursor CLI. On a headless server (`t3 serve`), the server spawns an external **`cursor-agent`** binary (default since [PR #4094](https://github.com/pingdotgg/t3code/pull/4094)), probes it on startup and on a ~5-minute refresh cycle, and drives it over ACP (`cursor-agent acp`). Subscription/auth is entirely delegated to the Cursor CLI on the **server machine** — via `agent login`, `CURSOR_API_KEY`, or per-instance env vars in T3 settings. For an add-on container, install Cursor CLI, put it on `PATH` (or set **Binary path**), authenticate inside the container, enable Cursor in T3 settings, and persist `HOME`/`~/.cursor` (and optionally `T3CODE_HOME` state).

---

## Binary name and PATH

| Item | Value | Source |
| --- | --- | --- |
| Default binary | `cursor-agent` | [`packages/contracts/src/settings.ts`](https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/settings.ts) (`CursorSettings.binaryPath`), [`CursorAcpSupport.ts`](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/acp/CursorAcpSupport.ts) |
| Previous default | `agent` (changed to avoid Grok CLI collision) | [PR #4094](https://github.com/pingdotgg/t3code/pull/4094), [issue #3478](https://github.com/pingdotgg/t3code/issues/3478) |
| Override | **Settings → Cursor → Binary path** (command name or absolute path) | [`docs/user/install.md`](https://github.com/pingdotgg/t3code/blob/main/docs/user/install.md) |
| Resolution | Non-Windows: command passed directly to spawn (must be on `PATH` or absolute). Windows resolves `.cmd`/`.bat`. | [`packages/shared/src/shell.ts`](https://github.com/pingdotgg/t3code/blob/main/packages/shared/src/shell.ts) |

**Cursor CLI install layout:** the official installer places the executable under `~/.local/share/cursor-agent/versions/<version>/cursor-agent` and symlinks **both** `~/.local/bin/agent` and `~/.local/bin/cursor-agent` ([install script](https://cursor.com/install), [installation docs](https://cursor.com/docs/cli/installation)). T3’s default `cursor-agent` matches the legacy symlink name and avoids picking up Grok’s `agent` when both are installed.

**User-facing docs note:** T3’s install guide lists default binary `cursor-agent` but login command `agent login` ([`docs/user/install.md`](https://github.com/pingdotgg/t3code/blob/main/docs/user/install.md)). Either symlink works for spawning; subcommands are the same binary.

### Spawn command shape

When T3 starts a Cursor session or runs discovery, it spawns:

```text
<binaryPath> [-e <apiEndpoint>] acp
```

- Default: `cursor-agent acp`
- Optional API override from **Settings → Cursor → API endpoint** → `-e <url>` ([`CursorAcpSupport.buildCursorAcpSpawnInput`](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/acp/CursorAcpSupport.ts))

Maintenance/update uses the same binary: `cursor-agent update` ([`CursorDriver.ts`](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/Drivers/CursorDriver.ts)).

---

## Server-side provider discovery

Discovery runs on the **T3 server process** (the add-on container when using `t3 serve`), not on the desktop/mobile client.

### Flow (`checkCursorProviderStatus`)

Source: [`apps/server/src/provider/Layers/CursorProvider.ts`](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/Layers/CursorProvider.ts)

1. **Enabled gate** — Cursor is **off by default** in T3 settings (`CursorSettings.enabled` defaults to `false`). If disabled, probe returns “Cursor is disabled in T3 Code settings.”
2. **Health probe** — Runs `<binaryPath> about` (prefers `about --format json`, falls back to plain `about`). Timeout: 8s.
   - Parses CLI version, user email, and optional `subscriptionTier` from JSON or key-value output.
   - Auth: email present and not “Not logged in” → authenticated; otherwise prompts **`agent login`**.
3. **Channel/version gate** — Reads `~/.cursor/cli-config.json` on the **server** for release channel. Parameterized model picker requires **lab channel** and CLI version **≥ 2026.04.08** (date parsed from version string).
4. **ACP model discovery** (only if authenticated) — Spawns `<binaryPath> acp`, calls extension method `cursor/list_available_models`. Timeout: 15s. Failures surface as warnings in provider status / server logs (`Cursor ACP model discovery failed`).

### Refresh cadence

Managed providers use [`makeManagedServerProvider`](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/makeManagedServerProvider.ts):

- Initial check on server start (forked).
- Periodic refresh: default **`DEFAULT_PROVIDER_HEALTH_REFRESH_INTERVAL` = 5 minutes** ([`packages/contracts/src/settings.ts`](https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/settings.ts)); profile-dependent (1–15 min).
- Re-check when Cursor settings change.
- Background policy may skip refresh when no client demand (headless servers may still run checks depending on scope).

Restart the server after installing Cursor CLI or changing `PATH` to pick up a new binary immediately ([`.cursor/rules/cursor-cloud.mdc`](https://github.com/pingdotgg/t3code/blob/main/.cursor/rules/cursor-cloud.mdc)).

---

## Environment variables

### T3 Code server (relevant to headless/add-on)

| Variable | Role |
| --- | --- |
| `T3CODE_HOME` | T3 state directory (pairing, SQLite, settings). Equivalent to `t3 serve --base-dir`. This add-on sets `T3CODE_HOME=/data/t3`. ([`apps/server/src/cli/config.ts`](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/cli/config.ts)) |
| `PATH` | Must include the directory containing `cursor-agent` if using default binary name without absolute path. |

T3 does **not** define Cursor-specific server env vars. The server forwards **`process.env`** (merged with per-instance overrides) to provider child processes ([`ProviderInstanceEnvironment.ts`](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/ProviderInstanceEnvironment.ts), [`CursorDriver.create`](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/Drivers/CursorDriver.ts)).

Per-instance env vars can be configured in **Settings → provider instance → Environment** (`ProviderInstanceConfig.environment` in [`providerInstance.ts`](https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/providerInstance.ts)).

### Cursor CLI (subscription / auth)

| Variable | Role | Source |
| --- | --- | --- |
| `CURSOR_API_KEY` | API key auth (CI/headless); alternative to `agent login` | [Cursor authentication](https://cursor.com/docs/cli/reference/authentication), [ACP docs](https://cursor.com/docs/cli/acp) |
| `CURSOR_AUTH_TOKEN` | Documented as alternate auth token flag/env on ACP startup | [ACP docs](https://cursor.com/docs/cli/acp) |
| `AGENT_CLI_CREDENTIAL_STORE=file` | Force file-based credential store (`~/.cursor/auth.json`) instead of OS keychain — **important in containers** without keychain | [Cursor forum / headless setups](https://forum.cursor.com/t/errsecitemnotfound-couldnt-find-your-saved-login-in-the-macos-keychain/167325) |
| `NO_OPEN_BROWSER=1` | Print login URL instead of opening browser during `agent login` | [Cursor authentication](https://cursor.com/docs/cli/reference/authentication) |
| `HOME` | Determines `~/.cursor/cli-config.json`, `~/.cursor/auth.json`, MCP config | [`CursorProvider.readCursorCliConfigChannel`](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/Layers/CursorProvider.ts) |

T3 settings also expose **API endpoint** (`CursorSettings.apiEndpoint`) as `-e` on the CLI, not as a separate env var.

### Probe script only (not used by server at runtime)

`apps/server/scripts/cursor-acp-model-mismatch-probe.ts` accepts `CURSOR_AGENT_BIN`, `CURSOR_REASONING`, `CURSOR_CONTEXT`, `CURSOR_FAST` for manual debugging.

---

## Subscription wiring

T3 uses a **bring-your-own-subscription** model: it does not bill or proxy Cursor; it controls whatever the Cursor CLI is authenticated as on the server.

1. **Login (interactive on server)** — Run `agent login` on the machine running `t3 serve` ([`docs/user/install.md`](https://github.com/pingdotgg/t3code/blob/main/docs/user/install.md)). Not on the pairing client.
2. **API key (headless/container-friendly)** — Set `CURSOR_API_KEY` in the container environment (or provider instance env in T3 settings). Cursor service accounts use the same variable ([service accounts docs](https://cursor.com/docs/account/enterprise/service-accounts)).
3. **ACP authenticate** — At session start T3 sends ACP `authenticate` with `methodId: "cursor_login"` ([`CursorAcpSupport.ts`](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/acp/CursorAcpSupport.ts)). Pre-authenticated CLI (login or API key) satisfies this.
4. **Status surfacing** — `cursor-agent about` JSON may include `subscriptionTier`; T3 maps it to provider auth metadata (e.g. “Cursor Pro Subscription”) ([`parseCursorAboutOutput`](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/Layers/CursorProvider.ts)).

Auth is required **before starting a Cursor thread**, not before starting T3 Code ([`docs/user/install.md`](https://github.com/pingdotgg/t3code/blob/main/docs/user/install.md)).

---

## Cursor provider settings schema

From [`CursorSettings`](https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/settings.ts):

| Field | Default | Notes |
| --- | --- | --- |
| `enabled` | `false` | Must opt in via Settings |
| `binaryPath` | `cursor-agent` | Empty string decodes to default |
| `apiEndpoint` | `""` | Optional `-e` override |
| `customModels` | `[]` | Fallback when ACP discovery fails |

Legacy settings live under `providers.cursor`; newer multi-instance map uses `providerInstances` with driver kind `cursor` ([`providerInstance.ts`](https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/providerInstance.ts)).

---

## Implications for the Home Assistant add-on container

Current add-on ([`t3code/run.sh`](../../t3code/run.sh), [`t3code/Dockerfile`](../../t3code/Dockerfile)):

- Runs `t3 serve` with `T3CODE_HOME=/data/t3` — correct for T3 state.
- Does **not** install Cursor CLI or configure Cursor auth (Phase 1 scope).
- Uses Node 22 from Alpine — satisfies T3’s `^22.16 || ^23.11 || >=24.10` requirement.

To add Cursor in a later phase:

1. **Install Cursor CLI in the image** — e.g. run `curl https://cursor.com/install -fsS | bash` (or copy binary) and ensure `~/.local/bin` is on `PATH` for the user the server runs as.
2. **Set `HOME`** to a persistent volume path (e.g. under `/data/cursor`) so `~/.cursor/auth.json` and `cli-config.json` survive restarts.
3. **Authenticate inside the container** — Prefer `CURSOR_API_KEY` via add-on options/secrets, or `AGENT_CLI_CREDENTIAL_STORE=file` + one-time `agent login` with `NO_OPEN_BROWSER=1` and persist `/data/cursor/.cursor/`.
4. **Enable Cursor in T3** — Toggle provider on in Settings (stored in T3 SQLite under `T3CODE_HOME`); default is disabled.
5. **Lab channel** — For full model picker, configure Cursor CLI to lab channel (`agent set-channel lab && agent update` per T3 error messages).
6. **Binary path** — If only `agent` is on PATH (no `cursor-agent` symlink), set explicit binary path in Settings or install script that creates both symlinks.
7. **No desktop keychain** — Containers lack macOS Keychain; use file store or API key.

---

## Version note (this repo)

Add-on pins `t3@0.0.33` ([`t3code/Dockerfile`](../../t3code/Dockerfile)), released 2026-08-10. The `cursor-agent` default landed in [PR #4094](https://github.com/pingdotgg/t3code/pull/4094) (merged 2026-07-17), so 0.0.33 includes it. Upgrades to newer `t3` releases should be checked against Cursor provider changelog.

---

## References

- T3 user install / providers: https://github.com/pingdotgg/t3code/blob/main/docs/user/install.md
- T3 remote/headless: https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md
- T3 provider internals: https://github.com/pingdotgg/t3code/blob/main/docs/internals/providers.md
- T3 Cursor driver: https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/Drivers/CursorDriver.ts
- T3 Cursor provider probe/discovery: https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/Layers/CursorProvider.ts
- T3 cursor-agent default change: https://github.com/pingdotgg/t3code/pull/4094
- Cursor CLI installation: https://cursor.com/docs/cli/installation
- Cursor CLI authentication: https://cursor.com/docs/cli/reference/authentication
- Cursor CLI ACP: https://cursor.com/docs/cli/acp
