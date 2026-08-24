---
name: home-assistant-dashboard-ui
description: Build or change Home Assistant dashboards — Lovelace views, cards, layouts, themes, badges, custom cards and card-mod. Covers storage vs YAML mode, the standard card set, and how to verify without screenshot tooling. Load for Lovelace, dashboard, view, card, or theme work.
---

# Dashboards and UI

**Operator loop:** ask → gather thin evidence → propose the smallest change → operator approves edits and applies reload/restart/UI. Never call services, reload, restart, or control devices yourself.

This Add-on does **not** ship `hab` dashboard CLI or screenshot MCP tools. Work through YAML-mode files when available; for storage-mode dashboards, guide the operator via the HA UI (or raw `.storage` only if they explicitly accept that risk).

## Thin evidence (ADR-0005 tiers)

Dashboard work is mostly **configuration**: files + docs. Confirm entity IDs from the Workspace before inventing them. When thin Core REST is available, **recommend** a quick existence/state check for entities named in the draft.

1. **File baseline** — `configuration.yaml` / `ui-lovelace.yaml` / included dashboard YAML; themes under `themes/`
2. **Core REST** — optional entity existence/state when drafting cards
3. **Supervisor REST** — not needed for dashboard YAML

**Fallback:** operator paste (States / UI) or `/config/.t3code/exports/`. No long `curl` recipes here. Thin REST may not be in the running image yet.

## Which mechanism this installation uses

Find out before proposing changes — the modes are not interchangeable.

- **Storage mode (default):** dashboards live under `.storage/`. Do **not** hand-edit `.storage` unless the operator explicitly asks and understands the risk. Prefer HA UI: Settings → Dashboards, or ask the operator to switch a dashboard to YAML mode.
- **YAML mode:** `lovelace:` in `configuration.yaml` points at dashboard files. Then it is ordinary YAML — use `home-assistant-configuration` style rules.

List dashboards from `configuration.yaml` / `ui-lovelace.yaml` / included files when in YAML mode. For storage mode, ask the operator which dashboard/`url_path` they mean.

## Building a view

Do not invent entity IDs — confirm from Workspace files, thin REST when available, or operator paste (Developer Tools → States).

Standard cards: `entities`, `tile`, `button`, `light`, `thermostat`, `media-control`, `weather-forecast`, `history-graph`, `statistics-graph`, `gauge`, `picture-elements`, `map`, `markdown`, `todo-list`, `area`, plus layout cards `grid`, `vertical-stack`, `horizontal-stack`, `sections`.

- **`conditional`** — hide cards when irrelevant
- **`custom:`** — requires HACS/resources; check `www/` / lovelace resources before using
- **card-mod** — also needs its resource installed

Views: `title`, `path`, `icon`, `type` (`sections`, `panel`, `masonry`, `sidebar`), `badges`, `cards`. Match the existing view type before adding cards.

Follow the HA YAML style guide for dashboard YAML.

## Verifying visually

No headless screenshot tool is bundled. After an approved change:

1. Ask the operator to open the dashboard (desktop and mobile if layout-sensitive)
2. Check for red error cards, `Unavailable` entities, dropped titles, bad wrapping
3. Iterate from their report

## Themes

Themes live in `themes/` and are referenced from `frontend:` in `configuration.yaml`. Adding one usually needs the operator to restart or reload themes — say which and let them apply it.
