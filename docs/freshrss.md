<!-- Extracted from README for reference. See ../README.md for overview. -->

# FreshRSS reader

Floating reader for a FreshRSS server. Opens from the bar pill or IPC (`qs ipc call freshRss toggle` / `refresh` / `show` / `hide`).

| Piece | Path |
|-------|------|
| Bar pill + window | `widgets/FreshRssPill.qml` |
| API client | `scripts/freshrss-api.sh` |
| Secrets (**outside git**) | `~/.config/freshrss-quickshell/freshrss.env` |
| Example template | `secrets/freshrss.env.example` |
| Read/write/test helpers | `freshrss-secrets-read.sh`, `freshrss-secrets-write.sh`, `freshrss-connection-test.sh` |
| Options UI | Control bar → **Options → FreshRSS** |
| Theme / limits | `Config.qml` (**FRESHRSS**) |

**Auth:** Profile → **API password** (not the web form password). The configured `FRESHRSS_USER` must be the same FreshRSS account where that API password was created. Without a password, public RSS is read-only.

**Data backends**

| Scope | Backend |
|-------|---------|
| All / Read | Google Reader API (per-feed parallel) |
| Unread / Starred | Fever API id lists |
| No API password | Public RSS `/i/?a=rss` (read-only) |

**Setup**

```bash
mkdir -p ~/.config/freshrss-quickshell
cp ~/.config/quickshell/secrets/freshrss.env.example \
   ~/.config/freshrss-quickshell/freshrss.env
# FRESHRSS_BASE_URL, FRESHRSS_USER, FRESHRSS_API_PASSWORD
chmod 600 ~/.config/freshrss-quickshell/freshrss.env

~/.config/quickshell/scripts/freshrss-api.sh status
# Or Options → FreshRSS → Test / Save server
```

**Reader UI**

- Always visible: date chips, scope, type, collapse/expand all feeds.
- **Filters** (collapsible, default open via Options): search, max days, per feed / max items.
- Feed expand → date groups; mark read/star when API password is set; **Play in mpv** on video items (`yt-dlp` on `PATH`).

**Defaults:** scope All, date All, categories collapsed A–Z, filters panel open by default (`freshRssFiltersExpanded`).

**Keyboard shortcuts** (window focused; not while typing in search)

| Keys | Action |
|------|--------|
| `w` / `s` or `↑` / `↓` | Move list cursor (feeds, dates, articles) |
| `Space` / `←` | Expand or collapse feed or date under cursor |
| `Enter` | Open article in detail pane (or expand feed/date if cursor is on a header) |
| `→` | **On an article:** open it (same as Enter). **On a feed/date:** expand/collapse |
| `j` / `k` | Next / previous **article** only |
| `/` or `Ctrl+F` | Focus search |
| `b` | Open selected article in browser |
| `v` | Play in mpv (**video items only**) |
| `r` / `Ctrl+R` | Refresh |
| `Esc` | Close window |
| `m` | Mark **item** read (writable) |
| `Shift+S` | Star / unstar item |
| `Shift+R` | Mark **feed** (category) read |
| `Shift+U` | Mark **feed** unread |

Double-click a row: video → mpv, otherwise browser.

**IPC / keybind**

```bash
qs ipc call freshRss toggle
qs ipc call freshRss refresh
qs ipc call freshRss show
qs ipc call shell setShowFreshRssPill false
```

Optional Hyprland: `bind = SUPER, R, exec, qs ipc call freshRss toggle`

**Config tokens** (`Config.qml`)

| Token | Default | Role |
|-------|---------|------|
| `showFreshRssPill` | `true` | Bar pill visibility |
| `freshRssPollIntervalMs` | `60000` | Unread badge poll |
| `freshRssItemLimit` | `80` | Max Unread/Starred ids |
| `freshRssPerFeedLimit` | `12` | Articles per feed for All/Read |
| `freshRssWidth` / `Height` | `980` / `640` | Floating window size |

**Performance (implementation notes)**

- All/Read fetch streams **in parallel** (thread pool); GReader auth cached under `~/.cache/quickshell/freshrss-greader.auth` (~25 min).
- List JSON **truncates** HTML/text so QML does not parse multi‑MB bodies for hundreds of rows.
- Categories **start collapsed** so the list paints feed headers only until expanded.
- Search avoids scanning full article HTML.
