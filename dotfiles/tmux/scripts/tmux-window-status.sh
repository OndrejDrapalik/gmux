#!/usr/bin/env bash

# Render per-window busy state for tmux window tabs when an agent task is in progress.
# Port indicator (⏺) is handled by native tmux format conditionals reading @has_port — not here.

set -eu

window_id="${1:-}"
active_flag="${2:-0}"
if [ -z "${window_id}" ]; then
	exit 0
fi

window_name="$(tmux display-message -p -t "${window_id}" "#{window_name}" 2>/dev/null || true)"
if [ -z "${window_name}" ]; then
	exit 0
fi

is_busy=0
detector="${GMUX_AGENT_DETECT:-${HOME}/.tmux/scripts/tmux-agent-detect.sh}"
while read -r pane_id pane_pid; do
	if "${detector}" pane-state "${pane_id}" "${pane_pid}" 2>/dev/null | grep -qx 'working'; then
		is_busy=1
		break
	fi
done < <(tmux list-panes -t "${window_id}" -F '#{pane_id} #{pane_pid}' 2>/dev/null || true)

# Always publish the window name so the format string can display it via #{@wname}.
tmux set-option -wqt "${window_id}" @wname "${window_name}" 2>/dev/null || true

if [ "${is_busy}" -eq 1 ]; then
	tmux set-option -wqt "${window_id}" @busy 1 2>/dev/null || true
else
	tmux set-option -wqt "${window_id}" @busy 0 2>/dev/null || true
fi
