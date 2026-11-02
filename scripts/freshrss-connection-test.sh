#!/usr/bin/env bash
# Test FreshRSS connection with form values (does not overwrite saved secrets).
# Usage: same flags as freshrss-secrets-write.sh
#   freshrss-connection-test.sh --scheme https --host h --user u [--password p]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITE="$SCRIPT_DIR/freshrss-secrets-write.sh"
API="$SCRIPT_DIR/freshrss-api.sh"
TMP="$(mktemp "${TMPDIR:-/tmp}/freshrss-test.XXXXXX.env")"
trap 'rm -f "$TMP"' EXIT

# If password omitted, write script merges from real secrets when writing to real path.
# For test we write to TMP: still merge password from real file if not provided.
export FRESHRSS_SECRETS="$TMP"

# Seed TMP from real secrets so omit-password keeps existing API key
REAL="${XDG_CONFIG_HOME:-$HOME/.config}/freshrss-quickshell/freshrss.env"
if [[ -f "$REAL" ]]; then
  cp "$REAL" "$TMP"
  chmod 600 "$TMP"
else
  : > "$TMP"
  chmod 600 "$TMP"
fi

# Apply form flags into TMP (write script honors FRESHRSS_SECRETS)
if ! out="$("$WRITE" "$@" 2>&1)"; then
  python3 - <<PY
import json
print(json.dumps({"ok": False, "error": """${out//$'\n'/ }"""[:200]}, ensure_ascii=False))
PY
  exit 1
fi

# Run status against temp secrets
export FRESHRSS_SECRETS="$TMP"
if ! status_json="$("$API" status 2>&1)"; then
  # api may exit non-zero; still try parse
  :
fi

python3 - <<'PY'
import json, os, sys
raw = os.environ.get("FR_STATUS_JSON", "")
# passed via env below
PY

# Pass status through Python for a clear message
export FR_STATUS_JSON="$status_json"
python3 - <<'PY'
import json, os, sys
raw = os.environ.get("FR_STATUS_JSON", "").strip()
try:
    j = json.loads(raw) if raw.startswith("{") else {}
except Exception:
    j = {}
if j.get("ok") and not j.get("fever_auth_failed"):
    mode = j.get("mode") or "?"
    unread = j.get("unread")
    auth = j.get("auth")
    writable = j.get("writable")
    parts = [f"OK · {mode}"]
    if auth is not None:
        parts.append("auth" if auth else "no-auth")
    if writable is not None:
        parts.append("r/w" if writable else "read-only")
    if unread is not None:
        parts.append(f"{unread} unread")
    print(json.dumps({"ok": True, "message": " · ".join(parts), "mode": mode, "unread": unread}, ensure_ascii=False))
    sys.exit(0)
err = j.get("error") or (raw[:160] if raw else "connection failed")
print(json.dumps({"ok": False, "error": err, "message": f"Failed · {err}"}, ensure_ascii=False))
sys.exit(1)
PY
