#!/usr/bin/env bash
# Swap the active pane with the pane in a given direction, but DON'T follow it —
# focus stays at the source screen position (now holding the swapped-in pane).
# Acts like "push the current pane aside/down" and keep working where you are.
# Usage: swap-pane-stay.sh <left-of|right-of|up-of|down-of>
#
# Plain `swap-pane` (no -d) leaves the active pane at the source screen position
# rather than following the swapped pane object, which is exactly what we want.

set -eu

dir="${1:?direction required: left-of|right-of|up-of|down-of}"

tmux swap-pane -t "{${dir}}"
