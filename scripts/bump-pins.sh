#!/usr/bin/env bash
# Refresh the t3 + Cursor CLI pin matrix together (ADR-0007).
# Writes Dockerfile ARGs, patch-bumps the Add-on version, and prepends CHANGELOG.
# Does not commit or push: print those as the Supervisor release step.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="${ROOT}/t3code/Dockerfile"
CONFIG_YAML="${ROOT}/t3code/config.yaml"
CHANGELOG="${ROOT}/t3code/CHANGELOG.md"

lab_url() {
  local version="$1" arch="$2"
  printf 'https://downloads.cursor.com/lab/%s/linux/%s/agent-cli-package.tar.gz' "${version}" "${arch}"
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{print $1}'
  else
    shasum -a 256 "${path}" | awk '{print $1}'
  fi
}

patch_bump() {
  python3 -c '
import sys
parts = sys.argv[1].split(".")
if len(parts) != 3 or not all(p.isdigit() for p in parts):
    sys.exit(f"expected X.Y.Z add-on version, got {sys.argv[1]!r}")
parts[2] = str(int(parts[2]) + 1)
print(".".join(parts))
' "$1"
}

replace_arg_default() {
  local file="$1" name="$2" value="$3"
  python3 -c '
from pathlib import Path
import re, sys
path, name, value = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
pattern = rf"^(ARG {re.escape(name)}=).*$"
new, n = re.subn(pattern, rf"\g<1>{value}", text, count=1, flags=re.M)
if n != 1:
    sys.exit(f"expected one ARG {name}= default in {path}")
path.write_text(new)
' "${file}" "${name}" "${value}"
}

current_t3="$(python3 -c '
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text()
m = re.search(r"^ARG T3_VERSION=(.+)$", text, re.M)
sys.exit("missing ARG T3_VERSION") if not m else print(m.group(1).strip())
' "${DOCKERFILE}")"

current_cursor="$(python3 -c '
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text()
m = re.search(r"^ARG CURSOR_VERSION=(.+)$", text, re.M)
sys.exit("missing ARG CURSOR_VERSION") if not m else print(m.group(1).strip())
' "${DOCKERFILE}")"

addon_version="$(python3 -c '
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text()
m = re.search(r"^version:\s*\"([^\"]+)\"", text, re.M)
sys.exit("missing config.yaml version") if not m else print(m.group(1))
' "${CONFIG_YAML}")"

if [[ -z "${T3_VERSION:-}" ]]; then
  T3_VERSION="$(curl -fsSL https://registry.npmjs.org/t3/latest | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
fi

if [[ -z "${CURSOR_VERSION:-}" ]]; then
  CURSOR_VERSION="$(curl -fsSL https://cursor.com/install | python3 -c '
import re, sys
text = sys.stdin.read()
matches = re.findall(r"downloads\.cursor\.com/lab/([^/]+)/", text)
if not matches:
    sys.exit("could not parse lab version from cursor.com/install")
print(matches[0])
')"
fi

if [[ -z "${CURSOR_SHA256_LINUX_X64:-}" || -z "${CURSOR_SHA256_LINUX_ARM64:-}" ]]; then
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT
  curl -fsSL "$(lab_url "${CURSOR_VERSION}" x64)" -o "${tmpdir}/x64.tar.gz"
  curl -fsSL "$(lab_url "${CURSOR_VERSION}" arm64)" -o "${tmpdir}/arm64.tar.gz"
  CURSOR_SHA256_LINUX_X64="$(sha256_file "${tmpdir}/x64.tar.gz")"
  CURSOR_SHA256_LINUX_ARM64="$(sha256_file "${tmpdir}/arm64.tar.gz")"
fi

new_addon_version="$(patch_bump "${addon_version}")"
today="$(date +%F)"

replace_arg_default "${DOCKERFILE}" T3_VERSION "${T3_VERSION}"
replace_arg_default "${DOCKERFILE}" CURSOR_VERSION "${CURSOR_VERSION}"
replace_arg_default "${DOCKERFILE}" CURSOR_SHA256_LINUX_X64 "${CURSOR_SHA256_LINUX_X64}"
replace_arg_default "${DOCKERFILE}" CURSOR_SHA256_LINUX_ARM64 "${CURSOR_SHA256_LINUX_ARM64}"

python3 -c '
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text()
new, n = re.subn(r"^version:\s*\"[^\"]+\"", f"version: \"{version}\"", text, count=1, flags=re.M)
if n != 1:
    sys.exit("failed to patch-bump config.yaml version")
path.write_text(new)
' "${CONFIG_YAML}" "${new_addon_version}"

python3 -c '
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
version, today, t3, cursor = sys.argv[2:6]
entry = (
    f"## [{version}] - {today}\n\n"
    f"### Changed\n\n"
    f"- Pin matrix: t3 {t3}, Cursor CLI {cursor}\n\n"
)
text = path.read_text()
marker = "## ["
idx = text.find(marker)
if idx < 0:
    sys.exit("CHANGELOG.md has no version heading to prepend before")
path.write_text(text[:idx] + entry + text[idx:])
' "${CHANGELOG}" "${new_addon_version}" "${today}" "${T3_VERSION}" "${CURSOR_VERSION}"

echo "Pin matrix refreshed:"
echo "  t3:              ${current_t3} -> ${T3_VERSION}"
echo "  Cursor CLI:      ${current_cursor} -> ${CURSOR_VERSION}"
echo "  linux/x64 sha256:    ${CURSOR_SHA256_LINUX_X64}"
echo "  linux/arm64 sha256:  ${CURSOR_SHA256_LINUX_ARM64}"
echo "  Add-on version:  ${addon_version} -> ${new_addon_version}"
echo
echo "Supervisor release is commit + push of this tree (custom repo: Check for updates → Update/Rebuild)."
echo "  git add t3code/Dockerfile t3code/config.yaml t3code/CHANGELOG.md"
echo "  git commit -m \"Bump pin matrix to t3 ${T3_VERSION} + Cursor ${CURSOR_VERSION}\""
echo "  git push"
