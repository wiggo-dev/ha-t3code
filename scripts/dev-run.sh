#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-ha-t3code-dev}"
PORT="${PORT:-3773}"
CONFIG_DIR="${CONFIG_DIR:-${ROOT}/.dev/config}"
DATA_DIR="${DATA_DIR:-${ROOT}/.dev/data}"
ADVERTISE_HOST="${ADVERTISE_HOST:-127.0.0.1}"

mkdir -p "${CONFIG_DIR}" "${DATA_DIR}/t3" "${DATA_DIR}/home"

OPTIONS_JSON="$(printf '{"host":"0.0.0.0","port":%s,"advertise_host":"%s"' "${PORT}" "${ADVERTISE_HOST}")"
if [[ -n "${CURSOR_API_KEY:-}" ]]; then
  # Escape for JSON string
  ESCAPED_KEY="$(printf '%s' "${CURSOR_API_KEY}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])')"
  OPTIONS_JSON="${OPTIONS_JSON},\"cursor_api_key\":\"${ESCAPED_KEY}\""
else
  OPTIONS_JSON="${OPTIONS_JSON},\"cursor_api_key\":\"\""
fi
OPTIONS_JSON="${OPTIONS_JSON}}"
printf '%s\n' "${OPTIONS_JSON}" > "${DATA_DIR}/options.json"

echo "Building ${IMAGE} from t3code/ ..."
docker build --build-arg BUILD_VERSION=dev -t "${IMAGE}" "${ROOT}/t3code"

echo "Starting dev container on http://${ADVERTISE_HOST}:${PORT}"
echo "Config mount: ${CONFIG_DIR} -> /config"
echo "State mount:  ${DATA_DIR} -> /data"

RUN_ENV=()
if [[ -n "${CURSOR_API_KEY:-}" ]]; then
  RUN_ENV+=(-e "CURSOR_API_KEY=${CURSOR_API_KEY}")
fi

exec docker run --rm -it \
  --name ha-t3code-dev \
  -p "${PORT}:${PORT}" \
  -v "${CONFIG_DIR}:/config" \
  -v "${DATA_DIR}:/data" \
  "${RUN_ENV[@]}" \
  "${IMAGE}"
