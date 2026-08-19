#!/usr/bin/with-contenv bashio
set -euo pipefail

T3_HOST="$(bashio::config 'host')"
T3_PORT="$(bashio::config 'port')"
T3_WORKDIR="/config"
T3_STATE_DIR="/data/t3"
CONFIGURED_ADVERTISE_HOST="$(bashio::config 'advertise_host')"

mkdir -p "${T3_STATE_DIR}"

export T3CODE_HOME="${T3_STATE_DIR}"

resolve_advertise_host() {
  if bashio::var.has_value "${CONFIGURED_ADVERTISE_HOST}"; then
    printf '%s' "${CONFIGURED_ADVERTISE_HOST}"
    return 0
  fi

  bashio::api.supervisor GET /network/info '' \
    'first(.interfaces[] | select(.primary == true) | .ipv4[]? | select(.address != null and (.address | startswith("169.254") | not)) | .address) // empty'
}

ADVERTISE_HOST="$(resolve_advertise_host || true)"

bashio::log.info "Starting T3 Code headless server"
bashio::log.info "Working directory: ${T3_WORKDIR}"
bashio::log.info "State directory: ${T3_STATE_DIR}"
bashio::log.info "Listening on ${T3_HOST}:${T3_PORT} (host network)"

if bashio::var.has_value "${ADVERTISE_HOST}"; then
  bashio::log.info "Pair from another machine on your LAN using host ${ADVERTISE_HOST} and port ${T3_PORT}"
  bashio::log.info "If the pairing URL below shows a 172.30.x.x address, replace it with http://${ADVERTISE_HOST}:${T3_PORT}/pair#token=<token>"
else
  bashio::log.warning "Could not detect LAN address automatically; set advertise_host in add-on options if needed"
fi

bashio::log.info "Pairing URL and token will appear below once the server is ready"

exec t3 serve \
  --host "${T3_HOST}" \
  --port "${T3_PORT}" \
  --base-dir "${T3_STATE_DIR}" \
  "${T3_WORKDIR}"
