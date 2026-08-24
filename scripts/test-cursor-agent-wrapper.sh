#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="${ROOT}/t3code/cursor-agent-wrapper.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

fake="${TMP}/cursor-agent"
cat > "${fake}" <<'EOF'
#!/bin/bash
printf '%s\n' "$@"
EOF
chmod +x "${fake}" "${WRAPPER}"

export CURSOR_AGENT_BIN="${fake}"

got="$("${WRAPPER}" acp)"
[[ "${got}" == $'--disable-auto-update\nacp' ]] || {
  echo "expected injected flag, got: ${got}" >&2
  exit 1
}

got="$("${WRAPPER}" --disable-auto-update about)"
[[ "${got}" == $'--disable-auto-update\nabout' ]] || {
  echo "expected no duplicate flag, got: ${got}" >&2
  exit 1
}

echo "cursor-agent wrapper smoke test OK"
