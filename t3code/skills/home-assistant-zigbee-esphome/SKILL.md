---
name: home-assistant-zigbee-esphome
description: Work with Zigbee and ESPHome devices in a file-first Workspace — inspect references across YAML, plan renames carefully, reason about ZHA/Z2M/ESPHome config, and guide firmware updates the operator runs in the UI. Load for Zigbee, ZHA, Z2M, ESPHome, or device-firmware requests.
---

# Zigbee and ESPHome devices

**Operator loop:** ask → gather thin evidence → propose the smallest change → operator approves edits and applies reload/restart/UI. Never call services, reload, restart, or control devices yourself — including firmware flash and mesh repair.

This Add-on does **not** ship `zigporter`, `hab`, or firmware-watch MCP tools.

## Thin evidence (ADR-0005 tiers)

1. **File baseline** — YAML references under `/config`, Z2M/ESPHome config the Workspace can see, `.HA_VERSION`
2. **Core REST** — when available, entity/device state for the IDs under discussion (recommend, don’t require, for rename/draft work)
3. **Supervisor REST** — add-on logs (Z2M, ESPHome) when diagnosing those add-ons

**Fallback:** operator paste from Developer Tools / ZHA / Z2M / ESPHome UI, or drop under `/config/.t3code/exports/`. No long `curl` recipes here. Thin REST may not be in the running image yet.

Signal issues (weak LQI, bad parent, offline router) usually show in ZHA/Z2M UIs — ask for that evidence rather than guessing.

## Firmware updates

Guide the operator through Settings → Devices → the device’s `update.*` entity (or ESPHome Dashboard). Ask before they start; warn about power/bricking risk. Prefer a recent HA backup for large updates.

For Core/OS/Supervisor/add-on updates, use Settings → System → Updates — ask before they start; Core updates take the instance offline.

## Inspecting a device

Build the picture from tier order:

- YAML references: `grep -rn "entity_id" /config --include='*.yaml'` (and packages)
- Entity/device state via thin Core REST when available, else operator paste (Developer Tools → States)
- ZHA: integrations UI + device page
- Zigbee2MQTT: its add-on config / `configuration.yaml` / network map in the Z2M UI
- ESPHome: device YAML under the ESPHome add-on’s config path when mapped; otherwise ask the operator to paste

## Renaming

There is no cascade-rename CLI here. A safe rename plan:

1. Dry-run: find all references to the old id/name in `/config` YAML (and note that Jinja templates must be checked separately)
2. Show the full list to the operator
3. Prefer HA UI rename when it updates the entity registry, then fix remaining YAML references with approval
4. Tell the operator explicitly that templates like `{{ states('light.old_id') }}` need a manual pass

```
grep -rn "old_id" /config --include='*.yaml'
```

## Cleanup

Stale devices, post-migration duplicates (`_2` suffixes), and mesh repair are UI/integration workflows (ZHA/Z2M). Propose steps for the operator; do not delete devices from `.storage` by hand.

## ESPHome

- Prefer editing the device’s ESPHome YAML the operator points you at
- Compile/upload happens in the ESPHome Dashboard / add-on — ask them to run it
- After adoption, entity IDs may change; re-check automations and dashboards
