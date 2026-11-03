<!-- Extracted from README for reference. See ../README.md for overview. -->

# Workspace overview (`widgets/Overview.qml`)

Fullscreen workspace view on the focused monitor. Live window captures sit above a workspace strip. Settings → Options → **Overview**. The layer namespace is `quickshell-overview`.

Hyprland binds in `~/.config/hypr/config/keybindings.lua`:

| Keys | IPC |
|------|-----|
| **Super+Tab** | `qs ipc call overview toggle` |
| **Super+Shift+Tab** | `qs ipc call overview desktop` |
| **Super+Ctrl+Tab** | `qs ipc call overview all` |

`toggle` opens the workspace view, or the all-workspaces view when **Open into all workspaces** is on. `open` always opens the workspace view. `desktop` and `all` close the overview when that mode is already open. `next` and `prev` step the strip while it is open, and move to the next or previous workspace when it is closed.

While it is open the focused monitor takes exclusive keyboard focus. **Super+Tab** still closes it.

| Key | Action |
|-----|--------|
| **Esc** | Close |
| **Tab** / **Shift+Tab** | Next or previous workspace card |
| **Arrows** | Move the selection between windows |
| **Enter** | Focus the selected window and close |
| **D** | Close the selected window |
| **A** | Toggle every workspace on this monitor |
| **Shift** alone | Flip desktop layout |
| **1–9**, **0** | Pick a strip card. **1** is the first card. **0** is the tenth |
| **Wheel** | Previous or next card, when **Wheel switches workspace** is on |

A click on a window focuses it and closes. That click skips the usual “focus the card you were viewing” step. Closing any other way focuses the workspace on the card you were viewing. The all-workspaces view does not change the workspace when it closes. A click on empty space closes when **Click empty space to close** is on.

## Views

| Layout | What the previews do |
|--------|----------------------|
| **Rows** | Pack windows at their real aspect |
| **Grid** | Equal cells. Dropping one preview on another swaps the two windows when **Drag to swap in grid layout** is on |
| **Natural** | Each window stays where it sits on the desktop. Desktop mode uses this placement and adds a close button on each window |

Drag a window onto a strip card to move it there. **Follow a dropped window** also switches the overview to that card. **Fly a dropped window into its card** shrinks the preview toward the card.

Large previews are `ScreencopyView` captures of the window. The capture source is cleared while the overview is closed. **Live window previews** follows the window. Off grabs one frame. Until a frame arrives, the preview is a color block from the app id or title.

## Workspace strip

The strip sits on the **Top**, **Bottom**, **Left**, or **Right** edge. Top or bottom thickness is **Strip height**. Left or right thickness is **Strip width**. **Card length** is the long side of each card. Cards use the emoji, word, font, bold, italic, and color from Options → **Workspaces**. **Use workspace numbers** replaces the emoji and name on numbered cards with the workspace id, in the bar font. **All** stays “All”. The special card keeps its icon and word.

**Strip previews** draws those windows inside the card with the same capture. Off leaves the card face empty. A color block shows until the frame arrives.

| Switch | Default | Effect |
|--------|---------|--------|
| **Dynamic workspaces** | on | Populated workspaces, plus one empty card at the end. A window has to land there before another empty card appears |
| **Hide emptied workspaces** | on | With dynamic workspaces, drop emptied cards. Hyprland already removes unpinned empty workspaces. Persistent ones stay |
| **Show empty workspaces** | on | When dynamic workspaces is off, keep empty workspaces as cards |
| **Show only active workspace** (Options → Workspaces) | off | Occupied numbered cards, plus exactly one next blank. A special card with no windows is hidden |
| **Show the special workspace** | off | One card for the special name from Options → Workspaces (`wsSpecialNameCustom`, or `magic` from `Config.qml` when that field is blank). Any other Hyprland special stays off the strip |
| **All-workspaces card** | off | Leading card of every window on this monitor |
| **Open into all workspaces** | off | **Super+Tab** starts in that view |

## Backdrop

**Backdrop dim** (`ovBlur`, 0–1) darkens the desktop. **Blur the desktop** asks Hyprland to blur this layer (`hl.layer_rule` named `quickshell-overview-blur`, namespace `^quickshell-overview$`). The dim still applies on top of that blur.

## Settings

Options → **Overview** is two columns for **Workspace strip**, **Previews**, **Workspaces**, and **Input**. **Layout** and **Motion** sit full width. The first change writes `state/bar-layout.json` (`hasOverviewPrefs` and the `ov*` keys). Until then the defaults in `shell.qml` apply. Colors follow the bar theme. There is no IPC setter for these options. `bar.setOverview(key, value)` is what the Options form calls.

Files: `widgets/Overview.qml`, `widgets/OverviewOptionsTab.qml`. Wired from `shell.qml`.
