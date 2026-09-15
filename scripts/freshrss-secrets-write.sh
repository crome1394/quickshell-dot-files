#!/usr/bin/env bash
# Write FreshRSS secrets outside the git tree.
#   freshrss-secrets-write.sh --scheme https --host example.com --user name [--password 'pw']
set -euo pipefail

OUT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/freshrss-quickshell"
OUT_FILE="${FRESHRSS_SECRETS:-$OUT_DIR/freshrss.env}"
SCHEME="https"
HOST=""
BASE_URL=""
USER=""
PASSWORD=""
PASSWORD_SET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scheme) SCHEME="${2:-https}"; shift 2 ;;
    --host) HOST="${2:-}"; shift 2 ;;
    --base-url) BASE_URL="${2:-}"; shift 2 ;;
    --user) USER="${2:-}"; shift 2 ;;
    --password) PASSWORD="${2:-}"; PASSWORD_SET=true; shift 2 ;;
    --clear-password) PASSWORD=""; PASSWORD_SET=true; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

EXIST_USER=""
EXIST_PW=""
EXIST_BASE=""
if [[ -f "$OUT_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$OUT_FILE"
  set +a
  EXIST_USER="${FRESHRSS_USER:-}"
  EXIST_PW="${FRESHRSS_API_PASSWORD:-}"
  EXIST_BASE="${FRESHRSS_BASE_URL:-}"
fi

if [[ -z "$BASE_URL" ]]; then
  if [[ -z "$HOST" ]]; then
    if [[ -n "$EXIST_BASE" ]]; then
      BASE_URL="$EXIST_BASE"
    else
      echo "error: need --host or --base-url" >&2
      exit 1
    fi
  else
    SCHEME=$(printf '%s' "$SCHEME" | tr '[:upper:]' '[:lower:]')
    [[ "$SCHEME" == "http" ]] || SCHEME="https"
    HOST="${HOST#https://}"
    HOST="${HOST#http://}"
    HOST="${HOST%/}"
    BASE_URL="${SCHEME}://${HOST}"
  fi
fi
BASE_URL="${BASE_URL%/}"

[[ -n "$USER" ]] || USER="${EXIST_USER:-admin}"
if [[ "$PASSWORD_SET" != true ]]; then
  PASSWORD="$EXIST_PW"
fi

mkdir -p "$(dirname "$OUT_FILE")"
umask 077
# Escape nothing special — values are written as-is; avoid newlines
BASE_URL="${BASE_URL//$'\n'/}"
USER="${USER//$'\n'/}"
PASSWORD="${PASSWORD//$'\n'/}"
# Quote so $, !, and spaces survive `source` in the API script.
q_base=$(printf '%q' "$BASE_URL")
q_user=$(printf '%q' "$USER")
q_pass=$(printf '%q' "$PASSWORD")
cat > "$OUT_FILE" <<ENV
# FreshRSS client secrets (outside quickshell git tree — never commit)
# API password = Profile → API password, not web form password.
FRESHRSS_BASE_URL=${q_base}
FRESHRSS_USER=${q_user}
FRESHRSS_API_PASSWORD=${q_pass}
ENV
chmod 600 "$OUT_FILE"

HAS_PW="false"
[[ -n "${PASSWORD// }" ]] && HAS_PW="true"
export FR_PATH="$OUT_FILE" FR_BASE="$BASE_URL" FR_USER="$USER" FR_HAS_PW="$HAS_PW"
python3 - <<'PY'
import json, os
print(json.dumps({
  "ok": True,
  "path": os.environ["FR_PATH"],
  "baseUrl": os.environ["FR_BASE"],
  "user": os.environ["FR_USER"],
  "hasPassword": os.environ["FR_HAS_PW"] == "true",
}, ensure_ascii=False))
PY
