#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_NAME="update-quote-geolocation"
PACKAGE_VERSION="${1:?usage: build-deb.sh <version>}"
BUILD_ROOT="${ROOT_DIR}/dist/deb"
STAGE_DIR="${BUILD_ROOT}/stage"
PACKAGE_ROOT="${STAGE_DIR}/${PACKAGE_NAME}"
APP_ROOT="${PACKAGE_ROOT}/usr/lib/${PACKAGE_NAME}"
VENDOR_ROOT="${APP_ROOT}/vendor"
WRAPPER_PATH="${PACKAGE_ROOT}/usr/bin/${PACKAGE_NAME}"
WEBHOOK_WRAPPER_PATH="${PACKAGE_ROOT}/usr/bin/${PACKAGE_NAME}-webhook"
CONTROL_DIR="${PACKAGE_ROOT}/DEBIAN"
DEB_PATH="${BUILD_ROOT}/${PACKAGE_NAME}_${PACKAGE_VERSION}_all.deb"
MAINTAINER_NAME="${MAINTAINER_NAME:-yboucher97}"
MAINTAINER_EMAIL="${MAINTAINER_EMAIL:-yboucher97@users.noreply.github.com}"

rm -rf "${STAGE_DIR}" "${DEB_PATH}"
mkdir -p "${APP_ROOT}" "${VENDOR_ROOT}" "${CONTROL_DIR}" "${PACKAGE_ROOT}/usr/bin" "${PACKAGE_ROOT}/etc/${PACKAGE_NAME}"

python3 -m pip install --upgrade pip
python3 -m pip install --no-compile --target "${VENDOR_ROOT}" -r "${ROOT_DIR}/requirements.txt"

install -m 755 "${ROOT_DIR}/zoho_quote_geocode.py" "${APP_ROOT}/zoho_quote_geocode.py"
install -m 755 "${ROOT_DIR}/quote_geolocation_webhook.py" "${APP_ROOT}/quote_geolocation_webhook.py"
install -m 644 "${ROOT_DIR}/zoho_quote_geocode.env.example" "${PACKAGE_ROOT}/etc/${PACKAGE_NAME}/zoho_quote_geocode.env.example"
install -m 644 "${ROOT_DIR}/README.md" "${APP_ROOT}/README.md"

cat > "${WRAPPER_PATH}" <<EOF
#!/bin/sh
set -eu

APP_DIR="/usr/lib/${PACKAGE_NAME}"
SYSTEM_ENV_FILE="/etc/${PACKAGE_NAME}/zoho_quote_geocode.env"
USER_ENV_FILE="\${XDG_CONFIG_HOME:-\$HOME/.config}/${PACKAGE_NAME}/zoho_quote_geocode.env"

load_env_file() {
  if [ -f "\$1" ]; then
    set -a
    # shellcheck disable=SC1090
    . "\$1"
    set +a
  fi
}

load_env_file "\${SYSTEM_ENV_FILE}"
load_env_file "\${USER_ENV_FILE}"

if [ -n "\${ZOHO_QUOTE_GEOLOCATION_ENV_FILE:-}" ] && [ -f "\${ZOHO_QUOTE_GEOLOCATION_ENV_FILE}" ]; then
  load_env_file "\${ZOHO_QUOTE_GEOLOCATION_ENV_FILE}"
fi

export PYTHONPATH="\${APP_DIR}/vendor\${PYTHONPATH:+:\${PYTHONPATH}}"
export UPDATE_QUOTE_GEOLOCATION_VERSION="${PACKAGE_VERSION}"

exec python3 "\${APP_DIR}/zoho_quote_geocode.py" "\$@"
EOF
chmod 755 "${WRAPPER_PATH}"

cat > "${WEBHOOK_WRAPPER_PATH}" <<EOF
#!/bin/sh
set -eu

APP_DIR="/usr/lib/${PACKAGE_NAME}"
SYSTEM_ENV_FILE="/etc/${PACKAGE_NAME}/zoho_quote_geocode.env"
USER_ENV_FILE="\${XDG_CONFIG_HOME:-\$HOME/.config}/${PACKAGE_NAME}/zoho_quote_geocode.env"

load_env_file() {
  if [ -f "\$1" ]; then
    set -a
    # shellcheck disable=SC1090
    . "\$1"
    set +a
  fi
}

load_env_file "\${SYSTEM_ENV_FILE}"
load_env_file "\${USER_ENV_FILE}"

if [ -n "\${ZOHO_QUOTE_GEOLOCATION_ENV_FILE:-}" ] && [ -f "\${ZOHO_QUOTE_GEOLOCATION_ENV_FILE}" ]; then
  load_env_file "\${ZOHO_QUOTE_GEOLOCATION_ENV_FILE}"
fi

export PYTHONPATH="\${APP_DIR}/vendor:\${APP_DIR}\${PYTHONPATH:+:\${PYTHONPATH}}"
export UPDATE_QUOTE_GEOLOCATION_VERSION="${PACKAGE_VERSION}"

HOST="\${ZOHO_QUOTE_WEBHOOK_HOST:-127.0.0.1}"
PORT="\${ZOHO_QUOTE_WEBHOOK_PORT:-8050}"

exec python3 -m uvicorn quote_geolocation_webhook:app --app-dir "\${APP_DIR}" --host "\${HOST}" --port "\${PORT}" "\$@"
EOF
chmod 755 "${WEBHOOK_WRAPPER_PATH}"

cat > "${CONTROL_DIR}/control" <<EOF
Package: ${PACKAGE_NAME}
Version: ${PACKAGE_VERSION}
Section: utils
Priority: optional
Architecture: all
Maintainer: ${MAINTAINER_NAME} <${MAINTAINER_EMAIL}>
Depends: python3
Description: Zoho CRM quote geolocation updater
 Fetches quote shipping addresses from Zoho CRM, geocodes them with the
 Google Geocoding API, and updates latitude/longitude fields in Zoho CRM.
EOF

cat > "${CONTROL_DIR}/postinst" <<EOF
#!/bin/sh
set -eu

CONFIG_DIR="/etc/${PACKAGE_NAME}"
EXAMPLE_FILE="\${CONFIG_DIR}/zoho_quote_geocode.env.example"
TARGET_FILE="\${CONFIG_DIR}/zoho_quote_geocode.env"

mkdir -p "\${CONFIG_DIR}"

if [ ! -f "\${TARGET_FILE}" ] && [ -f "\${EXAMPLE_FILE}" ]; then
  cp "\${EXAMPLE_FILE}" "\${TARGET_FILE}"
  chmod 600 "\${TARGET_FILE}"
fi
EOF
chmod 755 "${CONTROL_DIR}/postinst"

dpkg-deb --build --root-owner-group "${PACKAGE_ROOT}" "${DEB_PATH}"

echo "Built ${DEB_PATH}"
