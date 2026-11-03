# AGENTS.md

Quickshell bar and Hyprland config inspector for Hyprland on Wayland
(CachyOS). Public repo: crome1394/quickshell-dot-files, branch `master`.
Entry point: `shell.qml`. This directory is the live config and the bar
may be running from it.

## Layout
- `shell.qml` entry, `Config.qml` theme/fonts/defaults
- `widgets/` bar pills, control strip, inspector
- `components/` reusable pieces
- `scripts/` pollers and helpers
- `assets/`, `docs/`, `secrets/` (placeholders only)
- Gitignored runtime folders, never commit: `state/`, `themes/`, `profiles/`

New files go in the matching folder. Don't reorganize folders without
approval. Colors, sizes, and fonts come from `Config.qml`, never
hardcoded in widgets.

## Running and testing
- Verify commands with `qs --help` before using them.
- Start: `qs --daemonize -n`. From a worktree: `qs -p shell.qml`.
- IPC targets: `qs ipc show`. After changes, confirm every documented
  target still exists.
- Run `qmllint` on changed QML files and compare logs against a
  baseline taken before the change.
- Don't claim something is verified if it was only read.

## Standing rules
- Never push, force-push, change the remote, or rewrite history.
- Work on a branch, never directly on `master`.
- One logical change per commit. Keep cleanup, bug fixes, and
  refactors in separate commits.
- Every widget and feature is in active use. Never remove, disable,
  merge, or replace one.
- Dead code means leftovers only: unreferenced files, unused imports,
  properties, functions, commented-out blocks, orphaned assets, stale
  qmldir entries. Prove it's unused by searching imports, qmldir,
  Loader sources, dynamic/string references, IPC handlers, scripts,
  and JSON/config files. If unsure, ask instead of deleting.
- Code that only runs in an inactive mode is not dead. Classic and
  Dual layouts, left/right side bars, Active Window, and screensaver
  text styles are all live features.
- Don't change visible behavior, layout, or polling intervals without
  asking.
- If something looks like a bug but might be intentional, ask first.
- Consolidating duplicated logic into a shared service is allowed only
  when the copies are functionally identical (same command, parsing,
  interval, fallback). If they differ, list the differences and ask.
- If a change breaks the bar, fix it. At most 2 attempts, edit only
  the files in that change, and never fix by suppressing warnings or
  deleting features. If it still fails, revert the change, confirm the
  bar loads, and report it.
- If the bar can't be recovered, stop and restore from the backup.
- Never move, hide, or delete live `state/`, `themes/`, `profiles/`, or
  `secrets/` to test something. Copy them and test against the copy.
- After a change that affects the bar's windows, compare
  `hyprctl monitors -j | jq '.[].reserved'` with the value from before
  the change. Then restore the saved layout and confirm the state file
  is byte-identical.

## Intentional behavior (not bugs)
- Sysstats polls on a timer by design. Flag it only for very short
  intervals, polling while hidden, or a new process per tick.
- Only the Sys Stats button chosen in Options opens btop/nvtop. The
  other does nothing.
- The screensaver does not use DPMS.
- The app writes `~/.config/hypr/{screensaver.conf,monitors.lua,
  opacity.state,opacity.lua}` and reads
  `~/.config/freshrss-quickshell/freshrss.env`. Never edit those files
  or run commands that change them while testing.
- Never edit the Hyprland config.

## Secrets
Never commit tokens, keys, emails, hostnames, IPs, usernames, or
personal paths. `secrets/` holds placeholders only. The config must
start cleanly when `state/` and `secrets/` are empty.

## Optional later refactors

Not approved. Do not start these. ShellIpc and the shared edge-bar
face are already done. Leave the Config alias wall on `bar`. Widgets
bind those names directly. A new QML file that `qmllint` warns about
is a regression, and `PanelWindow` cannot be a component root.

3. **popupAnchor.js** — popup placement math, if the copies match. No save path and no exclusive-zone binding.
4. **widgetLayout.js** — `applyWidgetLayout` and the clone helpers. Reparenting is the risk. The functions are already one block.
5. **ThemeStore** — `themeColorsFile` plus `persistThemeColors`. A bad move changes live colors.
6. **BarLayoutStore** — the layout `FileView`, adapter, and `persistBarLayout`. Every setter writes through it, and the write guard is there to stop a reload loop.
7. **Launcher, Hyprland inspector, control bar, and connectivity hosts** — moving the inline hosts changes the ids popups and IPC already use.
