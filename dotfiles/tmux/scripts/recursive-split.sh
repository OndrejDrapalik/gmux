#!/usr/bin/env bash
# Recursive pane splitting: splits the currently active pane,
# choosing direction based on its aspect ratio (splits the longer dimension).

# Get active pane's dimensions
read -r width height < <(tmux display-message -p '#{pane_width} #{pane_height}')

# Approximate character aspect ratio: terminal chars are ~2x taller than wide
# so multiply height by 2 to compare fairly
if (( width >= height * 2 )); then
  tmux split-window -h -c '#{pane_current_path}'
else
  tmux split-window -v -c '#{pane_current_path}'
fi
