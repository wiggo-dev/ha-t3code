---
name: home-assistant-development
description: Develop for Home Assistant rather than only configure it — custom integrations under custom_components/, local add-ons, and notes on HA native llm/MCP surfaces. Load for Python integrations, add-on Dockerfile/config.yaml, manifests, or LLM tool provider code.
---

# Developing for Home Assistant

This is code, not configuration. Consent still applies. Do not hand-edit `.storage/` or other internal directories.

This Add-on does **not** consume or expose OpenCode’s HA MCP server. Native HA `llm` / MCP endpoints are documented for when the operator’s Home Assistant version supports them.

## Custom integrations

Live at `custom_components/<domain>/` with at least `manifest.json` and `__init__.py`. Manifest needs `domain`, `name`, `version`, `documentation`, `dependencies`, `codeowners`, `requirements`, `iot_class`.

Check current developer docs (https://developers.home-assistant.io) for:

- Config-flow vs YAML setup
- `async_setup_entry` / coordinator patterns
- Entity naming attributes
- `async_forward_entry_setups`

**Any change under `custom_components/` needs a full Home Assistant restart.** Say so and ask.

## Native LLM / MCP (informational)

Home Assistant can expose curated LLM tools via an integration’s `llm.py` and, on newer cores, native MCP endpoints such as `/api/mcp/assist` when the MCP Server integration is configured.

- Writing `llm.py` belongs in a custom integration; this Add-on cannot register tools into HA’s llm platform
- Consuming those endpoints from T3/Cursor is out of scope until a later MCP parity decision
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
3. Remind about restart / rebuild requirements
4. Suggest how to verify (logs, smoke config entry, Supervisor rebuild)
