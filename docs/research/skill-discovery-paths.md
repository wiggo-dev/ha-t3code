# Skill discovery paths: Cursor, T3 Code, OpenCode HA

Research notes on how Agent Skills (`SKILL.md`) are found on disk. Do not invent beyond cited sources; gaps marked **unknown**.

## Cursor (CLI / Agent)

**Primary source:** [cursor.com/docs/skills](https://cursor.com/docs/skills) (also [help/customization/skills](https://cursor.com/help/customization/skills)).

### Project / workspace roots

| Path | Scope |
|------|--------|
| `.agents/skills/` | Project-level |
| `.cursor/skills/` | Project-level |

Also (compatibility): `.claude/skills/`, `.codex/skills/`.

### Outside the workspace (home / global)

| Path | Scope |
|------|--------|
| `~/.agents/skills/` | User-level (global) |
| `~/.cursor/skills/` | User-level (global) |

Also (compatibility): `~/.claude/skills/`, `~/.codex/skills/`.

### Layout / discovery behavior

- Each skill is a folder containing `SKILL.md`.
- Cursor walks skill roots **recursively** (category subdirs OK; identity = folder that contains `SKILL.md`).
- Nested project dirs work: e.g. `apps/web/.cursor/skills/` is discovered and scoped to files under that directory.
- Required frontmatter: `name`, `description`. Optional Cursor-specific: `paths`, `disable-model-invocation`, `icon`, `color`, `metadata`. `name` must match parent folder name.

**`.opencode/skills/`:** not listed in Cursor docs → **unknown** whether Cursor loads it.

---

## T3 Code

T3 does **not** document a single cross-provider skill-root table. Discovery is **per provider**. Sources below are from `pingdotgg/t3code` docs/code/issues as of this research.

### Claude provider (documented + implemented on `main`)

**Sources:** [docs/user/providers-claude.md](https://github.com/pingdotgg/t3code/blob/main/docs/user/providers-claude.md); `apps/server/src/provider/Drivers/ClaudeSkills.ts` on `main`.

Scan order (later wins on name collision):

1. `<Claude config dir>/skills` (user; `CLAUDE_CONFIG_DIR` / instance `homePath`, else `~/.claude`)
2. `<workspace>/.agents/skills` (project)
3. `<workspace>/.claude/skills` (project)

Looks for `<dir>/<skill-name>/SKILL.md`, parses YAML `name` / `description`.

**Not documented for Claude scanner:** `.cursor/skills`, `.opencode/skills`, `~/.agents/skills` as a separate user root (user root is Claude config `skills/` only).

### Cursor provider

**On `main`:** no `CursorSkills.ts`; `providers-cursor.md` does not exist. This repo’s [docs/research/t3-cursor-provider.md](./t3-cursor-provider.md) covers Cursor spawn/auth/ACP models, **not** skill filesystem roots.

**Issue [#2736](https://github.com/pingdotgg/t3code/issues/2736)** (open): T3 Cursor provider cache often reports `skills: []` even when skills exist under `~/.cursor/skills/` and project `.cursor/skills/`. Commenters report Cursor ACP already surfaces skills (e.g. from `~/.agents/skills`) but T3 does not wire them into the `$` picker.

**PR [#5168](https://github.com/pingdotgg/t3code/pull/5168)** (`feat(cursor): cursor skills discovery`, **open, not merged**): proposes scanning `.cursor/skills` and `.agents/skills` at user and project scope; precedence claimed: directory name over frontmatter `name`, `.cursor` beats `.agents`, project beats user. Until merged, treat T3-owned Cursor skill inventory as **unknown / effectively empty for picker**.

**Runtime vs picker:** when T3 spawns `cursor-agent` with the project cwd, the **Cursor CLI itself** still discovers skills per Cursor docs above; that is separate from whether T3’s `$` picker lists them.

### Codex / OpenCode / Grok (T3)

- Codex: discovery delegated to `codex app-server` `skills/list` (includes `.agents/skills` per issues); T3 historically had wrong probe cwd ([#3040](https://github.com/pingdotgg/t3code/issues/3040)). Exact Codex path list in T3 user docs: **unknown** (no skill section in `providers-codex.md`).
- OpenCode/Grok in T3: historically no skills plumbing / empty pickers ([#2736](https://github.com/pingdotgg/t3code/issues/2736), [#5492](https://github.com/pingdotgg/t3code/issues/5492)). Current merged state for OpenCode inventory: **unknown** without re-checking each provider’s driver.

### This repo (`wiggo-dev/ha-t3code`)

- [CONTEXT.md](../../CONTEXT.md): defines Skill / Home Assistant Skills (five names from OpenCode HA); no discovery-path table.
- Skills live under `.agents/skills/` in the repo (engineering toolkit); no research note previously documenting Cursor/T3 scan roots.
- Research docs mention “symlink” only for `cursor-agent` binary names, not for skills.

---

## OpenCode (upstream) and OpenCode HA add-on

### Upstream OpenCode discovery

**Source:** [opencode.ai/docs/skills](https://opencode.ai/docs/skills/).

| Scope | Path |
|-------|------|
| Project | `.opencode/skills/<name>/SKILL.md` |
| Global | `~/.config/opencode/skills/<name>/SKILL.md` |
| Project compat | `.claude/skills/`, `.agents/skills/` |
| Global compat | `~/.claude/skills/`, `~/.agents/skills/` |

Project-local: walks from cwd up to git worktree. Frontmatter: required `name`, `description`; optional `license`, `compatibility`, `metadata`. Unknown fields ignored. `name` must match directory; description length 1–1024.

### OpenCode HA add-on — five bundled skills

**Sources:** [ha_opencode/DOCS.md](https://raw.githubusercontent.com/magnusoverli/opencode/main/ha_opencode/DOCS.md); tree under `ha_opencode/rootfs/opt/ha-mcp-server/skills/`; [deploy-opencode-assets.mjs](https://raw.githubusercontent.com/magnusoverli/opencode/main/ha_opencode/rootfs/usr/local/bin/deploy-opencode-assets.mjs); [skills-and-agents.test.js](https://raw.githubusercontent.com/magnusoverli/opencode/main/ha_opencode/test/skills-and-agents.test.js).

| Skill directory / `name` |
|--------------------------|
| `home-assistant-configuration` |
| `home-assistant-troubleshooting` |
| `home-assistant-dashboard-ui` |
| `home-assistant-zigbee-esphome` |
| `home-assistant-development` |

**Ship path (image):** `/opt/ha-mcp-server/skills/<name>/SKILL.md` (from rootfs).

**Deploy path (runtime, global OpenCode config):** copied to `/data/.config/opencode/skills/` on each start (`OPENCODE_ASSETS_TARGET` default). Deploy uses `fs.cp` (file copy), with digest bookkeeping: edited user copies are preserved and updates skipped.

**User / project skills (workspace):** `/config/.opencode/skills/<skill-name>/SKILL.md` (config mounted as `/homeassistant`, OpenCode cwd). Docs state: *“No additional volume mapping or symlink is required.”*

Bundled skills are separate from `/config/.opencode/skills/`; custom skills do not modify bundled files.

Example frontmatter (configuration skill): `name`, `description`, `metadata.owner: ha-opencode-addon`.

---

## Copy vs symlink

| Claim | Finding |
|-------|---------|
| OpenCode HA user skills need symlink into workspace | **Contradicted** by DOCS.md: place under `/config/.opencode/skills/`; no symlink required. |
| OpenCode HA bundled skills | **Copied** (not symlinked) from image → `/data/.config/opencode/skills/` by `deploy-opencode-assets.mjs`. |
| Cursor/T3: copy vs symlink skills into workspace | **Not found** in Cursor docs or this repo. Issue #2736 mentions skill **symlinks** as a user install method (`~/.cursor/skills/`), not as a documented requirement. |
| T3 Claude: symlink `.agents` into `.claude` | Mentioned as a **workaround** in secondary write-ups of GitHub issues; not in official `providers-claude.md`. |

---

## Adaptation notes (Cursor / T3 vs OpenCode)

| Topic | OpenCode / HA | Cursor | T3 (Claude on `main`) |
|-------|---------------|--------|------------------------|
| Preferred project path | `.opencode/skills/` (HA docs); also `.agents/skills/` | `.agents/skills/` or `.cursor/skills/` | `.agents/skills/` or `.claude/skills/` |
| Global / outside workspace | `~/.config/opencode/skills/`; HA bundled → `/data/.config/opencode/skills/` | `~/.agents/skills/`, `~/.cursor/skills/` | Claude: `<config>/skills` (not generic `~/.agents` in T3 scanner) |
| Frontmatter required | `name`, `description` | `name`, `description` (`name` = folder) | Uses `name`/`description`; fallback to dir name if frontmatter missing |
| Extra fields | `license`, `compatibility`, `metadata` | `paths`, `disable-model-invocation`, `icon`, `color`, `metadata` | **unknown** beyond name/description for inventory |
| OpenCode-only fields on Cursor | Ignored per OpenCode (“unknown ignored”); Cursor docs don’t list `license`/`compatibility` — likely ignored if Cursor follows Agent Skills pattern, but **unverified** | | |
| Naming | OpenCode regex `^[a-z0-9]+(-[a-z0-9]+)*$`, ≤64 chars, match dir | lowercase, numbers, hyphens; must match folder | Claude scanner: frontmatter name or directory name |
| HA skill names | Already hyphenated `home-assistant-*` — compatible with Cursor/OpenCode name rules | Same | Same |

**Practical interoperability:** putting skills under **workspace `.agents/skills/<name>/SKILL.md`** with standard `name` + `description` frontmatter is the path documented for Cursor, OpenCode (compat), and T3 Claude. HA’s documented **user** path is `.opencode/skills/` under `/config` — Cursor does **not** document that path. For Cursor/T3+Cursor, use `.agents/skills/` or `.cursor/skills/` under the workspace (or home equivalents), or rely on Cursor CLI discovery if the picker is empty.

---

## Sources checklist

1. This repo: CONTEXT.md; docs/research/* (no prior skill-path note); `.agents/skills/` present.
2. Cursor: https://cursor.com/docs/skills
3. T3: providers-claude.md; ClaudeSkills.ts; issues #2736, #5487, #5492; PR #5168 (unmerged).
4. OpenCode: https://opencode.ai/docs/skills/
5. OpenCode HA: DOCS.md; rootfs skills; deploy-opencode-assets.mjs; skills-and-agents.test.js
