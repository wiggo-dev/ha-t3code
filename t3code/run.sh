#!/usr/bin/with-contenv bashio
set -euo pipefail

T3_HOST="$(bashio::config 'host' || true)"
T3_PORT="$(bashio::config 'port' || true)"
T3_WORKDIR="/config"
T3_STATE_DIR="/data/t3"
CONFIGURED_ADVERTISE_HOST="$(bashio::config 'advertise_host' || true)"

T3_HOST="${T3_HOST:-0.0.0.0}"
T3_PORT="${T3_PORT:-3773}"

mkdir -p "${T3_STATE_DIR}"

export T3CODE_HOME="${T3_STATE_DIR}"
export HOME="${T3_WORKDIR}"

resolve_advertise_host() {
  local supervisor_ip=""
  local ip=""

  if bashio::var.has_value "${CONFIGURED_ADVERTISE_HOST}"; then
    printf '%s' "${CONFIGURED_ADVERTISE_HOST}"
    return 0
  fi

  for ip in $(hostname -I 2>/dev/null); do
    if [[ "${ip}" != 127.* && "${ip}" != 172.30.* && "${ip}" != 169.254.* ]]; then
      printf '%s' "${ip}"
      return 0
    fi
  done

  supervisor_ip="$(bashio::api.supervisor GET /network/info '' \
    'first(.interfaces[] | select(.primary == true) | .ipv4[]? | select(.address != null and (.address | startswith("169.254") | not)) | .address) // empty' \
    2>/dev/null || true)"
  if bashio::var.has_value "${supervisor_ip}"; then
    printf '%s' "${supervisor_ip}"
  fi
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

wait_for_t3_server() {
  local attempt=0

  while ! wget -q -O /dev/null "http://127.0.0.1:${T3_PORT}/.well-known/t3/environment" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [[ "${attempt}" -gt 120 ]]; then
      bashio::log.warning "Timed out waiting for T3 Code to become ready"
      return 1
    fi
    sleep 1
  done
}

print_pairing_info() {
  wait_for_t3_server || return 0

  if bashio::var.has_value "${ADVERTISE_HOST}"; then
    t3 pair --base-dir "${T3_STATE_DIR}" 2>&1 | rewrite_pairing_output "${ADVERTISE_HOST}" || true
  else
    t3 pair --base-dir "${T3_STATE_DIR}" || true
  fi
}

ADVERTISE_HOST="$(resolve_advertise_host || true)"

bashio::log.info "T3 Code add-on version $(bashio::addon.version 2>/dev/null || echo 'dev')"
bashio::log.info "Starting T3 Code server"
bashio::log.info "Default workspace: ${T3_WORKDIR}"
bashio::log.info "State directory: ${T3_STATE_DIR}"
bashio::log.info "Listening on ${T3_HOST}:${T3_PORT}"

if bashio::var.has_value "${ADVERTISE_HOST}"; then
  bashio::log.info "LAN host for pairing: ${ADVERTISE_HOST}:${T3_PORT}"
else
  bashio::log.warning "Could not detect LAN address; set advertise_host in add-on options"
fi

bashio::log.info "Pairing URL and token will appear below once the server is ready"

print_pairing_info &

cd "${T3_WORKDIR}"

T3_ARGS=(
  start
  --host "${T3_HOST}"
  --port "${T3_PORT}"
  --base-dir "${T3_STATE_DIR}"
  --no-browser
  --auto-bootstrap-project-from-cwd
  "${T3_WORKDIR}"
)

if bashio::var.has_value "${ADVERTISE_HOST}"; then
  set -o pipefail
  t3 "${T3_ARGS[@]}" 2>&1 | rewrite_pairing_output "${ADVERTISE_HOST}"
  exit "${PIPESTATUS[0]}"
fi

exec t3 "${T3_ARGS[@]}"
