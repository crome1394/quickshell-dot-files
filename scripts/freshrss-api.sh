#!/usr/bin/env bash
# FreshRSS client for Quickshell (Fever API when configured, else public RSS).
#
# Usage:
#   freshrss-api.sh status
#   freshrss-api.sh items [limit]
#   freshrss-api.sh item <id>
#   freshrss-api.sh mark-read <id> | mark-unread <id> | star <id> | unstar <id>
#   freshrss-api.sh open-browser <url>
#   freshrss-api.sh play-mpv <url>
#
# Secrets: ~/.config/freshrss-quickshell/freshrss.env (outside git)
#   FRESHRSS_BASE_URL=http://10.74.10.8
#   FRESHRSS_USER=admin
#   FRESHRSS_API_PASSWORD=...   # optional; Profile → API password
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Secrets live outside the git tree (never commit passwords):
#   ~/.config/freshrss-quickshell/freshrss.env
# Override with FRESHRSS_SECRETS=/path/to/file
_DEFAULT_SECRETS="${XDG_CONFIG_HOME:-$HOME/.config}/freshrss-quickshell/freshrss.env"
_LEGACY_SECRETS="${QS_ROOT}/secrets/freshrss.env"
if [[ -n "${FRESHRSS_SECRETS:-}" ]]; then
    SECRETS="$FRESHRSS_SECRETS"
elif [[ -f "$_DEFAULT_SECRETS" ]]; then
    SECRETS="$_DEFAULT_SECRETS"
else
    SECRETS="$_LEGACY_SECRETS"
fi

json_err() {
    local msg="$1"
    local code="${2:-1}"
    printf '{"ok":false,"error":%s}\n' "$(printf '%s' "$msg" | jq -Rs .)"
    exit "$code"
}

json_ok() {
    # stdin: raw JSON object fields without outer braces, OR full object via --argjson
    # Prefer: json_ok_obj '{"a":1}'
    :
}

json_ok_obj() {
    local obj="$1"
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$obj" | jq -c '. + {ok:true}'
    else
        # minimal fallback
        printf '%s\n' "$obj" | sed 's/^{/{"ok":true,/'
    fi
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || json_err "missing command: $1"
}

load_secrets() {
    if [[ ! -f "$SECRETS" ]]; then
        # Defaults for LAN FreshRSS without a secrets file
        FRESHRSS_BASE_URL="${FRESHRSS_BASE_URL:-http://10.74.10.8}"
        FRESHRSS_USER="${FRESHRSS_USER:-admin}"
        FRESHRSS_API_PASSWORD="${FRESHRSS_API_PASSWORD:-}"
        return 0
    fi
    # shellcheck disable=SC1090
    set -a
    # shellcheck source=/dev/null
    source "$SECRETS"
    set +a
    FRESHRSS_BASE_URL="${FRESHRSS_BASE_URL:-http://10.74.10.8}"
    FRESHRSS_USER="${FRESHRSS_USER:-admin}"
    FRESHRSS_API_PASSWORD="${FRESHRSS_API_PASSWORD:-}"
    # strip trailing slash
    FRESHRSS_BASE_URL="${FRESHRSS_BASE_URL%/}"
}

api_key() {
    # Fever: md5(username:apiPassword)
    printf '%s' "${FRESHRSS_USER}:${FRESHRSS_API_PASSWORD}" | md5sum | awk '{print $1}'
}

fever_mode() {
    [[ -n "${FRESHRSS_API_PASSWORD// }" ]]
}

fever_post() {
    # fever_post "api&items&max_id=0"  [extra form fields as name=value ...]
    local query="$1"
    shift || true
    local key
    key="$(api_key)"
    local url="${FRESHRSS_BASE_URL}/api/fever.php?${query}"
    local args=(-sS -m 25 -F "api_key=${key}")
    local kv
    for kv in "$@"; do
        args+=(-F "$kv")
    done
    curl "${args[@]}" "$url" || json_err "fever request failed: $query"
}

rss_url() {
    printf '%s/i/?a=rss' "$FRESHRSS_BASE_URL"
}

# ── RSS parser (anonymous / no API password) ──────────────────────────────────
parse_rss_items() {
    local limit="${1:-50}"
    local max_days="${2:-0}"
    need_cmd python3
    local xml
    xml="$(curl -sS -m 25 "$(rss_url)")" || json_err "failed to fetch public RSS"
    FRESHRSS_BASE_URL="$FRESHRSS_BASE_URL" LIMIT="$limit" MAX_DAYS="$max_days" python3 - "$xml" <<'PY'
import json, os, re, sys, hashlib, time
from xml.etree import ElementTree as ET
from email.utils import parsedate_to_datetime

xml = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
limit = int(os.environ.get("LIMIT", "50"))
max_days = max(0, int(os.environ.get("MAX_DAYS", "0") or 0))
cutoff_ts = (int(time.time()) - max_days * 86400) if max_days > 0 else 0
base = os.environ.get("FRESHRSS_BASE_URL", "")

try:
    root = ET.fromstring(xml)
except ET.ParseError as e:
    print(json.dumps({"ok": False, "error": f"RSS parse error: {e}"}))
    sys.exit(1)

# namespaces
NS = {
    "media": "http://search.yahoo.com/mrss/",
    "dc": "http://purl.org/dc/elements/1.1/",
    "content": "http://purl.org/rss/1.0/modules/content/",
    "atom": "http://www.w3.org/2005/Atom",
}

channel = root.find("channel")
if channel is None:
    print(json.dumps({"ok": False, "error": "RSS channel missing"}))
    sys.exit(1)

def text(el, path, default=""):
    if el is None:
        return default
    n = el.find(path)
    if n is not None and n.text:
        return n.text
    # try with namespaces
    for pfx, uri in NS.items():
        n = el.find(path.replace("dc:", f"{{{uri}}}") if path.startswith("dc:") else path)
    n = el.find(path)
    return (n.text or default) if n is not None else default

def findtext_any(el, names):
    for name in names:
        # plain
        n = el.find(name)
        if n is not None and (n.text or "").strip():
            return n.text.strip()
        # namespaced
        if "}" not in name and ":" not in name:
            for uri in NS.values():
                n = el.find(f"{{{uri}}}{name}")
                if n is not None and (n.text or "").strip():
                    return n.text.strip()
    return ""

VIDEO_RE = re.compile(
    r"(youtube\.com|youtu\.be|vimeo\.com|\.m4v\b|\.mp4\b|\.webm\b|\.mkv\b|twitch\.tv)",
    re.I,
)
VIDEO_SRC_RE = re.compile(r"<(?:video|source)[^>]+src=[\"']([^\"']+)[\"']", re.I)
HREF_RE = re.compile(r"href=[\"'](https?://[^\"']+)[\"']", re.I)

def is_video_url(u: str) -> bool:
    return bool(u and VIDEO_RE.search(u))

def extract_media(desc: str, link: str, item):
    candidates = []
    # media:content
    for mc in item.findall("media:content", NS) + item.findall("{http://search.yahoo.com/mrss/}content"):
        u = mc.get("url")
        if u:
            candidates.append(u)
    # enclosure
    enc = item.find("enclosure")
    if enc is not None and enc.get("url"):
        candidates.append(enc.get("url"))
    # html video src
    for u in VIDEO_SRC_RE.findall(desc or ""):
        candidates.append(u)
    # link itself
    if link:
        candidates.append(link)
    # first http links in desc that look like video
    for u in HREF_RE.findall(desc or ""):
        candidates.append(u)

    media_url = ""
    for u in candidates:
        if is_video_url(u):
            media_url = u
            break
    if not media_url and candidates:
        # prefer direct media paths even if host regex missed
        for u in candidates:
            if re.search(r"\.(m4v|mp4|webm|mkv)(\?|$)", u, re.I):
                media_url = u
                break
    return media_url, bool(media_url)

def strip_html(html: str) -> str:
    if not html:
        return ""
    t = re.sub(r"(?is)<script[^>]*>.*?</script>", " ", html)
    t = re.sub(r"(?is)<style[^>]*>.*?</style>", " ", t)
    t = re.sub(r"(?is)<br\s*/?>", "\n", t)
    t = re.sub(r"(?is)</p>", "\n\n", t)
    t = re.sub(r"(?is)<[^>]+>", " ", t)
    t = re.sub(r"&nbsp;", " ", t)
    t = re.sub(r"&amp;", "&", t)
    t = re.sub(r"&lt;", "<", t)
    t = re.sub(r"&gt;", ">", t)
    t = re.sub(r"&quot;", '"', t)
    t = re.sub(r"&#39;", "'", t)
    t = re.sub(r"[ \t]+\n", "\n", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    t = re.sub(r"[ \t]{2,}", " ", t)
    return t.strip()

def to_epoch(pub: str) -> int:
    if not pub:
        return 0
    try:
        return int(parsedate_to_datetime(pub).timestamp())
    except Exception:
        return 0

items_out = []
_take = 5000 if max_days > 0 else max(1, min(limit, 200))
for item in channel.findall("item")[:_take]:
    title = findtext_any(item, ["title"]) or "(no title)"
    link = findtext_any(item, ["link"]) or ""
    guid = findtext_any(item, ["guid"]) or link or title
    author = findtext_any(item, ["author", "dc:creator", "{http://purl.org/dc/elements/1.1/}creator"]) or ""
    # Never use RSS <category> (publisher tags like "U.S. News", "r/cachyos")
    # as a FreshRSS feed name. Public /i/?a=rss is one combined stream and
    # does not include subscription titles — callers should set an API password.
    src = item.find("source")
    src_title = (src.text or "").strip() if src is not None else ""
    feed_title = src_title
    pub = findtext_any(item, ["pubDate"]) or ""
    # body: content:encoded preferred
    html = ""
    ce = item.find("{http://purl.org/rss/1.0/modules/content/}encoded")
    if ce is not None and ce.text:
        html = ce.text
    if not html:
        html = findtext_any(item, ["description"]) or ""
    media_url, is_video = extract_media(html, link, item)
    # stable numeric-ish id for UI (Fever uses ints; RSS uses guid)
    id_str = str(guid)
    # hash for QML model if needed
    id_hash = hashlib.sha1(id_str.encode("utf-8", "replace")).hexdigest()[:16]
    plain = strip_html(html)
    summary = plain[:220] + ("…" if len(plain) > 220 else "")
    cat = feed_title or "Public RSS"
    items_out.append({
        "id": id_str,
        "id_hash": id_hash,
        "feed_id": feed_title,
        "feed_title": cat,
        "group_id": 0,
        "group_title": "Set API password to see your feeds",
        "category": cat,
        "title": title,
        "author": author,
        "url": link,
        "html": html,
        "text": plain,
        "summary": summary,
        "is_read": 0,
        "is_saved": 0,
        "is_video": 1 if is_video else 0,
        "media_url": media_url,
        "created_on_time": to_epoch(pub),
        "pubDate": pub,
    })

# Newest first + day window
items_out.sort(key=lambda x: x.get("created_on_time") or 0, reverse=True)
if cutoff_ts > 0:
    items_out = [x for x in items_out if int(x.get("created_on_time") or 0) >= cutoff_ts]
elif limit:
    items_out = items_out[: max(1, min(limit, 200))]

# unread badge: try HTML title "(N) …"
count = len(items_out)
try:
    import urllib.request
    req = urllib.request.Request(base + "/i/", headers={"User-Agent": "quickshell-freshrss/1.0"})
    with urllib.request.urlopen(req, timeout=8) as r:
        page = r.read(8000).decode("utf-8", "replace")
    m = re.search(r"<title>\((\d+)\)", page)
    if m:
        count = int(m.group(1))
except Exception:
    pass

print(json.dumps({
    "ok": True,
    "mode": "rss",
    "auth": False,
    "writable": False,
    "count": count,
    "total": len(items_out),
    "items": items_out,
}, ensure_ascii=False))
PY
}

cmd_status() {
    need_cmd curl
    need_cmd jq
    if fever_mode; then
        local resp
        resp="$(fever_post "api")" || true
        local auth
        auth="$(printf '%s' "$resp" | jq -r '.auth // 0')"
        if [[ "$auth" == "1" ]]; then
            # Google Reader unread-count: global max + per-feed (matches FreshRSS sidebar).
            FRESHRSS_BASE_URL="$FRESHRSS_BASE_URL" \
            FRESHRSS_USER="$FRESHRSS_USER" \
            FRESHRSS_API_PASSWORD="$FRESHRSS_API_PASSWORD" \
            python3 - <<'PY'
import json, os, urllib.parse, urllib.request, hashlib, time

base = os.environ["FRESHRSS_BASE_URL"].rstrip("/")
user = os.environ.get("FRESHRSS_USER", "admin")
pw = os.environ.get("FRESHRSS_API_PASSWORD", "")
cache = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                     "quickshell", "freshrss-greader.auth")

def http(method, url, data=None, headers=None, timeout=12):
    h = {"User-Agent": "quickshell-freshrss/1.2"}
    if headers:
        h.update(headers)
    body = None
    if data is not None:
        body = urllib.parse.urlencode(data).encode()
        h["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()

def load_auth():
    try:
        with open(cache, "r", encoding="utf-8") as f:
            d = json.load(f)
        if d.get("user") == user and d.get("base") == base and time.time() - float(d.get("ts", 0)) < 25 * 60:
            return d.get("auth") or ""
    except Exception:
        pass
    return ""

def save_auth(tok):
    try:
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        tmp = cache + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"auth": tok, "user": user, "base": base, "ts": time.time()}, f)
        os.chmod(tmp, 0o600)
        os.replace(tmp, cache)
    except Exception:
        pass

def login():
    raw = http("POST", f"{base}/api/greader.php/accounts/ClientLogin",
               {"Email": user, "Passwd": pw}).decode("utf-8", "replace")
    for line in raw.splitlines():
        if line.startswith("Auth="):
            tok = line.split("=", 1)[1].strip()
            save_auth(tok)
            return tok
    return ""

auth = load_auth() or login()
if not auth:
    # Fever fallback: global unread only
    import subprocess, hashlib
    key = hashlib.md5(f"{user}:{pw}".encode()).hexdigest()
    import urllib.request as ur
    # use curl-like via fever endpoint
    try:
        raw = http("POST", f"{base}/api/fever.php?api&unread_item_ids",
                   {"api_key": key}).decode()
        d = json.loads(raw)
        ids = (d.get("unread_item_ids") or "").strip()
        n = len([x for x in ids.split(",") if x]) if ids else 0
    except Exception:
        n = 0
    print(json.dumps({
        "ok": True, "mode": "fever", "auth": True, "writable": True,
        "unread": n, "count": n, "source": "fever",
        "feeds": {}, "titles": {}, "labels": {},
    }, separators=(",", ":")))
    raise SystemExit(0)

auth_h = {"Authorization": f"GoogleLogin auth={auth}"}

def get_json(path):
    return json.loads(http("GET", f"{base}/api/greader.php{path}", headers=auth_h).decode())

try:
    counts = get_json("/reader/api/0/unread-count?output=json")
    subs = get_json("/reader/api/0/subscription/list?output=json")
except Exception:
    auth = login()
    if not auth:
        print(json.dumps({"ok": False, "error": "greader auth failed"}))
        raise SystemExit(1)
    auth_h = {"Authorization": f"GoogleLogin auth={auth}"}
    counts = get_json("/reader/api/0/unread-count?output=json")
    subs = get_json("/reader/api/0/subscription/list?output=json")

uc = counts.get("unreadcounts") or []
by_stream = {u.get("id"): int(u.get("count") or 0) for u in uc if u.get("id")}
feeds = {}
for sid, c in by_stream.items():
    if sid.startswith("feed/"):
        feeds[sid[5:]] = c
labels = {}
for sid, c in by_stream.items():
    if "/label/" in sid:
        lab = urllib.parse.unquote(sid.split("/label/", 1)[-1].replace("+", " "))
        labels[lab] = c
titles = {}
for s in subs.get("subscriptions") or []:
    sid = s.get("id") or ""
    title = s.get("title") or sid
    titles[title] = int(by_stream.get(sid, 0))

n = int(counts.get("max") or by_stream.get("user/-/state/com.google/reading-list") or 0)
print(json.dumps({
    "ok": True, "mode": "fever", "auth": True, "writable": True,
    "unread": n, "count": n, "source": "greader",
    "feeds": feeds, "titles": titles, "labels": labels,
}, separators=(",", ":")))
PY
            return 0
        fi
        # Password is set but Fever returned auth=0 (wrong API password, or
        # the web login password was saved instead of Profile → API password).
        parse_rss_items 1 | jq -c --arg err \
            "Fever rejected the API password (auth=0). Use FreshRSS Profile → API password, not the web login password. Then Options → FreshRSS → Save server." \
            '. + {fever_auth_failed:true, has_password:true, error:$err}'
        return 0
    fi
    # RSS-only status (lightweight) — count from HTML title / feed size
    parse_rss_items 5 | jq -c '{ok,mode,auth,writable,count,unread:(.count//0),total}'
}

# Fetch recent items from EVERY feed via Google Reader API (covers quiet channels).
# Perf: parallel feed streams, cached auth, truncated HTML/text for the list payload.
# Env: FRESHRSS_BASE_URL, FRESHRSS_USER, FRESHRSS_API_PASSWORD
# Args: scope(all|read) limit_total per_feed [max_days]
# max_days > 0: primary history window; paginates per feed and ignores per_feed/item soft caps.
fetch_greader_per_feed() {
    local scope="$1"
    local limit="$2"
    local per_feed="$3"
    local max_days="${4:-0}"
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
    mkdir -p "$cache_dir" 2>/dev/null || true
    FRESHRSS_BASE_URL="$FRESHRSS_BASE_URL" \
    FRESHRSS_USER="$FRESHRSS_USER" \
    FRESHRSS_API_PASSWORD="$FRESHRSS_API_PASSWORD" \
    FRESHRSS_AUTH_CACHE="${cache_dir}/freshrss-greader.auth" \
    python3 - "$scope" "$limit" "$per_feed" "$max_days" <<'PY'
import json, os, re, sys, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

scope = sys.argv[1]
limit = int(sys.argv[2])
per_feed = max(1, min(int(sys.argv[3]), 40))
max_days = max(0, int(sys.argv[4]) if len(sys.argv) > 4 else 0)
base = os.environ.get("FRESHRSS_BASE_URL", "http://10.74.10.8").rstrip("/")
user = os.environ.get("FRESHRSS_USER", "admin")
pw = os.environ.get("FRESHRSS_API_PASSWORD", "")
auth_cache = os.environ.get("FRESHRSS_AUTH_CACHE", "")
# Cap body size sent to QML (list + detail); full article is always a click away.
HTML_MAX = 6000
TEXT_MAX = 1200
SUMMARY_MAX = 220
# Parallel stream fetches (LAN FreshRSS handles this fine).
WORKERS = min(12, max(4, (os.cpu_count() or 4)))
# Day-window mode: primary limit (overrides per-feed / item soft caps).
now_ts = int(time.time())
cutoff_ts = (now_ts - max_days * 86400) if max_days > 0 else 0
PAGE_N = 50 if max_days > 0 else per_feed
MAX_PAGES = 20 if max_days > 0 else 1

def http(method, url, data=None, headers=None, timeout=25):
    h = {"User-Agent": "quickshell-freshrss/1.2"}
    if headers:
        h.update(headers)
    body = None
    if data is not None:
        body = urllib.parse.urlencode(data).encode()
        h["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()

def load_cached_auth():
    if not auth_cache or not os.path.isfile(auth_cache):
        return ""
    try:
        with open(auth_cache, "r", encoding="utf-8") as f:
            data = json.load(f)
        if data.get("user") != user or data.get("base") != base:
            return ""
        if time.time() - float(data.get("ts", 0)) > 25 * 60:
            return ""
        return data.get("auth") or ""
    except Exception:
        return ""

def save_cached_auth(token):
    if not auth_cache or not token:
        return
    try:
        tmp = auth_cache + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"auth": token, "user": user, "base": base, "ts": time.time()}, f)
        os.chmod(tmp, 0o600)
        os.replace(tmp, auth_cache)
    except Exception:
        pass

def client_login():
    raw = http("POST", f"{base}/api/greader.php/accounts/ClientLogin", {
        "Email": user,
        "Passwd": pw,
    }).decode("utf-8", "replace")
    for line in raw.splitlines():
        if line.startswith("Auth="):
            tok = line.split("=", 1)[1].strip()
            save_cached_auth(tok)
            return tok
    return ""

auth = load_cached_auth()
if not auth:
    auth = client_login()
if not auth:
    print(json.dumps({"ok": False, "error": "greader ClientLogin failed"}))
    sys.exit(1)
auth_h = {"Authorization": f"GoogleLogin auth={auth}"}

def get_subs():
    return json.loads(http("GET",
        f"{base}/api/greader.php/reader/api/0/subscription/list?output=json",
        headers=auth_h).decode())

try:
    subs = get_subs()
except Exception:
    # Auth may have expired mid-session — refresh once.
    auth = client_login()
    if not auth:
        print(json.dumps({"ok": False, "error": "greader auth refresh failed"}))
        sys.exit(1)
    auth_h = {"Authorization": f"GoogleLogin auth={auth}"}
    subs = get_subs()

feeds = subs.get("subscriptions") or []

VIDEO_RE = re.compile(
    r"(youtube\.com|youtu\.be|youtube-nocookie\.com|vimeo\.com|"
    r"twitch\.tv|\.m4v\b|\.mp4\b|\.webm\b|\.mkv\b|/shorts/)",
    re.I,
)
VIDEO_SRC_RE = re.compile(r"<(?:video|source|iframe)[^>]+(?:src|data-src)=[\"']([^\"']+)[\"']", re.I)
YT_WATCH_RE = re.compile(
    r"(https?://(?:www\.)?(?:youtube\.com/(?:watch\?v=|shorts/|embed/|live/)|youtu\.be/)[^\s\"'<>&]+)",
    re.I,
)

def strip_html(html: str) -> str:
    if not html:
        return ""
    t = re.sub(r"(?is)<script[^>]*>.*?</script>", " ", html)
    t = re.sub(r"(?is)<style[^>]*>.*?</style>", " ", t)
    t = re.sub(r"(?is)<br\s*/?>", "\n", t)
    t = re.sub(r"(?is)</p>", "\n\n", t)
    t = re.sub(r"(?is)<[^>]+>", " ", t)
    for a, b in (("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", '"'), ("&#39;", "'")):
        t = t.replace(a, b)
    t = re.sub(r"[ \t]{2,}", " ", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    return t.strip()

def greader_id_to_fever(gid: str) -> str:
    if not gid:
        return ""
    hexpart = gid.rsplit("/", 1)[-1]
    try:
        return str(int(hexpart, 16))
    except Exception:
        return gid

def extract_media(html: str, url: str, feed_title: str, site_url: str):
    candidates = []
    for blob in (url, html or ""):
        for m in YT_WATCH_RE.findall(blob or ""):
            candidates.append(m.rstrip(").,;"))
    candidates += VIDEO_SRC_RE.findall(html or "")
    if url:
        candidates.append(url)
    media = ""
    for u in candidates:
        if u and VIDEO_RE.search(u):
            media = u
            break
    if not media:
        for u in candidates:
            if u and re.search(r"\.(m4v|mp4|webm|mkv)(\?|$)", u, re.I):
                media = u
                break
    feed_is_yt = bool(re.search(r"youtube", (feed_title or "") + " " + (site_url or ""), re.I))
    if not media and feed_is_yt and url:
        media = url
    is_vid = 1 if media or (feed_is_yt and url) else 0
    if is_vid and not media:
        media = url or ""
    return media, is_vid

def fetch_feed(sub):
    stream = sub.get("id") or ""
    if not stream:
        return [], None
    ftitle = sub.get("title") or ""
    site = (sub.get("htmlUrl") or sub.get("url") or "")
    # FreshRSS folders are GReader labels on the *subscription*, not item tags.
    group_title = "Other Feeds"
    for c in sub.get("categories") or []:
        cid = str(c.get("id") or "")
        lab = (c.get("label") or "").strip()
        if "/state/" in cid:
            continue
        if lab:
            group_title = lab
            break
        if "/label/" in cid:
            group_title = urllib.parse.unquote(cid.split("/label/", 1)[-1].replace("+", " "))
            break
    fid = 0
    m = re.match(r"feed/(\d+)$", stream)
    if m:
        fid = int(m.group(1))
    enc = urllib.parse.quote(stream, safe="")
    rows = []
    cont = None
    try:
        for _page in range(MAX_PAGES):
            q = {"n": str(PAGE_N), "output": "json"}
            if cont:
                q["c"] = cont
            url = (
                f"{base}/api/greader.php/reader/api/0/stream/contents/{enc}?"
                + urllib.parse.urlencode(q)
            )
            data = json.loads(http("GET", url, headers=auth_h, timeout=25).decode("utf-8", "replace"))
            page_items = data.get("items") or []
            if not page_items:
                break
            hit_old = False
            for it in page_items:
                pub = int(it.get("published") or it.get("updated") or 0)
                if cutoff_ts > 0 and pub > 0 and pub < cutoff_ts:
                    hit_old = True
                    continue  # skip older than day window
                iid = greader_id_to_fever(it.get("id") or "")
                if not iid:
                    continue
                cats = it.get("categories") or []
                is_read = 1 if any(c.endswith("/state/com.google/read") for c in cats) else 0
                is_saved = 1 if any(c.endswith("/state/com.google/starred") for c in cats) else 0
                if scope == "read" and not is_read:
                    continue
                if scope == "saved" and not is_saved:
                    continue

                link = ""
                for alt in (it.get("canonical") or []) + (it.get("alternate") or []):
                    if alt.get("href"):
                        link = alt["href"]
                        break
                html = ""
                if isinstance(it.get("content"), dict):
                    html = it["content"].get("content") or ""
                if not html and isinstance(it.get("summary"), dict):
                    html = it["summary"].get("content") or ""
                media, is_vid = extract_media(html, link, ftitle, site)
                plain = strip_html(html)
                if len(html) > HTML_MAX:
                    html = html[:HTML_MAX] + "…"
                if len(plain) > TEXT_MAX:
                    plain = plain[:TEXT_MAX] + "…"
                # Subscription title is the FreshRSS feed name (CachyOS, Dark Journalist).
                # origin.title and item categories are publisher tags ("U.S. News").
                feed_title = ftitle or "Other"
                gtitle = group_title
                category = feed_title
                summary = plain[:SUMMARY_MAX] + ("…" if len(plain) > SUMMARY_MAX else "")
                rows.append({
                    "id": iid,
                    "id_hash": iid,
                    "feed_id": fid,
                    "feed_title": feed_title,
                    "group_id": 0,
                    "group_title": gtitle,
                    "category": category,
                    "title": it.get("title") or "(no title)",
                    "author": it.get("author") or "",
                    "url": link,
                    "html": html,
                    "text": plain,
                    "summary": summary,
                    "is_read": is_read,
                    "is_saved": is_saved,
                    "is_video": is_vid,
                    "media_url": media,
                    "created_on_time": pub,
                    "pubDate": "",
                })
            if max_days <= 0:
                break  # single page when using per_feed
            cont = data.get("continuation")
            if hit_old or not cont:
                break
    except Exception as e:
        return [], f"{stream}: {e}"
    return rows, None

out = []
seen = set()
errors = []
t0 = time.time()

with ThreadPoolExecutor(max_workers=WORKERS) as pool:
    futs = {pool.submit(fetch_feed, sub): sub for sub in feeds}
    for fut in as_completed(futs):
        rows, err = fut.result()
        if err:
            errors.append(err)
        for row in rows:
            iid = row["id"]
            if iid in seen:
                continue
            # Safety filter
            if cutoff_ts > 0 and int(row.get("created_on_time") or 0) > 0:
                if int(row["created_on_time"]) < cutoff_ts:
                    continue
            seen.add(iid)
            out.append(row)

# Newest first.
out.sort(key=lambda x: x.get("created_on_time") or 0, reverse=True)
if max_days > 0:
    # Day window is authoritative — generous safety cap only.
    soft_cap = 5000
else:
    soft_cap = max(limit, per_feed * max(1, len(feeds)))
    soft_cap = min(soft_cap, 800)
out = out[:soft_cap]

print(json.dumps({
    "ok": True,
    "mode": "fever",
    "auth": True,
    "writable": True,
    "scope": scope,
    "source": "greader-per-feed",
    "per_feed": per_feed,
    "max_days": max_days,
    "cutoff": cutoff_ts,
    "feeds": len(feeds),
    "workers": WORKERS,
    "ms": int((time.time() - t0) * 1000),
    "count": len(out),
    "total": len(out),
    "items": out,
    "errors": errors[:5],
}, ensure_ascii=False))
PY
}

cmd_items() {
    # items [limit] [scope] [per_feed] [max_days]
    #   scope: unread (default) | all | saved | read
    #   per_feed: All/Read when max_days=0
    #   max_days: when >0, primary history window (overrides per-feed/item soft caps)
    local limit="${1:-50}"
    local scope="${2:-unread}"
    local per_feed="${3:-12}"
    local max_days="${4:-0}"
    case "$scope" in
        unread|all|saved|read|starred) ;;
        *) scope="unread" ;;
    esac
    # accept alias
    [[ "$scope" == "starred" ]] && scope="saved"
    if ! [[ "$max_days" =~ ^[0-9]+$ ]]; then
        max_days=0
    fi

    need_cmd curl
    need_cmd jq
    if fever_mode; then
        local resp
        resp="$(fever_post "api")"
        local auth
        auth="$(printf '%s' "$resp" | jq -r '.auth // 0')"
        if [[ "$auth" != "1" ]]; then
            parse_rss_items "$limit" "$max_days" | jq -c --arg err \
                "Fever rejected the API password (auth=0). Use FreshRSS Profile → API password, not the web login password. Then Options → FreshRSS → Save server." \
                '. + {fever_auth_failed:true, has_password:true, error:$err}'
            return 0
        fi
        if [[ "$auth" == "1" ]]; then
            # all/read: per-feed Google Reader stream so quiet channels still appear
            if [[ "$scope" == "all" || "$scope" == "read" ]]; then
                fetch_greader_per_feed "$scope" "$limit" "$per_feed" "$max_days"
                return 0
            fi

            local raw_ids="" ids items feeds groups
            case "$scope" in
                unread)
                    raw_ids="$(fever_post "api&unread_item_ids" | jq -r '.unread_item_ids // ""')"
                    ;;
                saved)
                    raw_ids="$(fever_post "api&saved_item_ids" | jq -r '.saved_item_ids // ""')"
                    ;;
            esac

            if [[ -n "$raw_ids" ]]; then
                # Prefer newest-looking ids (FreshRSS ids tend to increase with time).
                # with_ids is limited (~50); chunk if needed.
                local id_file chunk_json collected="[]"
                id_file="$(mktemp)"
                printf '%s' "$raw_ids" | tr ',' '\n' | grep -E '^[0-9]+$' \
                    | sort -n | tail -n "$limit" | sort -nr >"$id_file"
                if [[ ! -s "$id_file" ]]; then
                    items='{"items":[],"total_items":0}'
                else
                    while IFS= read -r chunk; do
                        [[ -z "$chunk" ]] && continue
                        chunk_json="$(fever_post "api&items&with_ids=${chunk}")"
                        collected="$(jq -c -n \
                            --argjson a "$collected" \
                            --argjson b "$(printf '%s' "$chunk_json" | jq -c '.items // []')" \
                            '$a + $b | unique_by(.id)')"
                    done < <(awk '{print} NR%40==0{print ""}' "$id_file" | awk '
                        BEGIN{c=""}
                        NF{ if(c!="") c=c","$1; else c=$1; next }
                        { if(c!=""){ print c; c="" } }
                        END{ if(c!="") print c }
                    ')
                    items="$(jq -nc --argjson items "$collected" '{items:$items, total_items:($items|length)}')"
                fi
                rm -f "$id_file"
            else
                items='{"items":[],"total_items":0}'
            fi
            feeds="$(fever_post "api&feeds" 2>/dev/null || echo '{}')"
            groups="$(fever_post "api&groups" 2>/dev/null || echo '{}')"
            # Pass scope for optional client-side filter (read = only is_read)
            python3 - "$items" "$feeds" "$groups" "$limit" "$scope" "$max_days" <<'PY'
import json, sys, re, time
items_blob = json.loads(sys.argv[1])
feeds_blob = json.loads(sys.argv[2]) if sys.argv[2] else {}
groups_blob = json.loads(sys.argv[3]) if sys.argv[3] else {}
limit = int(sys.argv[4])
scope = sys.argv[5] if len(sys.argv) > 5 else "unread"
max_days = max(0, int(sys.argv[6]) if len(sys.argv) > 6 else 0)
cutoff_ts = (int(time.time()) - max_days * 86400) if max_days > 0 else 0

feed_map = {}
for f in feeds_blob.get("feeds") or []:
    feed_map[int(f.get("id"))] = f

group_title = {int(g.get("id")): g.get("title") or "" for g in (groups_blob.get("groups") or [])}
feed_to_group = {}
for fg in groups_blob.get("feeds_groups") or []:
    gid = int(fg.get("group_id"))
    for part in str(fg.get("feed_ids") or "").split(","):
        part = part.strip()
        if part:
            feed_to_group[int(part)] = gid

VIDEO_RE = re.compile(
    r"(youtube\.com|youtu\.be|youtube-nocookie\.com|vimeo\.com|"
    r"twitch\.tv|\.m4v\b|\.mp4\b|\.webm\b|\.mkv\b|/shorts/)",
    re.I,
)
VIDEO_SRC_RE = re.compile(r"<(?:video|source|iframe)[^>]+(?:src|data-src)=[\"']([^\"']+)[\"']", re.I)
HREF_RE = re.compile(r"href=[\"'](https?://[^\"']+)[\"']", re.I)
YT_WATCH_RE = re.compile(
    r"(https?://(?:www\.)?(?:youtube\.com/(?:watch\?v=|shorts/|embed/|live/)|youtu\.be/)[^\s\"'<>&]+)",
    re.I,
)

def strip_html(html: str) -> str:
    if not html:
        return ""
    t = re.sub(r"(?is)<script[^>]*>.*?</script>", " ", html)
    t = re.sub(r"(?is)<style[^>]*>.*?</style>", " ", t)
    t = re.sub(r"(?is)<br\s*/?>", "\n", t)
    t = re.sub(r"(?is)</p>", "\n\n", t)
    t = re.sub(r"(?is)<[^>]+>", " ", t)
    t = re.sub(r"&nbsp;", " ", t)
    t = re.sub(r"&amp;", "&", t)
    t = re.sub(r"&lt;", "<", t)
    t = re.sub(r"&gt;", ">", t)
    t = re.sub(r"&quot;", '"', t)
    t = re.sub(r"&#39;", "'", t)
    t = re.sub(r"[ \t]{2,}", " ", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    return t.strip()

def is_video_url(u: str) -> bool:
    return bool(u and VIDEO_RE.search(u))

def extract_media(html: str, url: str, feed_meta: dict):
    candidates = []
    # Prefer canonical YouTube watch URLs from html/url
    for blob in (url, html or ""):
        for m in YT_WATCH_RE.findall(blob or ""):
            candidates.append(m.rstrip(").,;"))
    for u in VIDEO_SRC_RE.findall(html or ""):
        candidates.append(u)
    for u in HREF_RE.findall(html or ""):
        candidates.append(u)
    if url:
        candidates.append(url)
    # feed site may be youtube channel
    site = (feed_meta or {}).get("site_url") or ""
    feed_url = (feed_meta or {}).get("url") or ""

    media = ""
    for u in candidates:
        if is_video_url(u):
            media = u
            break
    if not media:
        for u in candidates:
            if re.search(r"\.(m4v|mp4|webm|mkv)(\?|$)", u or "", re.I):
                media = u
                break
    # Mark as video if feed is a YouTube channel feed even when only channel page link
    feed_is_yt = bool(
        re.search(r"youtube\.com|youtu\.be", site + " " + feed_url, re.I)
        or re.search(r"youtube", ((feed_meta or {}).get("title") or ""), re.I)
    )
    if not media and feed_is_yt and url:
        media = url
    is_vid = 1 if (media or feed_is_yt and is_video_url(url or media or "")) else 0
    if media:
        is_vid = 1
    elif feed_is_yt and url:
        is_vid = 1
        media = url
    return media, is_vid

out = []
for it in items_blob.get("items") or []:
    html = it.get("html") or ""
    url = it.get("url") or ""
    fid = int(it.get("feed_id") or 0)
    fmeta = feed_map.get(fid) or {}
    media, is_vid = extract_media(html, url, fmeta)
    plain = strip_html(html)
    if len(html) > 6000:
        html = html[:6000] + "…"
    if len(plain) > 1200:
        plain = plain[:1200] + "…"
    gid = feed_to_group.get(fid)
    gtitle = group_title.get(gid, "") if gid is not None else ""
    ftitle = (fmeta.get("title") or "").strip() or "Other"
    # FreshRSS folder (group), not RSS <category> publisher tags
    category = ftitle
    out.append({
        "id": str(it.get("id")),
        "id_hash": str(it.get("id")),
        "feed_id": fid,
        "feed_title": ftitle,
        "group_id": gid if gid is not None else 0,
        "group_title": gtitle,
        "category": category,
        "title": it.get("title") or "(no title)",
        "author": it.get("author") or "",
        "url": url,
        "html": html,
        "text": plain,
        "summary": plain[:220] + ("…" if len(plain) > 220 else ""),
        "is_read": int(it.get("is_read") or 0),
        "is_saved": int(it.get("is_saved") or 0),
        "is_video": is_vid,
        "media_url": media,
        "created_on_time": int(it.get("created_on_time") or 0),
        "pubDate": "",
    })

# Optional scope filter for "read" (read-only items from the recent pages)
if scope == "read":
    out = [x for x in out if int(x.get("is_read") or 0) == 1]

# Day window (primary when max_days > 0)
if cutoff_ts > 0:
    out = [x for x in out if int(x.get("created_on_time") or 0) >= cutoff_ts]

# Newest first (and cap) — day window overrides item soft-cap
out.sort(key=lambda x: x.get("created_on_time") or 0, reverse=True)
if max_days > 0:
    out = out[:5000]
else:
    out = out[: max(1, min(limit, 200))]

print(json.dumps({
    "ok": True,
    "mode": "fever",
    "auth": True,
    "writable": True,
    "scope": scope,
    "max_days": max_days,
    "count": len(out),
    "total": items_blob.get("total_items") or len(out),
    "items": out,
}, ensure_ascii=False))
PY
            return 0
        fi
    fi
    parse_rss_items "$limit" "$max_days"
}

cmd_item() {
    local id="${1:-}"
    [[ -n "$id" ]] || json_err "usage: item <id>"
    # Reuse items list and filter (RSS has full body already)
    cmd_items 100 | jq -c --arg id "$id" '
        . as $root
        | ($root.items // [])
        | map(select(.id == $id or .id_hash == $id))
        | if length == 0 then
            {ok:false, error:("item not found: " + $id)}
          else
            {ok:true, mode:$root.mode, item:.[0]}
          end
    '
}

cmd_mark() {
    local action="$1"
    local id="${2:-}"
    [[ -n "$id" ]] || json_err "usage: $action <id>"
    fever_mode || json_err "mark/star requires FRESHRSS_API_PASSWORD (Profile → API password). Anonymous RSS mode is read-only."
    need_cmd curl
    need_cmd jq
    local as
    case "$action" in
        mark-read)   as="read" ;;
        mark-unread) as="unread" ;;
        star)        as="saved" ;;
        unstar)      as="unsaved" ;;
        *) json_err "unknown mark action: $action" ;;
    esac
    # Fever write: POST mark=item&as=...&id=...
    local resp
    resp="$(fever_post "api" "mark=item" "as=${as}" "id=${id}")"
    local auth
    auth="$(printf '%s' "$resp" | jq -r '.auth // 0')"
    [[ "$auth" == "1" ]] || json_err "fever auth failed while marking item"
    json_ok_obj "$(jq -nc --arg id "$id" --arg as "$as" '{id:$id, as:$as, mode:"fever"}')"
}

# Resolve Google Reader auth token (reuses cache used by status/items).
greader_auth_token() {
    FRESHRSS_BASE_URL="$FRESHRSS_BASE_URL" \
    FRESHRSS_USER="$FRESHRSS_USER" \
    FRESHRSS_API_PASSWORD="$FRESHRSS_API_PASSWORD" \
    python3 - <<'PY'
import json, os, time, urllib.parse, urllib.request
base = os.environ["FRESHRSS_BASE_URL"].rstrip("/")
user = os.environ.get("FRESHRSS_USER", "admin")
pw = os.environ.get("FRESHRSS_API_PASSWORD", "")
cache = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                     "quickshell", "freshrss-greader.auth")

def http(method, url, data=None, headers=None):
    h = {"User-Agent": "quickshell-freshrss/1.2"}
    if headers: h.update(headers)
    body = None
    if data is not None:
        body = urllib.parse.urlencode(data).encode()
        h["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.read()

try:
    with open(cache, "r", encoding="utf-8") as f:
        d = json.load(f)
    if d.get("user") == user and d.get("base") == base and time.time() - float(d.get("ts", 0)) < 25 * 60:
        print(d.get("auth") or "")
        raise SystemExit(0)
except SystemExit:
    raise
except Exception:
    pass
raw = http("POST", f"{base}/api/greader.php/accounts/ClientLogin",
           {"Email": user, "Passwd": pw}).decode("utf-8", "replace")
tok = ""
for line in raw.splitlines():
    if line.startswith("Auth="):
        tok = line.split("=", 1)[1].strip()
        break
if tok:
    try:
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        tmp = cache + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"auth": tok, "user": user, "base": base, "ts": time.time()}, f)
        os.chmod(tmp, 0o600)
        os.replace(tmp, cache)
    except Exception:
        pass
print(tok)
PY
}

# mark-feed-read <feed_id> | mark-feed-unread <feed_id>
# feed_id is numeric FreshRSS/Fever id (stream feed/N).
cmd_mark_feed() {
    local action="$1"
    local feed_id="${2:-}"
    [[ -n "$feed_id" ]] || json_err "usage: $action <feed_id>"
    [[ "$feed_id" =~ ^[0-9]+$ ]] || json_err "feed_id must be numeric (got: $feed_id)"
    fever_mode || json_err "mark-feed requires FRESHRSS_API_PASSWORD"
    need_cmd curl
    need_cmd jq
    need_cmd python3

    local stream="feed/${feed_id}"
    local auth
    auth="$(greader_auth_token)"
    [[ -n "$auth" ]] || json_err "greader auth failed"

    if [[ "$action" == "mark-feed-read" ]]; then
        # Whole feed → read (GReader mark-all-as-read up to now)
        local ts
        ts="$(date +%s)000000"
        local code body
        body="$(curl -sS -m 20 -w '\n%{http_code}' -X POST \
            -H "Authorization: GoogleLogin auth=${auth}" \
            "${FRESHRSS_BASE_URL}/api/greader.php/reader/api/0/mark-all-as-read" \
            --data-urlencode "s=${stream}" \
            --data-urlencode "ts=${ts}" 2>/dev/null || true)"
        code="$(printf '%s' "$body" | tail -n1)"
        body="$(printf '%s' "$body" | sed '$d')"
        # Fever fallback (marks items with id/time before "before")
        local before
        before="$(date +%s)"
        fever_post "api" "mark=feed" "as=read" "id=${feed_id}" "before=${before}" >/dev/null 2>&1 || true
        if [[ "$code" != "200" && "$body" != "OK" ]]; then
            # still ok if fever path worked
            :
        fi
        json_ok_obj "$(jq -nc --arg fid "$feed_id" --arg stream "$stream" \
            '{action:"mark-feed-read",feed_id:$fid,stream:$stream}')"
        return 0
    fi

    if [[ "$action" == "mark-feed-unread" ]]; then
        # Fetch recent item ids for the feed and strip the read tag (batch).
        FRESHRSS_BASE_URL="$FRESHRSS_BASE_URL" \
        FRESHRSS_GREADER_AUTH="$auth" \
        FRESHRSS_FEED_STREAM="$stream" \
        python3 - <<'PY'
import json, os, urllib.parse, urllib.request, sys

base = os.environ["FRESHRSS_BASE_URL"].rstrip("/")
auth = os.environ["FRESHRSS_GREADER_AUTH"]
stream = os.environ["FRESHRSS_FEED_STREAM"]
auth_h = {"Authorization": f"GoogleLogin auth={auth}", "User-Agent": "quickshell-freshrss/1.2"}

def http(method, url, data=None):
    h = dict(auth_h)
    body = None
    if data is not None:
        body = urllib.parse.urlencode(data, doseq=True).encode()
        h["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()

# Collect item ids (paginated). No xt= filter → includes read + unread.
ids = []
cont = None
for _ in range(20):
    q = {"s": stream, "n": "1000", "output": "json"}
    if cont:
        q["c"] = cont
    raw = http("GET", base + "/api/greader.php/reader/api/0/stream/items/ids?" + urllib.parse.urlencode(q))
    data = json.loads(raw.decode("utf-8", "replace"))
    refs = data.get("itemRefs") or []
    for ref in refs:
        iid = ref.get("id")
        if iid is not None:
            # decimal id → greader tag form
            try:
                n = int(iid)
                hexid = format(n, "016x")
                ids.append(f"tag:google.com,2005:reader/item/{hexid}")
            except Exception:
                ids.append(str(iid))
    cont = data.get("continuation")
    if not cont or not refs:
        break

# Remove read state in chunks
READ = "user/-/state/com.google/read"
chunk = 50
marked = 0
for i in range(0, len(ids), chunk):
    batch = ids[i:i + chunk]
    form = [("r", READ)]
    for item in batch:
        form.append(("i", item))
    try:
        http("POST", base + "/api/greader.php/reader/api/0/edit-tag", form)
        marked += len(batch)
    except Exception as e:
        print(json.dumps({"ok": False, "error": f"edit-tag failed: {e}", "partial": marked}))
        sys.exit(1)

print(json.dumps({
    "ok": True,
    "action": "mark-feed-unread",
    "stream": stream,
    "items": marked,
}, separators=(",", ":")))
PY
        return 0
    fi

    json_err "unknown mark-feed action: $action"
}

cmd_open_browser() {
    local url="${1:-}"
    [[ -n "$url" ]] || json_err "usage: open-browser <url>"
    need_cmd xdg-open
    # detach
    nohup xdg-open "$url" >/dev/null 2>&1 &
    json_ok_obj "$(jq -nc --arg url "$url" '{action:"browser",url:$url}')"
}

cmd_play_mpv() {
    local url="${1:-}"
    [[ -n "$url" ]] || json_err "usage: play-mpv <url>"
    need_cmd mpv
    # Ensure user-local yt-dlp is on PATH (YouTube). Do NOT pass --ytdl-path:
    # this mpv build rejects that option and fatally aborts (breaks direct .m4v too).
    export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
    local ytdl=""
    if command -v yt-dlp >/dev/null 2>&1; then
        ytdl="$(command -v yt-dlp)"
    elif command -v youtube-dl >/dev/null 2>&1; then
        ytdl="$(command -v youtube-dl)"
    fi

    local -a args=(--force-window=immediate)
    # Only enable ytdl for sites that need it; direct media streams play fine without.
    if [[ "$url" =~ youtube\.com|youtu\.be|youtube-nocookie\.com|vimeo\.com|twitch\.tv ]]; then
        args+=(--ytdl=yes)
    else
        # Avoid ytdl trying (and failing) on plain mp4/m4v CDN links
        args+=(--ytdl=no)
    fi

    local log="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/freshrss-mpv.log"
    mkdir -p "$(dirname "$log")" 2>/dev/null || true
    {
        printf '[%s] play %s (ytdl=%s)\n' "$(date -Iseconds)" "$url" "${ytdl:-none}"
        nohup mpv "${args[@]}" -- "$url" >>"$log" 2>&1 &
        echo "pid=$!"
    } >>"$log" 2>&1
    json_ok_obj "$(jq -nc --arg url "$url" --arg ytdl "${ytdl:-}" '{action:"mpv",url:$url,ytdl:$ytdl}')"
}

usage() {
    cat <<'EOF'
Usage: freshrss-api.sh <command> [args]

Commands:
  status                 Mode, auth, unread/item count
  items [limit] [scope] [per_feed] [max_days]
                         scope: unread (default) | all | read | saved
                         all/read: GReader per-feed (per_feed default 12)
                         max_days>0: only last N days (overrides per-feed/item soft caps)
  item <id>              Single entry
  mark-read <id>         Mark one item read (Fever)
  mark-unread <id>       Mark one item unread (Fever)
  star <id> | unstar <id>
  mark-feed-read <feed_id>    Whole feed → read (GReader + Fever)
  mark-feed-unread <feed_id>  Whole feed → unread (GReader edit-tag)
  open-browser <url>
  play-mpv <url>

Config: ~/.config/quickshell/secrets/freshrss.env
EOF
}

main() {
    load_secrets
    local cmd="${1:-}"
    shift || true
    case "$cmd" in
        status)        cmd_status "$@" ;;
        items|unread)  cmd_items "$@" ;;
        item)          cmd_item "$@" ;;
        mark-read|mark-unread|star|unstar) cmd_mark "$cmd" "$@" ;;
        mark-feed-read|mark-feed-unread) cmd_mark_feed "$cmd" "$@" ;;
        open-browser)  cmd_open_browser "$@" ;;
        play-mpv)      cmd_play_mpv "$@" ;;
        -h|--help|help|"") usage; exit 0 ;;
        *) json_err "unknown command: $cmd" ;;
    esac
}

main "$@"
