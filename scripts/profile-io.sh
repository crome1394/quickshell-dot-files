#!/usr/bin/env bash
# profile-io.sh — save / load full bar setups (theme colors + layout)
# Usage:
#   profile-io.sh list
#   profile-io.sh export <name>
#   profile-io.sh import <name-or-path>
#   profile-io.sh delete <name-or-path>
set -euo pipefail

QS_ROOT="${QUICKSHELL_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell}"
PROFILES_DIR="${QS_PROFILES_DIR:-$QS_ROOT/profiles}"
STATE_DIR="${QS_STATE_DIR:-$QS_ROOT/state}"
mkdir -p "$PROFILES_DIR"

sanitize_name() {
  local n="${1:-}"
  n="$(echo "$n" | tr -cd 'A-Za-z0-9._ -' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  n="${n// /_}"
  if [[ -z "$n" ]]; then
    n="setup"
  fi
  echo "$n"
}

# Delete only a direct child of the real directory. A symlink there is
# removed as a link. ".." and any path outside the directory are refused.
delete_direct_child() {
  local dir="$1" target="$2" what="$3"
  local real base parent parent_real victim
  real="$(readlink -f -- "$dir" 2>/dev/null || true)"
  if [[ -z "$real" || ! -d "$real" ]]; then
    echo "refusing to delete: cannot resolve $what dir" >&2
    exit 1
  fi
  case "$target" in
    ..|../*|*/..|*/../*)
      echo "refusing to delete outside $what dir: $target" >&2
      exit 1
      ;;
  esac
  if [[ "$target" != */* && ! -e "$target" && ! -L "$target" ]]; then
    base="$(sanitize_name "$target")"
    victim="$real/${base}.json"
  else
    parent="$(dirname -- "$target")"
    base="$(basename -- "$target")"
    case "$base" in
      ""|.|..)
        echo "refusing to delete outside $what dir: $target" >&2
        exit 1
        ;;
    esac
    parent_real="$(readlink -f -- "$parent" 2>/dev/null || true)"
    if [[ -z "$parent_real" || "$parent_real" != "$real" ]]; then
      echo "refusing to delete outside $what dir: $target" >&2
      exit 1
    fi
    victim="$real/$base"
  fi
  if [[ "$(dirname -- "$victim")" != "$real" ]]; then
    echo "refusing to delete outside $what dir: $target" >&2
    exit 1
  fi
  if [[ ! -e "$victim" && ! -L "$victim" ]]; then
    echo "$what not found: $victim" >&2
    exit 1
  fi
  # rm of a symlink removes the link, not the file it names.
  rm -f -- "$victim"
  echo "deleted $victim"
}


# Validate, then print the JSON. A file whose canonical path is already
# inside the real directory is printed unchanged, including a symlink
# there whose target stays inside it. A file from anywhere else, and a
# symlink inside the directory that resolves outside it, is copied in
# under a sanitized name. Unknown keys are dropped from that copy and
# reported. Machine-specific paths and click-launched commands are
# dropped from that copy too.
import_checked() {
  local dir="$1" path="$2" kind="$3" limit="$4"
  local real parent base parent_real resolved mode out dest name n tmp
  real="$(readlink -f -- "$dir" 2>/dev/null || true)"
  if [[ -z "$real" || ! -d "$real" ]]; then
    echo "refusing to import: cannot resolve $kind dir" >&2
    exit 1
  fi
  parent="$(dirname -- "$path")"
  base="$(basename -- "$path")"
  parent_real="$(readlink -f -- "$parent" 2>/dev/null || true)"
  resolved="$(readlink -f -- "$path" 2>/dev/null || true)"
  mode="external"
  # Internal only when the given name is a direct child and the canonical
  # target stays inside the directory. A symlink that points outside is
  # external even though the link itself sits in the directory.
  if [[ -n "$parent_real" && "$parent_real" == "$real" \
        && -n "$base" && "$base" != "." && "$base" != ".." \
        && -n "$resolved" && "$resolved" == "$real"/* ]]; then
    mode="internal"
  fi
  out="$(mktemp)"
  if ! python3 - "$kind" "$mode" "$path" "$limit" >"$out" <<'PY'
import json, math, re, sys

KIND, MODE, PATH, LIMIT = sys.argv[1:5]
EXTERNAL = MODE == "external"
# Present on an outside file: drop the key, including an empty value.
ALWAYS_DROP = {
    "quickLaunchAppsJson": "runs on click",
    "wallpaperDir": "machine-specific path",
    "wallpaperCurrent": "machine-specific path",
    "screenshotDir": "machine-specific path",
}
# Present and non-empty on an outside file. An empty launcher command is
# the normal "use the default" value and is kept.
NONEMPTY_DROP = {
    "launcherCommandCustom": "runs on click",
    "statTerminal": "runs on click",
}
THEME_KEYS = ("name", "version", "colors", "numbers", "fonts")
PROFILE_KEYS = ("name", "version", "kind", "theme", "layout")
FONT_STR = set(["fontFamily", "fontMono", "fontMain", "fontSecondary", "fontBar"])
FONT_NUM = set(["fontScale", "fontMonoScale", "fontMainScale", "fontSecondaryScale", "fontBarScale"])
COLOR_KEYS = set(["glassBg", "glassPillBg", "glassPopupBg", "glassBorder", "glassPopupBorder", "pillBorder", "glassHighlight", "glassPopupHighlight", "glassHover", "iconHoverBg", "accent", "muted", "text", "subtext", "barText", "overlay", "bg", "surface", "clock", "buttonBg", "controlActiveBg", "popupButtonHoverBg", "buttonText", "buttonTextActive", "wsActiveBg", "wsActiveText", "wsInactiveText", "audioSpeakerTier1", "audioSpeakerTier2", "audioSpeakerTier3", "audioSpeakerTier4", "audioMicTier1", "audioMicTier2", "audioMicTier3", "audioMicTier4", "iconColor", "audioSpeakerIcon", "audioMicIcon", "statUtilTier1", "statUtilTier2", "statUtilTier3", "statUtilTier4", "statCpuTier1", "statCpuTier2", "statCpuTier3", "statCpuTier4", "statMemTier1", "statMemTier2", "statMemTier3", "statMemTier4", "statGpuTier1", "statGpuTier2", "statGpuTier3", "statGpuTier4", "statVramTier1", "statVramTier2", "statVramTier3", "statVramTier4", "statTempCool", "statTempWarm", "statTempHot", "qlRunningDot"])
NUMBER_KEYS = set(["audioUtilThreshold1", "audioUtilThreshold2", "audioUtilThreshold3", "audioMicUtilThreshold1", "audioMicUtilThreshold2", "audioMicUtilThreshold3", "statUtilThreshold1", "statUtilThreshold2", "statUtilThreshold3", "statTempWarmAt", "statTempHotAt"])
LAYOUT_TYPES = {
    "barPosition": "string",
    "barLayoutMode": "string",
    "barSpanFull": "bool",
    "panelSpanFull": "bool",
    "panelSizeScale": "real",
    "audioViewMode": "int",
    "topBarAlign": "string",
    "bottomBarAlign": "string",
    "showLeftBar": "bool",
    "showRightBar": "bool",
    "leftBarAlign": "string",
    "rightBarAlign": "string",
    "leftBarSpanFull": "bool",
    "rightBarSpanFull": "bool",
    "uiScaleManual": "real",
    "barEdgeMargin": "int",
    "barSizeScale": "real",
    "flushWindowsToBar": "bool",
    "tooltipDelay": "int",
    "tooltipAlignJson": "string",
    "clockFormat": "string",
    "clockFont": "string",
    "clockFontScale": "real",
    "widgetLayoutJson": "string",
    "widgetLayoutClassicJson": "string",
    "widgetLayoutDualJson": "string",
    "quickLaunchAppsJson": "string",
    "wallpaperDir": "string",
    "wallpaperCurrent": "string",
    "wallpaperTileSize": "int",
    "screenshotDir": "string",
    "hasOverviewPrefs": "bool",
    "ovLayout": "string",
    "ovAnchor": "string",
    "ovGap": "int",
    "ovPadding": "int",
    "ovPaddingTop": "int",
    "ovPaddingBottom": "int",
    "ovMaxScale": "real",
    "ovDuration": "int",
    "ovPreviewRound": "int",
    "ovBlur": "real",
    "ovBackdropBlur": "bool",
    "ovSwitchAnimation": "bool",
    "ovSwitchDuration": "int",
    "ovMoveAnimation": "bool",
    "ovMoveDuration": "int",
    "ovStripOffset": "int",
    "ovStripHeight": "int",
    "ovStripWidth": "int",
    "ovStripCardMax": "int",
    "ovStripMargin": "int",
    "ovStripGap": "int",
    "ovStripCardRound": "int",
    "ovHoverBorder": "int",
    "ovSelectBorder": "int",
    "ovLivePreviews": "bool",
    "ovShowWindowLabels": "bool",
    "ovShowWsLabels": "bool",
    "ovStripPreviews": "bool",
    "ovNumberLabels": "bool",
    "ovDynamic": "bool",
    "ovAutodelete": "bool",
    "ovShowEmpty": "bool",
    "ovShowSpecial": "bool",
    "ovStripAllCard": "bool",
    "ovShowAll": "bool",
    "ovSwitchOnNew": "bool",
    "ovSwitchOnDrop": "bool",
    "ovDragToSwap": "bool",
    "ovFocusFollowsMouse": "bool",
    "ovScrollSwitches": "bool",
    "ovExitOnClick": "bool",
    "ovExitOnSwitch": "bool",
    "widgetScalesJson": "string",
    "showLauncherPill": "bool",
    "showQuickLaunchPill": "bool",
    "showWorkspacesPill": "bool",
    "showStatsWidget": "bool",
    "showTrayPill": "bool",
    "showNetworkPanel": "bool",
    "showBluetoothPill": "bool",
    "showAudioPill": "bool",
    "showClockPill": "bool",
    "showNotificationPill": "bool",
    "showPowerPill": "bool",
    "showOpacityPill": "bool",
    "showTailscalePill": "bool",
    "showFreshRssPill": "bool",
    "showHyprInspPill": "bool",
    "showControlBarPill": "bool",
    "showActiveWindowPill": "bool",
    "activeWindowPillCorner": "string",
    "activeWindowExcludesJson": "string",
    "hasColorPresetPrefs": "bool",
    "showColorPresets": "bool",
    "hasWorkspacePrefs": "bool",
    "showMagicWorkspacePill": "bool",
    "wsMinimumShown": "int",
    "wsShowOnlyActive": "bool",
    "wsShowNumbers": "bool",
    "notificationAutoExpand": "bool",
    "notificationStaggerRows": "bool",
    "notificationClearOnBoot": "bool",
    "notificationShowCount": "bool",
    "notificationCorner": "string",
    "notificationTimeout": "int",
    "wsStartupWorkspace": "int",
    "wsStartupCloseMagic": "bool",
    "wsIconSpecialCustom": "string",
    "wsSpecialNameCustom": "string",
    "wsSpecialFont": "string",
    "wsSpecialFontPx": "int",
    "wsSpecialText": "string",
    "wsSpecialBold": "bool",
    "wsSpecialItalic": "bool",
    "wsSpecialColor": "string",
    "hasLauncherPrefs": "bool",
    "launcherIconCustom": "string",
    "launcherIconPx": "int",
    "launcherCommandCustom": "string",
    "hasWsSlots": "bool",
    "wsSlotsJson": "string",
    "hasStatPrefs": "bool",
    "showStatCpu": "bool",
    "showStatVram": "bool",
    "showStatMem": "bool",
    "showStatGpu": "bool",
    "showStatGauges": "bool",
    "statTerminal": "string",
    "statLaunchButton": "string",
    "showNetworkFullIp": "bool",
    "showNetworkLastOctet": "bool",
    "showNetworkDeviceName": "bool",
    "hasAudioMenuPrefs": "bool",
    "showEchoCancelInMenu": "bool",
    "showAudioSummary": "bool",
    "showAudioDefaults": "bool",
    "showAudioLevelMeters": "bool",
    "audioSummaryExpanded": "bool",
    "audioDefaultsExpanded": "bool",
    "hasFreshRssPrefs": "bool",
    "freshRssFiltersExpanded": "bool",
    "hasDockPrefs": "bool",
    "dockEffect": "string",
    "dockMaxScale": "real",
    "dockRadius": "int",
    "dockJumpPx": "int",
    "dockScope": "string"
}
HEX = re.compile(r"#?[0-9A-Fa-f]{3}(?:[0-9A-Fa-f]{3})?$")

def die(msg):
    print(msg, file=sys.stderr)
    raise SystemExit(1)

def is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)

def check_name(v):
    if not isinstance(v, str):
        die("refusing to import: name must be a string")
    if len(v) > 200 or any(ord(ch) < 32 for ch in v):
        die("refusing to import: name is too long or has a control character")

def check_color(key, entry, dropped, prefix):
    label = prefix + key
    if isinstance(entry, str):
        if not HEX.fullmatch(entry.strip()):
            die("refusing to import: color %s is not a hex color" % label)
        return entry
    if not isinstance(entry, dict):
        die("refusing to import: color %s must be a hex string or an object" % label)
    out = {}
    for fld, val in entry.items():
        if fld not in ("hex", "alpha", "color"):
            if EXTERNAL:
                dropped.append("%s.%s (unknown key)" % (label, fld))
                continue
            out[fld] = val
            continue
        out[fld] = val
    if "hex" not in out and "color" not in out:
        die("refusing to import: color %s needs hex" % label)
    for fld in ("hex", "color"):
        if fld in out and (not isinstance(out[fld], str) or not HEX.fullmatch(out[fld].strip())):
            die("refusing to import: color %s.%s is not a hex color" % (label, fld))
    if "alpha" in out:
        alpha = out["alpha"]
        if not is_num(alpha) or alpha < 0 or alpha > 1:
            die("refusing to import: color %s alpha must be a number from 0 to 1" % label)
    return out

def clean_theme(data, dropped, prefix):
    if not isinstance(data, dict):
        die("refusing to import: theme must be an object")
    out = {}
    for key, val in data.items():
        if key not in THEME_KEYS:
            if EXTERNAL:
                dropped.append("%s%s (unknown key)" % (prefix, key))
                continue
        out[key] = val
    if "name" in out:
        check_name(out["name"])
    if "version" in out and (isinstance(out["version"], bool) or not isinstance(out["version"], int)):
        die("refusing to import: version must be an integer")
    if "colors" in out:
        colors = out["colors"]
        if not isinstance(colors, dict):
            die("refusing to import: colors must be an object")
        cleaned = {}
        for key, val in colors.items():
            if key not in COLOR_KEYS:
                if EXTERNAL:
                    dropped.append("%scolors.%s (unknown key)" % (prefix, key))
                    continue
                cleaned[key] = val
                continue
            cleaned[key] = check_color(key, val, dropped, prefix + "colors.")
        out["colors"] = cleaned
    if "numbers" in out:
        numbers = out["numbers"]
        if not isinstance(numbers, dict):
            die("refusing to import: numbers must be an object")
        cleaned = {}
        for key, val in numbers.items():
            if key not in NUMBER_KEYS:
                if EXTERNAL:
                    dropped.append("%snumbers.%s (unknown key)" % (prefix, key))
                    continue
                cleaned[key] = val
                continue
            if not is_num(val):
                die("refusing to import: number %s%s must be a number" % (prefix, key))
            cleaned[key] = val
        out["numbers"] = cleaned
    if "fonts" in out:
        fonts = out["fonts"]
        if not isinstance(fonts, dict):
            die("refusing to import: fonts must be an object")
        cleaned = {}
        for key, val in fonts.items():
            if key not in FONT_STR and key not in FONT_NUM:
                if EXTERNAL:
                    dropped.append("%sfonts.%s (unknown key)" % (prefix, key))
                    continue
                cleaned[key] = val
                continue
            if key in FONT_STR:
                if not isinstance(val, str):
                    die("refusing to import: font %s must be a string" % key)
            elif not is_num(val):
                die("refusing to import: font %s must be a number" % key)
            cleaned[key] = val
        out["fonts"] = cleaned
    return out

def clean_layout(layout, dropped):
    if not isinstance(layout, dict):
        die("refusing to import: layout must be an object")
    out = {}
    for key, val in layout.items():
        if EXTERNAL and key in ALWAYS_DROP:
            dropped.append("layout.%s (%s)" % (key, ALWAYS_DROP[key]))
            continue
        if EXTERNAL and key in NONEMPTY_DROP and val not in ("", None):
            dropped.append("layout.%s (%s)" % (key, NONEMPTY_DROP[key]))
            continue
        if key not in LAYOUT_TYPES:
            if EXTERNAL:
                dropped.append("layout.%s (unknown key)" % key)
                continue
            out[key] = val
            continue
        if val is None:
            out[key] = val
            continue
        typ = LAYOUT_TYPES[key]
        if typ == "string" and not isinstance(val, str):
            die("refusing to import: layout.%s must be a string" % key)
        elif typ == "bool" and not isinstance(val, bool):
            die("refusing to import: layout.%s must be true or false" % key)
        elif typ in ("int", "real") and not is_num(val):
            die("refusing to import: layout.%s must be a number" % key)
        out[key] = val
    return out

def clean_profile(data, dropped):
    if not isinstance(data, dict):
        die("refusing to import: setup must be an object")
    out = {}
    for key, val in data.items():
        if key not in PROFILE_KEYS:
            if EXTERNAL:
                dropped.append("%s (unknown key)" % key)
                continue
        out[key] = val
    if "name" in out:
        check_name(out["name"])
    if "version" in out and (isinstance(out["version"], bool) or not isinstance(out["version"], int)):
        die("refusing to import: version must be an integer")
    if "kind" in out and out["kind"] != "setup":
        die("refusing to import: kind must be setup")
    if "theme" in out:
        out["theme"] = clean_theme(out["theme"], dropped, "theme.")
    if "layout" in out:
        out["layout"] = clean_layout(out["layout"], dropped)
    return out

raw = open(PATH, "rb").read()
if len(raw) > int(LIMIT):
    die("refusing to import: file is larger than %s bytes" % LIMIT)
try:
    text = raw.decode("utf-8")
except UnicodeDecodeError:
    die("refusing to import: file is not UTF-8")
try:
    data = json.loads(text)
except json.JSONDecodeError as exc:
    die("refusing to import: invalid JSON (%s)" % exc.msg)
if not isinstance(data, dict):
    die("refusing to import: root must be an object")
dropped = []
if KIND == "theme":
    cleaned = clean_theme(data, dropped, "")
elif KIND == "profile":
    cleaned = clean_profile(data, dropped)
else:
    die("refusing to import: unknown kind")
if (not EXTERNAL) or (not dropped):
    sys.stdout.buffer.write(raw)
else:
    sys.stdout.write(json.dumps(cleaned, indent=2, ensure_ascii=False) + "\n")
for item in dropped:
    print("dropped %s" % item, file=sys.stderr)

PY
  then
    rm -f -- "$out"
    exit 1
  fi
  if [[ "$mode" == "external" ]]; then
    name="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); print(d.get("name") or "")' "$out")"
    name="$(sanitize_name "$name")"
    dest="$real/${name}.json"
    n=2
    while [[ -e "$dest" || -L "$dest" ]]; do
      dest="$real/${name}-$n.json"
      n=$((n + 1))
      if (( n > 100 )); then
        rm -f -- "$out"
        echo "refusing to import: too many existing names" >&2
        exit 1
      fi
    done
    tmp="$(mktemp "${dest}.XXXXXX")"
    chmod 644 -- "$tmp"
    if ! cp -- "$out" "$tmp"; then
      rm -f -- "$tmp" "$out"
      exit 1
    fi
    mv -f -- "$tmp" "$dest"
    echo "copied $dest" >&2
  fi
  cat -- "$out"
  rm -f -- "$out"
}

cmd="${1:-}"
case "$cmd" in
  list)
    python3 - "$PROFILES_DIR" <<'PY'
import json, os, sys
d = sys.argv[1]
out = []
if os.path.isdir(d):
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".json"):
            continue
        path = os.path.join(d, fn)
        name = fn[:-5]
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and data.get("name"):
                name = str(data["name"])
        except Exception:
            pass
        out.append({"id": fn[:-5], "name": name, "path": path})
print(json.dumps(out))
PY
    ;;
  export)
    raw_name="${2:-setup}"
    name="$(sanitize_name "$raw_name")"
    dest="$PROFILES_DIR/${name}.json"
    python3 - "$dest" "$raw_name" "$STATE_DIR/theme-colors.json" "$STATE_DIR/bar-layout.json" <<'PY'
import json, os, sys
dest, raw_name, theme_path, layout_path = sys.argv[1:5]
theme = {}
if os.path.isfile(theme_path):
    with open(theme_path, "r", encoding="utf-8") as f:
        wrap = json.load(f)
    if isinstance(wrap, dict) and wrap.get("themeJson"):
        try:
            theme = json.loads(wrap["themeJson"])
        except Exception:
            theme = wrap
    elif isinstance(wrap, dict) and "colors" in wrap:
        theme = wrap
layout = {}
if os.path.isfile(layout_path):
    with open(layout_path, "r", encoding="utf-8") as f:
        layout = json.load(f)
if not isinstance(theme, dict):
    theme = {}
if not isinstance(layout, dict):
    layout = {}
data = {
    "name": raw_name,
    "version": 1,
    "kind": "setup",
    "theme": theme,
    "layout": layout,
}
os.makedirs(os.path.dirname(dest), exist_ok=True)
with open(dest, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(dest)
PY
    ;;
  import)
    target="${2:-}"
    if [[ -z "$target" ]]; then
      echo "usage: profile-io.sh import <name-or-path>" >&2
      exit 1
    fi
    if [[ -f "$target" ]]; then
      path="$target"
    else
      name="$(sanitize_name "$target")"
      path="$PROFILES_DIR/${name}.json"
    fi
    if [[ ! -f "$path" ]]; then
      echo "setup not found: $path" >&2
      exit 1
    fi
    import_checked "$PROFILES_DIR" "$path" profile 1048576
    ;;
  delete)
    target="${2:-}"
    if [[ -z "$target" ]]; then
      echo "usage: profile-io.sh delete <name-or-path>" >&2
      exit 1
    fi
    delete_direct_child "$PROFILES_DIR" "$target" "setup"
    ;;
  *)
    echo "usage: profile-io.sh list|export <name>|import <name-or-path>|delete <name-or-path>" >&2
    exit 1
    ;;
esac
