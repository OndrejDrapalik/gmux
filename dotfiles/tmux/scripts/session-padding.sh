#!/bin/bash
# Generate padding spaces equal to session name length + 1
# Guard: exit cleanly if tmux not ready
session_name=$(tmux display-message -p '#S' 2>/dev/null) || exit 0
[ -z "$session_name" ] && exit 0
length=$((${#session_name} + 1))
printf "%*s" "$length" ""
