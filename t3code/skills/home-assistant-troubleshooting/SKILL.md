---
name: home-assistant-troubleshooting
description: Diagnose a Home Assistant problem without changing anything — unavailable entities, automations that did not fire, template errors, failing integrations, unhealthy systems. Gather thin evidence (files first, then Core/Supervisor REST), propose the smallest fix, and leave reload/restart/UI to the operator. Load when something is broken, missing, or behaving oddly.
---

# Troubleshooting Home Assistant

**Operator loop:** ask → gather thin evidence → propose the smallest change → operator approves edits and applies reload/restart/UI. Never call services, reload, restart, or control devices yourself.

**Read-only until the user asks for a fix.** Gather evidence, explain it, propose — and stop. Do not edit files while investigating.

## Thin evidence (ADR-0005 tiers)

Prefer this order for **runtime diagnosis**. Do not paste-dump as the happy path. Do not block a file-backed proposal when live evidence is missing.

1. **File baseline** (Workspace `/config`): `home-assistant.log`, `.HA_VERSION`, read-only `.storage/` registries, YAML via `grep` / `yq` / `jq`
2. **Core REST** — read-only states, history, logbook, `/error_log` via `http://supervisor/core/api` and `SUPERVISOR_TOKEN`
3. **Supervisor REST** — Core container journal `/core/logs` (needs `hassio_role: homeassistant`), `/resolution/info`, other allowed `GET`s via `http://supervisor`. Prefer Core `/api/error_log` for integration/YAML failures. Do **not** POST restart/stop/update.

**Fallback:** ask the operator for a short paste, or for a drop under `/config/.t3code/exports/`. Name the tier you need; short `curl` shapes live in add-on DOCS — do not paste long recipes into this Skill.

This Add-on does **not** ship MCP/`hab`/service-call tools. Thin REST is read-only evidence only.

## Keep investigation bounded

Do not dump every entity or the entire log into context.

- Start from the named entity, automation, or integration in the report
- Prefer short time windows for history/logbook
- Widen search only after a narrow query finds nothing

## Order of attack

1. Confirm the entity/automation/integration IDs from YAML or the report
2. Read the relevant YAML (automations, packages, templates)
3. Gather live evidence in tier order: state, recent history, logbook around the event, error log for that component
4. Check renames (old `entity_id` still referenced), battery/offline devices, and integration setup failures

| Symptom | Next evidence |
| --- | --- |
| `unavailable` / `unknown` | Device/integration status; error log for that integration; `last_updated` |
| Entity missing | Search YAML and entity registry for old/new IDs; integration load failures |
| Automation did not fire | Automation YAML; conditions vs history at trigger time; logbook for the automation |
| Template error | Exact expression; referenced entities exist and are not `unknown` at startup |
| Wrong value | History for the entity and its source |
| Integration failed setup | Error log; Supervisor repairs if applicable |
| Slow / restarting / disk | Supervisor health; recorder size; recent updates |

## Common causes

- Device offline, asleep, or low battery
- Renamed entity still referenced somewhere
- Integration failed at startup; dependents stay `unknown`
- Template without triggers that never recovers from startup `unavailable`
- Race: condition checked after the state already moved on
- Two automations fighting one entity
- Recorder exclusions hiding history
- Intentional user change — ask before calling it a bug

## Reporting

Observed → meaning → smallest proposed fix. Separate evidence from inference. End with a concrete proposal and wait.

If the fix needs configuration edits, hand off to `home-assistant-configuration` and get approval first. Tell the operator which reload/restart/UI step applies — never perform it.
