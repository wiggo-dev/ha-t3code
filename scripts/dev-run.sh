#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-ha-t3code-dev}"
PORT="${PORT:-3773}"
CONFIG_DIR="${CONFIG_DIR:-${ROOT}/.dev/config}"
DATA_DIR="${DATA_DIR:-${ROOT}/.dev/data}"
ADVERTISE_HOST="${ADVERTISE_HOST:-127.0.0.1}"

mkdir -p "${CONFIG_DIR}" "${DATA_DIR}/t3"
printf '%s\n' "{\"host\":\"0.0.0.0\",\"port\":${PORT},\"advertise_host\":\"${ADVERTISE_HOST}\"}" > "${DATA_DIR}/options.json"

echo "Building ${IMAGE} from t3code/ ..."
docker build --build-arg BUILD_VERSION=dev -t "${IMAGE}" "${ROOT}/t3code"

echo "Starting dev container on http://${ADVERTISE_HOST}:${PORT}"
echo "Config mount: ${CONFIG_DIR} -> /config"
echo "State mount:  ${DATA_DIR} -> /data"

exec docker run --rm -it \
  --name ha-t3code-dev \
  -p "${PORT}:${PORT}" \
  -v "${CONFIG_DIR}:/config" \
  -v "${DATA_DIR}:/data" \
  "${IMAGE}"
