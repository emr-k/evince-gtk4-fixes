#!/usr/bin/env bash
# Fixes the tiny page thumbnails in Evince's sidebar (GTK 4.22 and later).
# No rebuild and no root needed: it adds one CSS rule to your user GTK 4 stylesheet.
#
#   ./fix-thumbnails.sh           add the rule
#   ./fix-thumbnails.sh remove    take it out again
#   ./fix-thumbnails.sh status    show whether it is present
set -euo pipefail

CSS="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/gtk.css"
BEGIN="/* evince-gtk4-fixes: thumbnails begin */"
END="/* evince-gtk4-fixes: thumbnails end */"

present() { [ -f "$CSS" ] && grep -qF "$BEGIN" "$CSS"; }

case "${1:-install}" in
    install)
        if present; then
            echo "Already installed in $CSS"
            exit 0
        fi
        mkdir -p "$(dirname "$CSS")"
        {
            printf '\n%s\n' "$BEGIN"
            printf 'evsidebarthumbnails iconview { -gtk-icon-size: 1000px; }\n'
            printf '%s\n' "$END"
        } >> "$CSS"
        echo "Added the rule to $CSS"
        echo "Close all Evince windows and open a PDF again."
        ;;
    remove)
        if ! present; then
            echo "Nothing to remove in $CSS"
            exit 0
        fi
        tmp="$(mktemp)"
        awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1; next} $0==e{skip=0; next} !skip' "$CSS" > "$tmp"
        cat "$tmp" > "$CSS"
        rm -f "$tmp"
        echo "Removed the rule from $CSS"
        ;;
    status)
        if present; then echo "installed ($CSS)"; else echo "not installed"; fi
        ;;
    *)
        echo "Usage: $0 [install|remove|status]" >&2
        exit 2
        ;;
esac
