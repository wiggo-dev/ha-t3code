---
name: home-assistant-configuration
description: Write or change Home Assistant YAML — automations, scripts, scenes, templates, integrations, packages, helpers. Covers checking current docs before writing, the HA YAML style guide, reading YAML with yq, safe whole-file edits, validation, backups, and telling the operator what to reload vs restart. Load this before editing any file under the Workspace (/config).
---

# Home Assistant configuration work

**Operator loop:** ask → gather thin evidence → propose the smallest change → operator approves edits and applies reload/restart/UI. Never call services, reload, restart, or control devices yourself.

**Evidence shell:** `yq`, `grep`, `jq`, and read-only `curl` to Core/Supervisor REST (`SUPERVISOR_TOKEN`). That is the full set — do not probe PATH for other HA CLIs.

Show the change, wait for explicit approval, change nothing else.

## Thin evidence (ADR-0005 tiers)

For **configuration / improvement** (nothing broken), files + current docs are enough to draft. When a draft names entities, **recommend** (do not require) a quick existence/state check via Core REST (`SUPERVISOR_TOKEN` → `http://supervisor/core/api/states/<entity_id>`).

Use higher tiers only when diagnosis is needed (hand off to `home-assistant-troubleshooting`):

1. **File baseline** — YAML tree, `.HA_VERSION`, read-only `.storage/` registries
2. **Core REST** — entity existence/state (optional check when drafting)
3. **Supervisor REST** — usually not needed for pure config work

**Fallback:** operator paste or `/config/.t3code/exports/`. Short recipes: add-on DOCS — do not embed long `curl` blocks here. Thin REST is read-only evidence only.

## Before you write anything

Home Assistant ships a release every month. Verify syntax against the running version and current docs rather than training data.

1. Note the Home Assistant version (`.HA_VERSION`, or ask Settings → About).
2. Read current integration docs: https://www.home-assistant.io/integrations/<domain>/
3. Check breaking changes for that version when something failed after an update.
4. Read the existing file in full. Every write should replace the whole file content you intend to keep.

Frequently-changed pitfalls:

- Template sensors: prefer top-level `template:` over legacy `platform: template` under `sensor:`
- MQTT: prefer top-level `mqtt:` over legacy `platform: mqtt` under a domain
- Service targeting: use `target:`; do not put `entity_id` at action level or inside `data:`
- Prefer `states('sensor.x')` over `states.sensor.x.state`
- Many integrations are UI-only now — do not invent YAML for those

## Writing safely

There is no `write_config_safe` tool here. Mimic it manually:

1. Read the entire existing file
2. Draft the full new contents (existing + your change)
3. Show the complete draft and wait for approval
4. Write the complete file (never a partial fragment that drops sibling keys/list entries)
5. Suggest validation: Developer Tools → YAML → Check Configuration (operator runs it)
6. Suggest backup before large changes (Settings → System → Backups)

**Never write partial content** that omits what was already in the file.

## Reading YAML from the shell

Use **`yq`** (mikefarah, on PATH). It tolerates HA tags (`!include`, `!secret`, …). PyYAML often crashes on those tags.

```
yq '.homeassistant.latitude' configuration.yaml
yq 'keys' configuration.yaml
```

**Never round-trip through JSON** — `!include` / `!secret` are lost. Prefer the editor for real edits; `yq -i` is only for careful low-risk tweaks (custom tags stick to overwritten values; blank lines may be stripped).

## YAML style guide (mandatory)

Follow the official [Home Assistant YAML style guide](https://developers.home-assistant.io/docs/documenting/yaml-style-guide/).

- Indentation: 2 spaces
- Booleans: lowercase `true` / `false` only
- Strings: double quotes (exceptions: entity IDs, domain keys, trigger/action types, etc.)
- Sequences and mappings: block style
- Service targets: always `target:`
- Templates: double quotes outside, single inside; prefer `states()` / `state_attr()` / `is_state()`

## What lives where

Workspace root is `/config` (also the T3 project root):

- `configuration.yaml`, `automations.yaml`, `scripts.yaml`, `scenes.yaml`, …
- `secrets.yaml` — never display or copy secret values
- `packages/`, `blueprints/`, `themes/`, `www/`, `custom_components/`
- `.storage/`, `.cloud/`, `deps/`, `tts/`, `home-assistant_v2.db`, `home-assistant.log` — do not hand-edit; use HA UI the operator controls

## Creating an automation

Inventory first from the Workspace (and optionally Core REST), then edit:

1. List existing automations with `yq` / `grep` on `automations.yaml` and `packages/` (ids, aliases, entity_ids)
2. Optional live check: Core REST states for `automation.*` (short `curl` shapes in add-on DOCS)
3. Read the whole existing automations file or package
4. Draft complete YAML with comments for non-obvious bits
5. Show the full draft; wait for approval
6. Write the file
7. Suggest how the operator should test; name the reload step (they apply it)

## Applying the change

Tell the operator which step is needed; they apply it in the UI. Never perform reload/restart yourself.

| Change | What the operator applies |
| --- | --- |
| automations / scripts / scenes YAML | Reload that domain |
| Template entities, many helpers | Reload the domain |
| `configuration.yaml` integration blocks | Usually a **restart** |
| New code under `custom_components/` | **Restart** |
| `secrets.yaml` | Restart whatever reads them |
