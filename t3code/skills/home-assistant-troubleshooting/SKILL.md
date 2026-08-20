---
name: home-assistant-troubleshooting
description: Diagnose a Home Assistant problem without changing anything — unavailable entities, automations that did not fire, template errors, failing integrations, unhealthy systems. Gather evidence from files and operator-provided UI/API output, then recommend a fix. Load when something is broken, missing, or behaving oddly.
---

# Troubleshooting Home Assistant

**Read-only until the user asks for a fix.** Gather evidence, explain it, propose the smallest change — and stop. Do not edit files, call services, restart, or reload while investigating.

This Add-on does **not** ship live HA MCP tools. Use Workspace files, logs the operator can share, Developer Tools, and Settings UI. Ask the operator for states/history/log excerpts when you cannot see the running system.

## Keep investigation bounded

Do not dump every entity or the entire log into context.

- Start from the named entity, automation, or integration in the report
- Prefer short time windows for history/logbook when the operator pastes them
- Widen search only after a narrow query finds nothing

## Order of attack

1. Confirm the entity/automation/integration IDs from YAML or the report
2. Read the relevant YAML (automations, packages, templates)
3. Ask for or inspect: current state, recent history, logbook around the event, and error log lines for that component
4. Check renames (old `entity_id` still referenced), battery/offline devices, and integration setup failures

| Symptom | Next evidence |
| --- | --- |
| `unavailable` / `unknown` | Device/integration status; error log for that integration; `last_updated` |
| Entity missing | Search YAML and entity registry exports for old/new IDs; integration load failures |
| Automation did not fire | Automation YAML; conditions vs history at trigger time; logbook for the automation |
| Template error | Exact expression; referenced entities exist and are not `unknown` at startup |
| Wrong value | History for the entity and its source |
| Integration failed setup | Error log; Supervisor repairs if applicable |
| Slow / restarting / disk | Supervisor health/metrics; recorder size; recent updates |

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

If the fix needs configuration edits, hand off to `home-assistant-configuration` and get approval first. If it needs reload/restart, say which and why — never do it as part of investigating.
