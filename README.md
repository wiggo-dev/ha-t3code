# T3 Code on Home Assistant

A Home Assistant OS add-on that runs [T3 Code](https://github.com/pingdotgg/t3code) in headless server mode so you can pair from the T3 desktop app and use Server-side Cursor against `/config`.

**Current release:** add-on **0.3.5** — pin matrix, store-ready custom repo, thin Core/Supervisor REST evidence (including Core journal via `/core/logs`), Home Assistant Skills with gather→propose→operator-applies guidance.

**Operator docs** (install, pair, Tailscale, Cursor, Skills, thin evidence): [`t3code/README.md`](t3code/README.md) · Supervisor tab: [`t3code/DOCS.md`](t3code/DOCS.md)

Add this GitHub repo as a custom add-on repository:

```
https://github.com/wiggo-dev/ha-t3code
```

Then install **T3 Code**, Update/Rebuild after repo changes, and confirm the startup log shows `T3 Code add-on version 0.3.5` plus **Pin matrix** lines.

Domain glossary: [`CONTEXT.md`](CONTEXT.md) · Decisions: [`docs/adr/`](docs/adr/)
