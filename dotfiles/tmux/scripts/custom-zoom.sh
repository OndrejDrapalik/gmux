#!/usr/bin/env bash
# Toggle "custom zoom" for the current pane: grow it to a target
# percentage of the window in both dimensions WITHOUT hiding the
# other panes (unlike resize-pane -Z, which maximizes fullscreen).
#
# Reversible: the pre-zoom window_layout is saved in the window-scoped
# user option @customzoom_layout; a second invocation restores it.
#
# Usage: custom-zoom.sh [PERCENT]   (default 80)

set -eu

pct="${1:-80}"

saved=$(tmux show-options -wqv @customzoom_layout)

if [ -n "$saved" ]; then
  tmux select-layout "$saved"
  tmux set-option -wu @customzoom_layout
else
  current_layout=$(tmux display-message -p '#{window_layout}')
  tmux set-option -w @customzoom_layout "$current_layout"
  tmux resize-pane -x "${pct}%" -y "${pct}%"
fi
