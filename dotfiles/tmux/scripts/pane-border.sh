#!/bin/bash
# Pane border format script - outputs path colored by length relative to pane width.
# Active pane path turns red when it exceeds 50% of the pane width.

pane_active="$1"
pane_path="$2"
pane_width="${3:-80}"

# Replace $HOME with ~
path="${pane_path/#$HOME/~}"

gray="#565f89"
normal="#E0AF69"
warn="#E16072"

worktree="#D77757"

if [[ "$pane_active" != "1" ]]; then
    echo "#[fg=${gray}]${path}"
elif [[ "$pane_path" == *"_worktrees/"* ]]; then
    echo "#[fg=${worktree}]${path}"
else
    echo "#[fg=${normal}]${path}"
fi
