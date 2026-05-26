#!/usr/bin/env bash
# Toggle "vertical half-zoom" for the current pane:
# expand it to consume the full height of its vertical-split parent
# (i.e. eat its column-siblings) without touching panes in other columns.
#
# Reversible: the pre-zoom window_layout is saved in the window-scoped
# user option @halfzoom_layout; a second invocation restores it.

set -eu

saved=$(tmux show-options -wqv @halfzoom_layout)

if [ -n "$saved" ]; then
  tmux select-layout "$saved"
  tmux set-option -wu @halfzoom_layout
else
  current_layout=$(tmux display-message -p '#{window_layout}')
  tmux set-option -w @halfzoom_layout "$current_layout"
  tmux resize-pane -y 9999
fi
