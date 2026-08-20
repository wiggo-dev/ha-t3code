---
name: home-assistant-zigbee-esphome
description: Work with Zigbee and ESPHome devices in a file-first Workspace — inspect references across YAML, plan renames carefully, reason about ZHA/Z2M/ESPHome config, and guide firmware updates the operator runs in the UI. Load for Zigbee, ZHA, Z2M, ESPHome, or device-firmware requests.
---

# Zigbee and ESPHome devices

This Add-on does **not** ship `zigporter`, `hab`, or firmware-watch MCP tools. Use Workspace files, Z2M/ZHA/ESPHome configs the operator can access, and HA UI for live device/mesh/firmware actions.

## Firmware updates

Guide the operator through Settings → Devices → the device’s `update.*` entity (or ESPHome Dashboard). Ask before starting; warn about power/bricking risk. Prefer a recent HA backup for large updates.

For Core/OS/Supervisor/add-on updates, use Settings → System → Updates — ask before starting; Core updates take the instance offline.

## Inspecting a device

Without zigporter, build the picture from:

- Entity/device names the operator provides (Developer Tools → States)
- YAML references: `grep -rn "entity_id" /config --include='*.yaml'` (and packages)
- ZHA: integrations UI + device page
- Zigbee2MQTT: its add-on config / `configuration.yaml` / network map in the Z2M UI
- ESPHome: device YAML under the ESPHome add-on’s config path when mapped; otherwise ask the operator to paste

Signal issues (weak LQI, bad parent, offline router) usually show in ZHA/Z2M UIs — ask for that evidence rather than guessing.

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

Stale devices, post-migration duplicates (`_2` suffixes), and mesh repair are UI/integration workflows (ZHA/Z2M). Propose steps; do not delete devices from `.storage` by hand.

## ESPHome

- Prefer editing the device’s ESPHome YAML the operator points you at
- Compile/upload happens in the ESPHome Dashboard / add-on — ask them to run it
- After adopotion, entity IDs may change; re-check automations and dashboards
