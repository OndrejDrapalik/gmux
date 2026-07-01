#!/usr/bin/env bash
# Recursive pane splitting: splits the currently active pane,
# choosing direction based on its aspect ratio (splits the longer dimension).

mode=""
target=""

if [ "${1:-}" = "--vertical-first" ]; then
  mode="$1"
  target="${2:-}"
else
  target="${1:-}"
fi

tmux_target=()
if [ -n "${target}" ]; then
  tmux_target=(-t "${target}")
fi

# Get active pane's dimensions
read -r width height < <(tmux display-message -p "${tmux_target[@]}" '#{pane_width} #{pane_height}')

if [ "${mode}" = "--vertical-first" ]; then
  next_direction=$(tmux show-options -pqv "${tmux_target[@]}" @recursive_split_next 2>/dev/null || true)
  if [ -z "${next_direction}" ]; then
    next_direction="v"
  fi

  if [ "${next_direction}" = "v" ]; then
    new_pane=$(tmux split-window "${tmux_target[@]}" -v -P -F '#{pane_id}' -c '#{pane_current_path}')
    tmux set-option -p -t "${new_pane}" @recursive_split_next h
  else
    new_pane=$(tmux split-window "${tmux_target[@]}" -h -P -F '#{pane_id}' -c '#{pane_current_path}')
    tmux set-option -p -t "${new_pane}" @recursive_split_next v
  fi
  exit 0
fi

# Approximate character aspect ratio: terminal chars are ~2x taller than wide
# so multiply height by 2 to compare fairly
if (( width >= height * 2 )); then
  tmux split-window "${tmux_target[@]}" -h -c '#{pane_current_path}'
else
  tmux split-window "${tmux_target[@]}" -v -c '#{pane_current_path}'
fi
