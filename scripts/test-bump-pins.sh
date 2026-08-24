#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

mkdir -p "${TMP}/t3code" "${TMP}/scripts"
cp "${ROOT}/scripts/bump-pins.sh" "${TMP}/scripts/bump-pins.sh"
chmod +x "${TMP}/scripts/bump-pins.sh"

cat > "${TMP}/t3code/Dockerfile" <<'EOF'
ARG BUILD_FROM=ghcr.io/home-assistant/base-debian:trixie
ARG T3_VERSION=0.0.33
ARG CURSOR_VERSION=2026.08.11-e8db854
ARG CURSOR_SHA256_LINUX_X64=oldx64
ARG CURSOR_SHA256_LINUX_ARM64=oldarm64

FROM ${BUILD_FROM}

ARG T3_VERSION
ARG CURSOR_VERSION
ARG CURSOR_SHA256_LINUX_X64
ARG CURSOR_SHA256_LINUX_ARM64
EOF

cat > "${TMP}/t3code/config.yaml" <<'EOF'
name: T3 Code
version: "0.3.0"
slug: t3code
EOF

cat > "${TMP}/t3code/CHANGELOG.md" <<'EOF'
# Changelog

## [0.3.0] - 2026-08-24

### Added

- Pin matrix
EOF

T3_VERSION=0.0.34 \
  CURSOR_VERSION=2026.09.01-deadbee \
  CURSOR_SHA256_LINUX_X64=aaa \
  CURSOR_SHA256_LINUX_ARM64=bbb \
  "${TMP}/scripts/bump-pins.sh" >/dev/null

grep -q 'ARG T3_VERSION=0.0.34' "${TMP}/t3code/Dockerfile" || { echo "t3 pin not written"; exit 1; }
grep -q 'ARG CURSOR_VERSION=2026.09.01-deadbee' "${TMP}/t3code/Dockerfile" || { echo "cursor pin not written"; exit 1; }
grep -q 'ARG CURSOR_SHA256_LINUX_X64=aaa' "${TMP}/t3code/Dockerfile" || { echo "x64 checksum not written"; exit 1; }
grep -q 'ARG CURSOR_SHA256_LINUX_ARM64=bbb' "${TMP}/t3code/Dockerfile" || { echo "arm64 checksum not written"; exit 1; }
grep -q 'version: "0.3.1"' "${TMP}/t3code/config.yaml" || { echo "config.yaml not patch-bumped"; exit 1; }
grep -q '## \[0.3.1\]' "${TMP}/t3code/CHANGELOG.md" || { echo "CHANGELOG missing new heading"; exit 1; }
grep -q 'Pin matrix: t3 0.0.34, Cursor CLI 2026.09.01-deadbee' "${TMP}/t3code/CHANGELOG.md" || {
  echo "CHANGELOG missing pin gist"
  exit 1
}
grep -q '## \[0.3.0\]' "${TMP}/t3code/CHANGELOG.md" || { echo "previous CHANGELOG heading lost"; exit 1; }

echo "bump-pins smoke test OK"
