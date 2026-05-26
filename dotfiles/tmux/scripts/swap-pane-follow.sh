#!/usr/bin/env bash
# Swap the active pane with the pane in a given direction, then follow it.
# Usage: swap-pane-follow.sh <left-of|right-of|up-of|down-of>
#
# tmux's swap-pane keeps focus at the source screen position rather than
# following the swapped pane object. We capture the active pane ID first
# (pane IDs are stable across swap-pane), perform the swap, then re-select
# that pane ID — which now lives at the new position.

set -eu

dir="${1:?direction required: left-of|right-of|up-of|down-of}"

src=$(tmux display -p '#{pane_id}')
tmux swap-pane -t "{${dir}}"
tmux select-pane -t "$src"
