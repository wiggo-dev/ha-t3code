---
name: home-assistant-development
description: Develop for Home Assistant rather than only configure it — custom integrations under custom_components/, local add-ons, and notes on HA native llm/MCP surfaces. Load for Python integrations, add-on Dockerfile/config.yaml, manifests, or LLM tool provider code.
---

# Developing for Home Assistant

**Operator loop:** ask → gather thin evidence → propose the smallest change → operator approves edits and applies reload/restart/UI. Never call services, reload, restart, or control devices yourself.

**Evidence shell:** `yq`, `grep`, `jq`, and read-only `curl` to Core/Supervisor REST (`SUPERVISOR_TOKEN`). That is the full set — do not probe PATH for other HA CLIs.

This is code, not configuration. Consent still applies. Do not hand-edit `.storage/` or other internal directories. Tooling stays files + thin REST (ADR-0006); native HA `llm` / MCP notes below are informational only.

## Thin evidence (ADR-0005 tiers)

Development work is mostly **files + docs**. Use higher tiers when debugging a running integration or add-on:

1. **File baseline** — `custom_components/`, manifests, local add-on sources, `home-assistant.log`
2. **Core REST** — entity/state checks after the operator reloads or restarts (`SUPERVISOR_TOKEN` → `http://supervisor/core/api`)
3. **Supervisor REST** — add-on logs, resolution/info, host health (`http://supervisor`)

**Fallback:** operator paste or `/config/.t3code/exports/`. Short recipes: add-on DOCS.

## Custom integrations

Live at `custom_components/<domain>/` with at least `manifest.json` and `__init__.py`. Manifest needs `domain`, `name`, `version`, `documentation`, `dependencies`, `codeowners`, `requirements`, `iot_class`.

Check current developer docs (https://developers.home-assistant.io) for:

- Config-flow vs YAML setup
- `async_setup_entry` / coordinator patterns
- Entity naming attributes
- `async_forward_entry_setups`

**Any change under `custom_components/` needs a full Home Assistant restart.** Tell the operator; never restart yourself.

## Native LLM / MCP (informational)

Home Assistant can expose curated LLM tools via an integration’s `llm.py` and, on newer cores, native MCP endpoints such as `/api/mcp/assist` when the MCP Server integration is configured.

- Writing `llm.py` belongs in a custom integration; this Add-on cannot register tools into HA’s llm platform
- Consuming those endpoints from T3/Cursor is out of scope (ADR-0006)
- Prefer official HA developer docs over remembered API shapes

## Home Assistant add-ons

Local add-on sources may be under `/addons` only if the operator mapped that path. Treat other add-ons’ `/addon_configs` as sensitive.

Add-on basics:

- `config.yaml` `options:` and `schema:` keys must align
- `map:` controls mounts (`homeassistant_config`, `addons`, …)
- `hassio_api` / `homeassistant_api` — request the least privilege needed
- Optional init must not fail the container boot

## Workflow

1. Read existing code and manifests before editing
2. Show the diff; wait for approval
3. Tell the operator about restart / rebuild requirements (they apply)
4. Suggest how to verify (logs via file baseline or Supervisor REST, smoke config entry, Supervisor rebuild)
