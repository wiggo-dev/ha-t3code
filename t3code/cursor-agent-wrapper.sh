#!/bin/bash
# PATH wrapper: inject --disable-auto-update so T3's ACP spawn (`cursor-agent acp`)
# cannot float the Cursor CLI (ADR-0007).
set -euo pipefail

REAL="${CURSOR_AGENT_BIN:-}"
if [[ -z "${REAL}" || ! -x "${REAL}" ]]; then
  echo "cursor-agent wrapper: CURSOR_AGENT_BIN is missing or not executable: ${REAL:-<unset>}" >&2
  exit 127
fi

for arg in "$@"; do
  if [[ "${arg}" == "--disable-auto-update" ]]; then
    exec "${REAL}" "$@"
  fi
done

exec "${REAL}" --disable-auto-update "$@"
