#!/usr/bin/env bash
# list-terminals.sh — print installed terminal emulators, one per line.
# Used by SettingsPanel (Options → Stats → Terminal) to build the picker chips,
# and consumed as argv[0] when SysStatsPill launches btop / nvtop.
# Known terminals come first (preference order); anything else registering an
# XDG "TerminalEmulator" desktop entry is appended. Extend the list as needed.
set -u

known=(
    kitty foot alacritty wezterm ghostty ptyxis kgx
    gnome-terminal konsole xfce4-terminal mate-terminal deepin-terminal
    tilix terminator terminology rio st xterm urxvt lxterminal
    sakura roxterm tilda
)

{
    for t in "${known[@]}"; do
        command -v "$t" >/dev/null 2>&1 && printf '%s\n' "$t"
    done

    # Catch terminals not in the known list via their desktop entries.
    for d in /usr/share/applications "$HOME/.local/share/applications"; do
        [ -d "$d" ] || continue
        for f in "$d"/*.desktop; do
            [ -f "$f" ] || continue
            grep -q "TerminalEmulator" "$f" 2>/dev/null || continue
            exe=$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$f" | head -n1)
            [ -n "$exe" ] || continue
            bin=${exe##*/}
            case "$bin" in
                flatpak|env|sh|bash|gdbus|xdg-terminal-exec) continue ;;
            esac
            command -v "$bin" >/dev/null 2>&1 && printf '%s\n' "$bin"
        done
    done
} | awk '!seen[$0]++'
