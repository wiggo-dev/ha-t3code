# T3 Code on Home Assistant

Remote T3 Code server running as a Home Assistant add-on so agents can work against the Home Assistant configuration from another machine.

## Language

**Add-on**:
The Home Assistant Supervisor app that packages and runs the T3 Code server in a container on Home Assistant OS.
_Avoid_: plugin, integration, container (when meaning the Supervisor-managed unit)

**Workspace**:
The directory on the Home Assistant host that T3 treats as the project root for agent sessions. Today this is Home Assistant's `/config`.
_Avoid_: cwd, project folder, home directory

**Provider**:
An external agent CLI that T3 spawns on the Add-on to run agent turns (for example Cursor via `cursor-agent`).
_Avoid_: model, LLM, backend (when meaning the CLI process)

**Server-side Cursor**:
Running the Cursor CLI (`cursor-agent`) inside the Add-on so T3 can use the Cursor provider against the Workspace.
_Avoid_: local Cursor, desktop Cursor, Cursor app

**Provider home**:
The Add-on's persistent directory for Provider CLI auth and XDG state (`/data/home`), kept outside the Workspace. Process `HOME` remains the Workspace so `~` means `/config`.
_Avoid_: Cursor home, workspace home, HOME=/data/home (when meaning the shell home / `~`)

**Skill**:
An on-demand procedure document (`SKILL.md`) the Provider can load for a task. Bundled Home Assistant Skills and operator-added user Skills share one Agent Skills tree in the Workspace.
_Avoid_: prompt, agent instruction, MCP tool (those are different artifacts)

**Home Assistant Skills**:
The five bundled Skills for HA work: configuration, troubleshooting, dashboard-ui, zigbee-esphome, and development (origin: OpenCode HA add-on docs). Shipped by the Add-on; operator edits of those copies are preserved across upgrades.
_Avoid_: OpenCode skills (when meaning only those five without naming them)
