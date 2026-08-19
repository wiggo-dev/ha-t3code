#!/usr/bin/with-contenv bashio
set -euo pipefail

T3_HOST="$(bashio::config 'host')"
T3_PORT="$(bashio::config 'port')"
T3_WORKDIR="/config"
T3_STATE_DIR="/data/t3"

mkdir -p "${T3_STATE_DIR}"

export T3CODE_HOME="${T3_STATE_DIR}"

bashio::log.info "Starting T3 Code headless server"
bashio::log.info "Working directory: ${T3_WORKDIR}"
bashio::log.info "State directory: ${T3_STATE_DIR}"
bashio::log.info "Listening on ${T3_HOST}:${T3_PORT}"
bashio::log.info "Pairing URL and token will appear below once the server is ready"

exec t3 serve \
  --host "${T3_HOST}" \
  --port "${T3_PORT}" \
  --base-dir "${T3_STATE_DIR}" \
  "${T3_WORKDIR}"
