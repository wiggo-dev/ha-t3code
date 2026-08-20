#!/usr/bin/env bash
# Smoke-test digest sync for deploy-skills.py (no Docker required).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

SOURCE="${TMP}/source"
TARGET="${TMP}/target"
STATE="${TMP}/state.json"
mkdir -p "${SOURCE}/demo" "${TARGET}"

printf 'v1\n' > "${SOURCE}/demo/SKILL.md"

export SKILLS_SOURCE="${SOURCE}" SKILLS_TARGET="${TARGET}" SKILLS_STATE="${STATE}"
python3 "${ROOT}/t3code/deploy-skills.py" >/dev/null

[[ -f "${TARGET}/demo/SKILL.md" ]] || { echo "missing deploy"; exit 1; }
[[ "$(cat "${TARGET}/demo/SKILL.md")" == "v1" ]] || { echo "bad content"; exit 1; }

printf 'v2\n' > "${SOURCE}/demo/SKILL.md"
python3 "${ROOT}/t3code/deploy-skills.py" >/dev/null
[[ "$(cat "${TARGET}/demo/SKILL.md")" == "v2" ]] || { echo "should refresh unmodified"; exit 1; }

printf 'mine\n' > "${TARGET}/demo/SKILL.md"
printf 'v3\n' > "${SOURCE}/demo/SKILL.md"
out="$(python3 "${ROOT}/t3code/deploy-skills.py" 2>&1 || true)"
[[ "$(cat "${TARGET}/demo/SKILL.md")" == "mine" ]] || { echo "should preserve edit"; exit 1; }
printf '%s\n' "${out}" | grep -q 'Keeping your edited' || { echo "expected warning"; exit 1; }

echo "deploy-skills smoke test OK"
