#!/usr/bin/env bash
set -euo pipefail

APP_NAME="quote-geolocation"
SERVICE_NAME="${QUOTE_GEO_SERVICE_NAME:-${SERVICE_NAME:-quote-geolocation}}"
SERVICE_USER="${QUOTE_GEO_SERVICE_USER:-${SERVICE_USER:-quotegeo}}"
SERVICE_ROOT="${QUOTE_GEO_SERVICE_ROOT:-${SERVICE_ROOT:-/opt/services/${APP_NAME}}}"
APP_DIR="${QUOTE_GEO_APP_DIR:-${APP_DIR:-${SERVICE_ROOT}/app}}"
VENV_DIR="${QUOTE_GEO_VENV_DIR:-${VENV_DIR:-${SERVICE_ROOT}/.venv}}"
CONFIG_DIR="${QUOTE_GEO_CONFIG_DIR:-${CONFIG_DIR:-${SERVICE_ROOT}/config}}"
DATA_DIR="${QUOTE_GEO_DATA_DIR:-${DATA_DIR:-${SERVICE_ROOT}/data}}"
LOG_DIR="${QUOTE_GEO_LOG_DIR:-${LOG_DIR:-${SERVICE_ROOT}/logs}}"
ENV_FILE="${QUOTE_GEO_ENV_FILE:-${ENV_FILE:-${CONFIG_DIR}/zoho_quote_geocode.env}}"
META_FILE="${QUOTE_GEO_META_FILE:-${META_FILE:-${CONFIG_DIR}/install-meta.env}}"
PATHS_FILE="${QUOTE_GEO_PATHS_FILE:-${PATHS_FILE:-${CONFIG_DIR}/paths.txt}}"
REPO_URL="${QUOTE_GEO_REPO_URL:-${REPO_URL:-https://github.com/yboucher97/Update-Quote-Geolocation.git}}"
REPO_REF="${QUOTE_GEO_REPO_REF:-${REPO_REF:-main}}"
PORT="${QUOTE_GEO_PORT:-${PORT:-8050}}"
HOST="${QUOTE_GEO_HOST:-${HOST:-}}"
WEBHOOK_SECRET="${QUOTE_GEO_WEBHOOK_SECRET:-${ZOHO_QUOTE_WEBHOOK_SECRET:-}}"
UFW_MODE="${QUOTE_GEO_CONFIGURE_UFW:-auto}"
INSTALL_OWNER="${QUOTE_GEO_INSTALL_OWNER:-${SUDO_USER:-$(id -un)}}"
INSTALL_OWNER_HOME="${QUOTE_GEO_OWNER_HOME:-}"
CADDY_FILE="${QUOTE_GEO_CADDY_FILE:-${CADDY_FILE:-/etc/caddy/conf.d/webhooks.caddy}}"
CADDY_ROUTES_DIR="${QUOTE_GEO_CADDY_ROUTES_DIR:-${CADDY_ROUTES_DIR:-/etc/caddy/conf.d/webhooks.routes}}"
CADDY_ROUTE_FILE="${QUOTE_GEO_CADDY_ROUTE_FILE:-${CADDY_ROUTE_FILE:-${CADDY_ROUTES_DIR}/${SERVICE_NAME}.caddy}}"
LEGACY_ENV_FILE="${QUOTE_GEO_LEGACY_ENV_FILE:-/etc/update-quote-geolocation/zoho_quote_geocode.env}"
WEBHOOK_SECRET_SOURCE=""
GENERATED_WEBHOOK_SECRET=""

log() {
  printf '[%s] %s\n' "${APP_NAME}" "$*"
}

fail() {
  printf '[%s] ERROR: %s\n' "${APP_NAME}" "$*" >&2
  exit 1
}

generate_secret() {
  od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
}

initialize_context() {
  if [[ -z "$INSTALL_OWNER_HOME" ]]; then
    if command -v getent >/dev/null 2>&1; then
      INSTALL_OWNER_HOME="$(getent passwd "$INSTALL_OWNER" | cut -d: -f6 || true)"
    fi
    if [[ -z "$INSTALL_OWNER_HOME" ]]; then
      if [[ "$INSTALL_OWNER" == "root" ]]; then
        INSTALL_OWNER_HOME="/root"
      else
        INSTALL_OWNER_HOME="/home/${INSTALL_OWNER}"
      fi
    fi
  fi
}

read_env_value_from_file() {
  local file_path="$1"
  local key_name="$2"

  if [[ ! -f "$file_path" ]]; then
    return 1
  fi

  python3 - "$file_path" "$key_name" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
for raw_line in path.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    current_key, value = line.split("=", 1)
    if current_key.strip() == key:
        print(value.strip())
        raise SystemExit(0)
raise SystemExit(1)
PY
}

prompt() {
  local var_name="$1"
  local message="$2"
  local default_value="${3:-}"
  local current_value="${!var_name:-}"

  if [[ -n "${current_value}" ]]; then
    return
  fi

  if [[ ! -t 0 ]]; then
    printf -v "$var_name" '%s' "$default_value"
    return
  fi

  local answer
  if [[ -n "$default_value" ]]; then
    read -r -p "${message} [${default_value}]: " answer
    printf -v "$var_name" '%s' "${answer:-$default_value}"
  else
    read -r -p "${message}: " answer
    printf -v "$var_name" '%s' "$answer"
  fi
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Run this installer as root. Example: sudo bash <(curl -fsSL https://raw.githubusercontent.com/yboucher97/Update-Quote-Geolocation/main/install.sh)"
  fi
}

ensure_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y git curl ca-certificates openssl python3 python3-venv python3-pip caddy ufw
}

ensure_user_and_dirs() {
  if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --create-home --home-dir "$SERVICE_ROOT" --shell /usr/sbin/nologin "$SERVICE_USER"
  fi

  mkdir -p "$SERVICE_ROOT" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "${DATA_DIR}/reports"
  chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR" "$LOG_DIR"
  chmod 755 "$SERVICE_ROOT" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
}

port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH "( sport = :${port} )" 2>/dev/null | grep -q .
    return
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return
  fi
  return 1
}

select_service_port() {
  local preferred_port="$1"
  local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
  local chosen_port="$preferred_port"

  if [[ -f "$service_file" ]] && grep -Fq -- "--port ${preferred_port}" "$service_file"; then
    PORT="$preferred_port"
    return
  fi

  while port_in_use "$chosen_port"; do
    chosen_port="$((chosen_port + 1))"
  done

  if [[ "$chosen_port" != "$preferred_port" ]]; then
    log "Port ${preferred_port} is already in use. Using ${chosen_port} instead."
  fi

  PORT="$chosen_port"
}

disable_legacy_services() {
  local legacy
  for legacy in update-quote-geolocation update-quote-geolocation-webhook; do
    if systemctl list-unit-files | grep -Fq "${legacy}.service"; then
      log "Stopping legacy service ${legacy}.service"
      systemctl disable --now "${legacy}.service" >/dev/null 2>&1 || true
    fi
  done
}

sync_repo() {
  mkdir -p "$(dirname "$APP_DIR")"
  if [[ -d "${APP_DIR}/.git" ]]; then
    log "Updating existing repo in ${APP_DIR}"
    git config --global --add safe.directory "${APP_DIR}"
    git -C "$APP_DIR" fetch --prune origin
    git -C "$APP_DIR" checkout "$REPO_REF"
    git -C "$APP_DIR" reset --hard "origin/${REPO_REF}"
  else
    log "Cloning repo into ${APP_DIR}"
    rm -rf "$APP_DIR"
    git clone --branch "$REPO_REF" "$REPO_URL" "$APP_DIR"
  fi
}

migrate_legacy_env_file() {
  if [[ ! -f "$ENV_FILE" && -f "$LEGACY_ENV_FILE" ]]; then
    log "Migrating legacy env file from ${LEGACY_ENV_FILE}"
    cp "$LEGACY_ENV_FILE" "$ENV_FILE"
  fi
}

prepare_webhook_secret() {
  local current_secret=""

  if [[ -n "$WEBHOOK_SECRET" ]]; then
    WEBHOOK_SECRET_SOURCE="provided"
    return
  fi

  if current_secret="$(read_env_value_from_file "$ENV_FILE" "ZOHO_QUOTE_WEBHOOK_SECRET" 2>/dev/null)"; then
    WEBHOOK_SECRET="$current_secret"
    WEBHOOK_SECRET_SOURCE="existing"
    return
  fi

  if current_secret="$(read_env_value_from_file "$LEGACY_ENV_FILE" "ZOHO_QUOTE_WEBHOOK_SECRET" 2>/dev/null)"; then
    WEBHOOK_SECRET="$current_secret"
    WEBHOOK_SECRET_SOURCE="existing"
    return
  fi

  WEBHOOK_SECRET="$(generate_secret)"
  GENERATED_WEBHOOK_SECRET="$WEBHOOK_SECRET"
  WEBHOOK_SECRET_SOURCE="generated"
}

seed_env_file() {
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "${APP_DIR}/zoho_quote_geocode.env.example" "$ENV_FILE"
  fi

  ENV_FILE="$ENV_FILE" \
  REPORT_ROOT="${DATA_DIR}/reports" \
  PORT="$PORT" \
  WEBHOOK_SECRET="$WEBHOOK_SECRET" \
  python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["ENV_FILE"])
existing_lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
values = {}
for line in existing_lines:
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in stripped:
        continue
    key, value = stripped.split("=", 1)
    values[key] = value

defaults = {
    "ZOHO_QUOTE_FAILURE_REPORT_PATH": f"{os.environ['REPORT_ROOT']}/quote-geolocation-failures.xlsx",
    "ZOHO_GOOGLE_ERROR_REPORT_PATH": f"{os.environ['REPORT_ROOT']}/quote-google-geocode-errors.xlsx",
    "ZOHO_REGION_FAILURE_REPORT_PATH": f"{os.environ['REPORT_ROOT']}/quote-region-failures.xlsx",
    "ZOHO_QUOTE_RUN_REPORT_PATH": f"{os.environ['REPORT_ROOT']}/quote-run-report.xlsx",
    "ZOHO_QUOTE_RUN_ONE_REPORT_PATH": f"{os.environ['REPORT_ROOT']}/quote-run-one-report.xlsx",
    "ZOHO_QUOTE_WEBHOOK_HOST": "127.0.0.1",
    "ZOHO_QUOTE_WEBHOOK_PORT": os.environ["PORT"],
    "ZOHO_QUOTE_WEBHOOK_SECRET": os.environ["WEBHOOK_SECRET"],
}
for key, value in defaults.items():
    values.setdefault(key, value)

ordered_keys = [
    "ZOHO_QUOTE_FAILURE_REPORT_PATH",
    "ZOHO_GOOGLE_ERROR_REPORT_PATH",
    "ZOHO_REGION_FAILURE_REPORT_PATH",
    "ZOHO_QUOTE_RUN_REPORT_PATH",
    "ZOHO_QUOTE_RUN_ONE_REPORT_PATH",
    "ZOHO_QUOTE_WEBHOOK_HOST",
    "ZOHO_QUOTE_WEBHOOK_PORT",
    "ZOHO_QUOTE_WEBHOOK_SECRET",
]
present = {line.split("=", 1)[0].strip() for line in existing_lines if "=" in line and not line.lstrip().startswith("#")}
lines = list(existing_lines)
for key in ordered_keys:
    if key not in present and key in values:
        lines.append(f"{key}={values[key]}")

path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY

  chmod 600 "$ENV_FILE"
  chown root:root "$ENV_FILE"
}

install_python_deps() {
  python3 -m venv "${VENV_DIR}"
  "${VENV_DIR}/bin/pip" install --upgrade pip
  "${VENV_DIR}/bin/pip" install -r "${APP_DIR}/requirements.txt"
  chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR" "$VENV_DIR"
}

write_install_metadata() {
  {
    printf 'SERVICE_NAME=%q\n' "$SERVICE_NAME"
    printf 'SERVICE_USER=%q\n' "$SERVICE_USER"
    printf 'INSTALL_OWNER=%q\n' "$INSTALL_OWNER"
    printf 'SERVICE_ROOT=%q\n' "$SERVICE_ROOT"
    printf 'APP_DIR=%q\n' "$APP_DIR"
    printf 'VENV_DIR=%q\n' "$VENV_DIR"
    printf 'CONFIG_DIR=%q\n' "$CONFIG_DIR"
    printf 'DATA_DIR=%q\n' "$DATA_DIR"
    printf 'LOG_DIR=%q\n' "$LOG_DIR"
    printf 'ENV_FILE=%q\n' "$ENV_FILE"
    printf 'META_FILE=%q\n' "$META_FILE"
    printf 'PATHS_FILE=%q\n' "$PATHS_FILE"
    printf 'CADDY_FILE=%q\n' "$CADDY_FILE"
    printf 'CADDY_ROUTES_DIR=%q\n' "$CADDY_ROUTES_DIR"
    printf 'CADDY_ROUTE_FILE=%q\n' "$CADDY_ROUTE_FILE"
    printf 'HOST=%q\n' "$HOST"
    printf 'PORT=%q\n' "$PORT"
    printf 'REPO_REF=%q\n' "$REPO_REF"
  } >"$META_FILE"
  chmod 644 "$META_FILE"
}

write_paths_file() {
  {
    printf '%s  # service root\n' "$SERVICE_ROOT"
    printf '%s  # application code\n' "$APP_DIR"
    printf '%s  # Python virtualenv\n' "$VENV_DIR"
    printf '%s  # runtime config directory\n' "$CONFIG_DIR"
    printf '%s  # secrets environment file\n' "$ENV_FILE"
    printf '%s  # systemd service file\n' "/etc/systemd/system/${SERVICE_NAME}.service"
    printf '%s  # service data root\n' "$DATA_DIR"
    printf '%s  # reports and exported run artifacts\n' "${DATA_DIR}/reports"
    printf '%s  # application logs\n' "$LOG_DIR"
    printf '%s  # rotating application log file\n' "${LOG_DIR}/quote-geolocation.log"
    printf '%s  # local update script\n' "${APP_DIR}/update.sh"
    if [[ -n "$HOST" ]]; then
      printf '%s  # shared Caddy site config\n' "$CADDY_FILE"
      printf '%s  # per-app Caddy route snippets\n' "$CADDY_ROUTES_DIR"
      printf '%s  # this service Caddy route snippet\n' "$CADDY_ROUTE_FILE"
    fi
  } >"$PATHS_FILE"

  if id -u "$INSTALL_OWNER" >/dev/null 2>&1; then
    chown "$INSTALL_OWNER:$INSTALL_OWNER" "$PATHS_FILE" || true
  fi
}

write_service_file() {
  local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
  cat >"$service_file" <<EOF
[Unit]
Description=Quote Geolocation Webhook Service
After=network.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${APP_DIR}
EnvironmentFile=${ENV_FILE}
Environment=ZOHO_QUOTE_GEOLOCATION_ENV_FILE=${ENV_FILE}
Environment=ZOHO_QUOTE_LOG_DIR=${LOG_DIR}
Environment=PATH=${VENV_DIR}/bin
ExecStart=${VENV_DIR}/bin/uvicorn quote_geolocation_webhook:app --app-dir ${APP_DIR} --host 127.0.0.1 --port ${PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
}

configure_caddy() {
  if [[ -z "$HOST" ]]; then
    log "No hostname provided. Skipping Caddy configuration."
    return
  fi

  mkdir -p /etc/caddy/conf.d "$CADDY_ROUTES_DIR"
  if [[ ! -f /etc/caddy/Caddyfile ]] || grep -Fq '/usr/share/caddy' /etc/caddy/Caddyfile; then
    cat >/etc/caddy/Caddyfile <<'EOF'
import /etc/caddy/conf.d/*.caddy
EOF
  elif ! grep -Fq 'import /etc/caddy/conf.d/*.caddy' /etc/caddy/Caddyfile; then
    printf '\nimport /etc/caddy/conf.d/*.caddy\n' >> /etc/caddy/Caddyfile
  fi

  if [[ -f "$CADDY_FILE" ]]; then
    local existing_host
    existing_host="$(sed -n '1s/[[:space:]]*{[[:space:]]*$//p' "$CADDY_FILE" | head -n1)"
    if [[ -n "$existing_host" && "$existing_host" != "$HOST" ]]; then
      fail "Caddy host file ${CADDY_FILE} already targets '${existing_host}'. Reuse that hostname or update the file manually."
    fi
  fi

  cat >"$CADDY_FILE" <<EOF
${HOST} {
    import ${CADDY_ROUTES_DIR}/*.caddy
}
EOF

  cat >"$CADDY_ROUTE_FILE" <<EOF
handle_path /quote-geolocation/* {
    reverse_proxy 127.0.0.1:${PORT}
}

handle /health/quote-geolocation* {
    reverse_proxy 127.0.0.1:${PORT}
}

handle /webhooks/quote-geolocation* {
    reverse_proxy 127.0.0.1:${PORT}
}

handle /webhooks/zoho/quote-geolocation* {
    reverse_proxy 127.0.0.1:${PORT}
}
EOF

  caddy fmt --overwrite /etc/caddy/Caddyfile >/dev/null
  caddy fmt --overwrite "$CADDY_FILE" >/dev/null
  caddy fmt --overwrite "$CADDY_ROUTE_FILE" >/dev/null
  caddy validate --config /etc/caddy/Caddyfile
  systemctl enable --now caddy
  systemctl reload caddy
}

configure_ufw() {
  if [[ "$UFW_MODE" == "false" ]]; then
    log "Skipping UFW configuration."
    return
  fi

  ufw allow OpenSSH >/dev/null 2>&1 || true
  if [[ -n "$HOST" ]]; then
    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
  fi
  ufw --force enable >/dev/null 2>&1 || true
}

report_follow_up() {
  log "Edit ${ENV_FILE} with your Zoho OAuth settings, Google API key, field names, and shapefile paths."
  case "$WEBHOOK_SECRET_SOURCE" in
    generated)
      log "Generated webhook secret. Copy this value now:"
      printf '%s\n' "$GENERATED_WEBHOOK_SECRET"
      ;;
    existing)
      log "Existing webhook secret preserved in ${ENV_FILE}"
      ;;
    provided)
      log "Webhook secret stored from installer input in ${ENV_FILE}"
      ;;
  esac
  log "Then restart the service if you changed credentials:"
  log "  sudo systemctl restart ${SERVICE_NAME}"
}

main() {
  require_root
  initialize_context
  prompt HOST "Public hostname for shared Caddy/HTTPS" "$HOST"

  if [[ -z "${HOST// }" ]]; then
    fail "A public hostname is required. Set QUOTE_GEO_HOST or enter one at the prompt."
  fi

  ensure_packages
  ensure_user_and_dirs
  disable_legacy_services
  select_service_port "$PORT"
  sync_repo
  migrate_legacy_env_file
  prepare_webhook_secret
  seed_env_file
  install_python_deps
  write_install_metadata
  write_service_file
  configure_caddy
  configure_ufw
  write_paths_file

  log "Install complete."
  log "Service root: ${SERVICE_ROOT}"
  log "Code directory: ${APP_DIR}"
  log "Virtualenv: ${VENV_DIR}"
  log "Config env: ${ENV_FILE}"
  log "Logs: ${LOG_DIR}"
  log "Service: ${SERVICE_NAME}"
  log "Path inventory: ${PATHS_FILE}"
  log "Public quote health check: https://${HOST}/quote-geolocation/health"
  log "Public quote webhook: https://${HOST}/quote-geolocation/webhooks/zoho/quote-geolocation"
  report_follow_up
}

main "$@"
