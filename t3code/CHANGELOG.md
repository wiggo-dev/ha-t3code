# Changelog

All notable changes to this Home Assistant add-on are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for **add-on releases** (`config.yaml` `version`). Nested T3/Cursor pin bumps are
mentioned only when they matter to operators.

## [0.3.4] - 2026-08-26

### Changed

- Pin matrix: t3 0.0.34, Cursor CLI 2026.08.25-3e8eec8

## [0.3.3] - 2026-08-24

### Added

- `hassio_role: homeassistant` so Supervisor `/core/logs` (Core journal) is allowed — default role only permits `/*/info` (403 otherwise)

### Changed

- DOCS: clarify `/core/logs` vs Core `/api/error_log`, and that the role unlock is GET-only by Skill policy (ADR-0006)

## [0.3.2] - 2026-08-24

### Added

- `homeassistant_api: true` so agents can use read-only Core REST via `SUPERVISOR_TOKEN` (ADR-0005)
- Create `/config/.t3code/exports/` on start for operator evidence drops
- DOCS thin-evidence section: short Core/Supervisor REST pointers (no long Skill recipes)

### Changed

- Known limitations / Skills: thin REST is available; file baseline remains preferred first

## [0.3.1] - 2026-08-24

### Changed

- Home Assistant Skills encode ADR-0008 gather → propose → operator-applies loop and name ADR-0005 evidence tiers
- Known limitations: Skill depth / thin evidence language aligned with ADR-0005/0006/0008

## [0.3.0] - 2026-08-24

### Added

- Pin matrix at image build: pinned `t3` + Cursor CLI lab tarball URL with checksums (ADR-0007)
- PATH wrapper injects `--disable-auto-update` for `cursor-agent` / `agent`
- Startup log fingerprint: `t3 --version` and `cursor-agent --version` next to the Add-on version
- Maintainer `scripts/bump-pins.sh` refreshes both pins together and patch-bumps the Add-on version

### Changed

- Operator upgrade path is Add-on Update/Rebuild only; previous Add-on version is break-glass rollback
- Known limitations: drop “no pin matrix”; document Update/Rebuild as the only supported upgrade

## [0.2.2] - 2026-08-24

### Added

- Supervisor `icon.png` and `logo.png`
- `DOCS.md` for the Supervisor Configuration / Documentation tab
- Root MIT `LICENSE`
- `hassio_api: true` so LAN pairing host detection can use Supervisor network info as a fallback

### Documentation

- Root README purpose and pointer into `t3code/`
- Known limitations for pin/upgrade and thin log evidence (not shipped in this release)

## [0.2.1] - 2026-08-20

### Added

- Server-side Cursor (`cursor-agent`) in the Debian add-on image
- Optional `cursor_api_key` with login-file fallback under Provider home `/data/home`
- Bundled Home Assistant Skills digest-synced into `/config/.agents/skills/`
- Tailscale / private-mesh pairing via `advertise_host` (LAN remains the default)

## [0.2.0] - 2026-08-19

### Added

- Phase 1: T3 Code headless server on Home Assistant OS
- Host-network bind on port 3773 and LAN pairing URL rewrite
