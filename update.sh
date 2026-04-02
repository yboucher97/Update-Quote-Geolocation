#!/usr/bin/env bash
set -euo pipefail

DEFAULT_SERVICE_ROOT="${QUOTE_GEO_SERVICE_ROOT:-/opt/services/quote-geolocation}"
DEFAULT_CONFIG_DIR="${QUOTE_GEO_CONFIG_DIR:-${DEFAULT_SERVICE_ROOT}/config}"
META_FILE="${QUOTE_GEO_META_FILE:-${DEFAULT_CONFIG_DIR}/install-meta.env}"

if [[ ! -f "$META_FILE" ]]; then
  echo "Install metadata not found: ${META_FILE}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$META_FILE"
if [[ -f "${ENV_FILE:-}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi
set +a

APP_DIR="${QUOTE_GEO_APP_DIR:-${APP_DIR:-${DEFAULT_SERVICE_ROOT}/app}}"
REPO_REF="${QUOTE_GEO_REPO_REF:-${REPO_REF:-main}}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo ${APP_DIR}/update.sh" >&2
  exit 1
fi

if [[ ! -d "${APP_DIR}/.git" ]]; then
  echo "Install directory is not a git checkout: ${APP_DIR}" >&2
  exit 1
fi

git config --global --add safe.directory "${APP_DIR}"
git -C "${APP_DIR}" fetch --prune origin
git -C "${APP_DIR}" checkout "${REPO_REF}"
git -C "${APP_DIR}" reset --hard "origin/${REPO_REF}"

exec bash "${APP_DIR}/install.sh"
