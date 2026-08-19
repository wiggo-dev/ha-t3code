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
  local supervisor_ip=""
  local ip=""

  if bashio::var.has_value "${CONFIGURED_ADVERTISE_HOST}"; then
    printf '%s' "${CONFIGURED_ADVERTISE_HOST}"
    return 0
  fi

  supervisor_ip="$(bashio::api.supervisor GET /network/info '' \
    'first(.interfaces[] | select(.primary == true) | .ipv4[]? | select(.address != null and (.address | startswith("169.254") | not)) | .address) // empty' \
    || true)"
  if bashio::var.has_value "${supervisor_ip}"; then
    printf '%s' "${supervisor_ip}"
    return 0
  fi

  for ip in $(hostname -I 2>/dev/null); do
    if [[ "${ip}" != 127.* && "${ip}" != 172.30.* && "${ip}" != 169.254.* ]]; then
      printf '%s' "${ip}"
      return 0
    fi
  done
}

rewrite_pairing_output() {
  local advertise_host="$1"

  while IFS= read -r line; do
    case "${line}" in
      "Connection string:"*|"Pairing URL:"*)
        printf '%s\n' "$(printf '%s' "${line}" | sed -E "s|http://[^:/]+:${T3_PORT}|http://${advertise_host}:${T3_PORT}|g")"
        ;;
      "Token:"*)
        local token="${line#Token: }"
        printf '%s\n' "${line}"
        bashio::log.info "Use this LAN pairing URL from another device:"
        bashio::log.info "http://${advertise_host}:${T3_PORT}/pair#token=${token}"
        ;;
      *)
        printf '%s\n' "${line}"
        ;;
    esac
  done
}

ADVERTISE_HOST="$(resolve_advertise_host || true)"

bashio::log.info "T3 Code add-on version $(bashio::addon.version)"
bashio::log.info "Starting T3 Code headless server"
bashio::log.info "Working directory: ${T3_WORKDIR}"
bashio::log.info "State directory: ${T3_STATE_DIR}"
bashio::log.info "Listening on ${T3_HOST}:${T3_PORT}"

if bashio::var.has_value "${ADVERTISE_HOST}"; then
  bashio::log.info "LAN host for pairing: ${ADVERTISE_HOST}:${T3_PORT}"
else
  bashio::log.warning "Could not detect LAN address; set advertise_host in add-on options"
fi

bashio::log.info "Pairing URL and token will appear below once the server is ready"

if bashio::var.has_value "${ADVERTISE_HOST}"; then
  set -o pipefail
  t3 serve \
    --host "${T3_HOST}" \
    --port "${T3_PORT}" \
    --base-dir "${T3_STATE_DIR}" \
    "${T3_WORKDIR}" 2>&1 | rewrite_pairing_output "${ADVERTISE_HOST}"
  exit "${PIPESTATUS[0]}"
fi

exec t3 serve \
  --host "${T3_HOST}" \
  --port "${T3_PORT}" \
  --base-dir "${T3_STATE_DIR}" \
  "${T3_WORKDIR}"
