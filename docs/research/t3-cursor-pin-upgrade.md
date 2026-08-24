# T3 and Cursor CLI pin / float and operator upgrade story

Research for [ha-t3code#15](https://github.com/wiggo-dev/ha-t3code/issues/15). Primary sources: this repo’s [`t3code/Dockerfile`](../../t3code/Dockerfile), [`t3code/run.sh`](../../t3code/run.sh), [`t3code/config.yaml`](../../t3code/config.yaml), [`t3code/README.md`](../../t3code/README.md), [ADR-0001](../adr/0001-debian-base-server-side-cursor.md), [ADR-0002](../adr/0002-cursor-credential-schema.md), [ADR-0003](../adr/0003-workspace-agent-skills.md); npm registry [`t3`](https://registry.npmjs.org/t3); [pingdotgg/t3code](https://github.com/pingdotgg/t3code) tag `v0.0.33` (`CursorProvider.ts`, `CursorDriver.ts`, `CursorAcpSupport.ts`); [Cursor CLI installation](https://cursor.com/docs/cli/installation), [configuration](https://cursor.com/docs/cli/reference/configuration), [changelog](https://cursor.com/docs/cli/changelog), [ACP](https://cursor.com/docs/cli/acp), live [install script](https://cursor.com/install) (fetched 2026-08-22), and `https://downloads.cursor.com/lab/<version>/…` packages. Related research: [t3-cursor-provider.md](./t3-cursor-provider.md), [cursor-cli-container-auth.md](./cursor-cli-container-auth.md), [skill-discovery-paths.md](./skill-discovery-paths.md).

**Scope:** facts only. Pin vs float policy is deferred to grilling after this note.

---

## Summary

| Component | Today in this Add-on image | Upstream release surface | Float / pin character |
| --- | --- | --- | --- |
| **`t3` (npm)** | **Pinned** at build: `ARG T3_VERSION=0.0.33` → `npm install -g "t3@${T3_VERSION}"` | npm dist-tags `latest` (= `0.0.33` as of 2026-08-22), `nightly` (e.g. `0.0.34-nightly.*`), `alpha`; GitHub releases mostly nightly prereleases | Rebuild required to change; not updated at container runtime |
| **Cursor CLI (`cursor-agent` / `agent`)** | **Not version-pinned in Dockerfile.** Build runs `curl https://cursor.com/install -fsS \| bash`, which currently hardcodes lab build `2026.08.11-e8db854` | Install script embeds a concrete `downloads.cursor.com/lab/<ver>/…` URL; docs say CLI **auto-updates by default**; manual `agent update`; config `channel`; flag `--disable-auto-update` | **Float at image-build time** (whatever the install script serves that day). **Also can float at runtime** unless auto-update is disabled — separate from Add-on image upgrades |
| **Add-on package** | `config.yaml` `version: "0.2.1"` (Supervisor-facing); independent of `T3_VERSION` | HA: Check for updates → Update/Rebuild → restart ([README](../../t3code/README.md)) | Operator upgrade unit is the Add-on version, not npm/Cursor alone |

Break-glass surfaces already documented in-repo: ACP auth probe vs API key ([t3code#7244](https://github.com/pingdotgg/t3code/issues/7244)), lab-channel + min CLI date for parameterized models (T3 `CursorProvider` on `v0.0.33`), Skills picker vs CLI discovery ([skill-discovery-paths.md](./skill-discovery-paths.md), [t3code#2736](https://github.com/pingdotgg/t3code/issues/2736) / [PR #5168](https://github.com/pingdotgg/t3code/pull/5168)), and ADR-0002’s note that T3 settings SQLite shape is version-fragile.

---

## Current image build (this repo)

Source: [`t3code/Dockerfile`](../../t3code/Dockerfile) on branch tip from `main` (verified 2026-08-22).

### What is pinned

| Pin | Value | Mechanism |
| --- | --- | --- |
| Base image | `ghcr.io/home-assistant/base-debian:trixie` | `ARG BUILD_FROM` (glibc; required for Cursor — [ADR-0001](../adr/0001-debian-base-server-side-cursor.md), [cursor-cli-container-auth.md](./cursor-cli-container-auth.md)) |
| Node | `22.23.2` | Direct download from `nodejs.org` |
| yq | `v4.44.3` | GitHub release binary |
| **`t3`** | **`0.0.33`** | `ARG T3_VERSION=0.0.33` + `npm install -g "t3@${T3_VERSION}"` |

No add-on `build.yaml` overrides `T3_VERSION`; changing `t3` means editing the Dockerfile (or adding a build-arg wiring later).

### What is not pinned (Cursor)

```dockerfile
curl https://cursor.com/install -fsS | bash
ln -sf /root/.local/bin/cursor-agent /usr/local/bin/cursor-agent
ln -sf /root/.local/bin/agent /usr/local/bin/agent
cursor-agent --version
```

- Official installer extracts under **`/root/.local/share/cursor-agent/versions/<version>/`** and symlinks `/root/.local/bin/{agent,cursor-agent}` ([install script](https://cursor.com/install); layout also in [cursor-cli-container-auth.md](./cursor-cli-container-auth.md)).
- Dockerfile republishes both names on `/usr/local/bin` and sets `ENV PATH="/root/.local/bin:${PATH}"`.
- **No Cursor version ARG**, no direct tarball URL, no checksum — each image build accepts whatever version string is currently hardcoded in the install script.

Bundled Skills are copied from `t3code/skills` → `/opt/ha-t3code/skills` and deployed at start by `deploy-skills.py` ([ADR-0003](../adr/0003-workspace-agent-skills.md)) — versioned with the Add-on image, not with npm/Cursor.

### Runtime (upgrade-relevant; not install pin)

[`t3code/run.sh`](../../t3code/run.sh):

| Setting | Value |
| --- | --- |
| Workspace / `HOME` | `/config` |
| T3 state | `T3CODE_HOME=/data/t3` |
| Provider home | `/data/home` via `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME` |
| Credential store | `AGENT_CLI_CREDENTIAL_STORE=file` |
| `.cursor` | Symlink `/config/.cursor` → `/data/home/.cursor` when missing |

Also:

- Logs Add-on version (`bashio::addon.version`), Cursor auth readiness, and whether `cursor-agent` is on `PATH`.
- Does **not** log `t3 --version` / `cursor-agent --version` as a release fingerprint.
- Does **not** pass `--disable-auto-update`.
- Starts `t3 start … /config`.

Upstream T3 Cursor ACP spawn (`v0.0.33`): `<binaryPath> acp` with optional `-e <endpoint>` — **no** auto-update flag on the child ([`CursorAcpSupport.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/acp/CursorAcpSupport.ts)). Maintenance capability shells `cursor-agent update` ([`CursorDriver.ts`](https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Drivers/CursorDriver.ts)).

---

## Upstream: `t3` release channels

| Fact | Source |
| --- | --- |
| npm package `t3`, bin `t3` → `./dist/bin.mjs`, git repo `pingdotgg/t3code` (`apps/server`) | [registry.npmjs.org/t3](https://registry.npmjs.org/t3) |
| Engines: `node: ^22.16 \|\| ^23.11 \|\| >=24.10` | `t3@0.0.33` metadata |
| dist-tag **`latest` → `0.0.33`** (published 2026-08-10); **equals** current Dockerfile pin | registry fetch 2026-08-22 |
| dist-tag **`nightly`** → high-churn `0.0.34-nightly.*` | registry + [GitHub releases](https://github.com/pingdotgg/t3code/releases) (prerelease) |
| dist-tag **`alpha` → `0.0.2`** | registry |
| GitHub release feed is dominated by nightlies after `0.0.33` | GitHub Releases API 2026-08-22 |

**Implication:** bumping `T3_VERSION` is a deliberate image change. `npm install -g t3@latest` at build would still freeze whatever `latest` was that day, but would advance silently when the tag moves. `t3@nightly` tracks prerelease churn.

T3 does **not** ship the Cursor CLI; it expects an external binary ([t3-cursor-provider.md](./t3-cursor-provider.md)).

---

## Upstream: Cursor CLI install, channels, updates

### Install script (build-time float)

Fetched [https://cursor.com/install](https://cursor.com/install) on 2026-08-22:

1. Detects `linux`/`darwin` × `x64`/`arm64`.
2. Downloads **`https://downloads.cursor.com/lab/2026.08.11-e8db854/${OS}/${ARCH}/agent-cli-package.tar.gz`** (version **hardcoded in the script**; no argv/env pin hook in the script body).
3. Extracts to `~/.local/share/cursor-agent/versions/2026.08.11-e8db854/`.
4. Symlinks `~/.local/bin/agent` and `~/.local/bin/cursor-agent`.

That tarball URL returned **HTTP 200**. Invented version ids returned **403** (must know a real id to pin by URL; no public index observed).

**Pin recipe available but unused today:** Dockerfile `ARG` + direct `curl` of the lab tarball (same URL shape as the installer), extract under a fixed path, symlink — same pattern already used for Node and yq.

The packaged `cursor-agent` entrypoint is a bash wrapper: resolves `SCRIPT_DIR` via `realpath`, runs bundled `node` + `index.js` from that version directory; compile cache uses `XDG_CACHE_HOME` / `~/.cache` (wrapper in `2026.08.11-e8db854` package).

### Documented update behavior

| Behavior | Source |
| --- | --- |
| “Cursor CLI will try to **auto-update by default**” | [Installation → Updates](https://cursor.com/docs/cli/installation) |
| Manual update: `agent update` | same |
| `--disable-auto-update` disables background updates | [CLI changelog](https://cursor.com/docs/cli/changelog) |
| Config field `channel` — release channel for CLI updates | [CLI configuration](https://cursor.com/docs/cli/reference/configuration) (docs path `~/.cursor/cli-config.json`; also documents `XDG_CONFIG_HOME` variants for some settings) |
| Reliable channel switching called out in changelog | [CLI changelog](https://cursor.com/docs/cli/changelog) |

### T3 gates that depend on Cursor version/channel

From `CursorProvider` on tag **`v0.0.33`** (source fetched from GitHub):

- Parameterized model picker requires CLI version date **≥ 2026-04-08** and channel **`lab`**.
- Operator guidance string: run `agent set-channel lab && agent update` and use CLI **2026.04.08+**.
- Channel read from **`~/.cursor/cli-config.json`** (`channel` field) via `os.homedir()` — with this Add-on’s `HOME=/config` and `.cursor` symlink, that is effectively Provider-home-backed `/data/home/.cursor/cli-config.json`.
- Health probe: `agent about` (JSON preferred); email absence ⇒ treated logged out even if `CURSOR_API_KEY` works ([t3code#7244](https://github.com/pingdotgg/t3code/issues/7244); Add-on workaround: login file under `/data/home/.config/cursor/auth.json` — [ADR-0002](../adr/0002-cursor-credential-schema.md), README).

ACP surface includes `authenticate` / `cursor_login`, model listing, session flow ([ACP docs](https://cursor.com/docs/cli/acp); [t3-cursor-provider.md](./t3-cursor-provider.md)). Skew between T3’s ACP client and Cursor CLI can break discovery or sessions.

---

## Skills discovery vs binary versions

| Layer | Behavior | Pin relevance |
| --- | --- | --- |
| **Cursor CLI** | Discovers Agent Skills from project/user trees per [Cursor skills docs](https://cursor.com/docs/skills) | CLI upgrades can change discovery; Workspace skills remain under `/config` |
| **T3 Cursor `$` picker** | On `0.0.33` / current `main`: inventory effectively empty; [t3code#2736](https://github.com/pingdotgg/t3code/issues/2736) open; [PR #5168](https://github.com/pingdotgg/t3code/pull/5168) open/unmerged | Fix likely requires a **`t3` bump**, not Cursor pin alone |
| **This Add-on** | Digest-syncs bundled HA Skills into Workspace `.agents/skills` ([ADR-0003](../adr/0003-workspace-agent-skills.md)) | Tied to Add-on image + `/data` digest state; operator edits preserved |

---

## Operator upgrade / break-glass story (factual)

### How operators get new bits today

1. Maintainers change Dockerfile pins / Cursor install line and bump [`config.yaml`](../../t3code/config.yaml) `version` (currently `0.2.1`).
2. Operator: Add-on store → **Check for updates** → **T3 Code** → confirm version → **Update** or **Rebuild** → restart ([README](../../t3code/README.md)).
3. Logs show Add-on version and Cursor auth/PATH checks — **not** a recorded `t3@x` + `cursor-agent@y` matrix for rollback.

Persistent across image replace:

| Path | Contents |
| --- | --- |
| `/data/t3` | T3 SQLite / settings / pairing (version-fragile per ADR-0002) |
| `/data/home` | Cursor auth (`…/config/cursor/auth.json`), XDG cache/data, `.cursor` channel/prefs |
| `/config` | Workspace, Skills tree, optional `.cursor` symlink |

Rebuild replaces the image layer (including `/root/.local/share/cursor-agent/…` from build). Runtime updates that only touched the ephemeral container layer are lost on recreate; state under `/data` and `/config` remains.

### Failure modes worth pinning / testing against

| Failure mode | What breaks | What you’d freeze or test | Evidence |
| --- | --- | --- | --- |
| **ACP protocol / spawn skew** | Sessions, model discovery | Co-pin known-good **`t3` + `cursor-agent`**; disable CLI auto-update | `cursor-agent acp` spawn; ACP docs |
| **Auth probe / `cursor_login`** | Provider “logged out”; browser login required | Track #7244 fixes in `t3` bumps; keep login-file workaround | t3code#7244, README, ADR-0002 |
| **Channel / min version gate** | Parameterized model picker off | Keep `lab` + CLI ≥ 2026.04.08; watch channel on update | `CursorProvider` v0.0.33 |
| **Skills picker empty** | `$` empty while CLI still loads skills | **`t3` feature gap** until #5168 | skill-discovery research |
| **Cursor auto-update mid-flight** | Running CLI drifts without Add-on release | `--disable-auto-update`; avoid production reliance on T3 `update` maintenance | Installation docs + changelog |
| **Build non-reproducibility** | Same git SHA, different Cursor on Rebuild when install script moves | Pin tarball URL (+ checksum) in Dockerfile | Install script hardcodes version; Dockerfile floats |
| **T3 settings migrations** | Pairing/settings after `t3` bump | Slow bumps; backup `/data/t3` | ADR-0002 |
| **glibc / base drift** | Cursor won’t run | Stay on Debian/glibc base | ADR-0001 |

### Break-glass levers that exist today

1. **Add-on Update/Rebuild** to a previous Add-on version — restores that image’s baked `t3` + Cursor.
2. **Dockerfile change:** bump `T3_VERSION` and/or replace Cursor install with a **known lab tarball URL**; ship new Add-on version.
3. **Inside a running container:** `cursor-agent update` / `agent set-channel lab` (and T3 maintenance that runs `update`) — moves Cursor **without** an Add-on release (anti-pin).
4. **`--disable-auto-update`** on Cursor CLI — documented; **not** wired in `run.sh` or T3 ACP spawn today.
5. **Auth:** re-set `cursor_api_key` or re-login into `/data/home`; image rollback does not wipe Provider home by itself.
6. **Skills:** digest sync preserves operator edits; delete edited bundled skill to restore shipped copy (ADR-0003).

---

## Fact table: pin vs float options (no decision)

| Option | `t3` | Cursor CLI | Reproducible image? | Operator gets fixes via |
| --- | --- | --- | --- | --- |
| **A. Status quo** | Pin `0.0.33` | Float at build via install script; auto-update on by default at runtime | `t3` yes; Cursor weak | Add-on Rebuild (both); silent Cursor self-update (CLI only) |
| **B. Pin both at build** | Keep/bump `T3_VERSION` | Dockerfile ARG + lab tarball URL (+ checksum) | Yes | Add-on release only (plus disable auto-update) |
| **C. Float `t3@latest` at build** | Unpinned tag | (any Cursor policy) | Weak for `t3` | Every Rebuild may jump `latest` |
| **D. Runtime Cursor float** | Pin | Allow `agent update` / auto-update in live container | Image SHA ≠ running CLI | Fast CLI fixes; highest ACP skew risk |
| **E. Nightly `t3`** | `nightly` tag | (any) | Poor | Tracks prerelease churn |

---

## Gaps / unknowns

- Exact filesystem target of **runtime** auto-update when `HOME=/config` but the binary resolves under `/root/.local/share/cursor-agent/versions/…` (whether updates rewrite `/root` layer vs `XDG_DATA_HOME`) — public install docs do not specify; wrapper always runs Node from the versioned install dir.
- Retention lifetime of old `downloads.cursor.com/lab/<version>/…` artifacts (how durable a URL pin is).
- Whether T3 headless/Add-on UX enables provider update checks by default (`enableProviderUpdateChecks` exists in driver code — default **unknown** without a settings dump).
- Full Home Assistant Supervisor semantics for local vs store Rebuild beyond this repo’s README (developers.home-assistant.io timed out during this pass).

---

## References

- Add-on image/runtime: `t3code/Dockerfile`, `t3code/run.sh`, `t3code/config.yaml`, `t3code/README.md`
- ADR-0001 Debian + Server-side Cursor; ADR-0002 credentials; ADR-0003 Workspace skills
- Prior research: [t3-cursor-provider.md](./t3-cursor-provider.md), [cursor-cli-container-auth.md](./cursor-cli-container-auth.md), [skill-discovery-paths.md](./skill-discovery-paths.md)
- npm `t3`: https://registry.npmjs.org/t3
- t3code Cursor provider (`v0.0.33`): https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Layers/CursorProvider.ts
- t3code Cursor driver update: https://github.com/pingdotgg/t3code/blob/v0.0.33/apps/server/src/provider/Drivers/CursorDriver.ts
- Cursor install script: https://cursor.com/install
- Cursor CLI installation / updates: https://cursor.com/docs/cli/installation
- Cursor CLI configuration (`channel`): https://cursor.com/docs/cli/reference/configuration
- Cursor CLI changelog (`--disable-auto-update`): https://cursor.com/docs/cli/changelog
- Cursor ACP: https://cursor.com/docs/cli/acp
- Upstream auth bug: https://github.com/pingdotgg/t3code/issues/7244
- Upstream skills discovery: https://github.com/pingdotgg/t3code/issues/2736 , https://github.com/pingdotgg/t3code/pull/5168
