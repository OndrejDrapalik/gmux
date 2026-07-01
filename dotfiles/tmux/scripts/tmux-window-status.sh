#!/usr/bin/env bash

# Render per-window busy state for tmux window tabs when a Claude/Codex task is in progress.
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
while read -r pane_id pane_cmd; do
	is_agent_cmd=0
	case "${pane_cmd}" in
		*claude* | *codex*) is_agent_cmd=1 ;;
		[0-9]*.[0-9]*.[0-9]*) is_agent_cmd=1 ;;
	esac
	if [ "${is_agent_cmd}" -ne 1 ]; then
		continue
	fi

	pane_title="$(tmux display-message -p -t "${pane_id}" "#{pane_title}" 2>/dev/null || true)"

	# Claude/Codex live spinner prefixes only (do not treat static "✳ Task Name" as busy).
	if printf "%s" "${pane_title}" | grep -qE '^([⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏⠂⠒⠢⠆⠐⠠⠄◐◓◑◒|/\\-] )'; then
		is_busy=1
		break
	fi

	# Codex: detect busy via "esc to interrupt" marker during active processing.
	if tmux capture-pane -p -J -t "${pane_id}" 2>/dev/null | grep -q 'esc to interrupt'; then
		is_busy=1
		break
	fi
done < <(tmux list-panes -t "${window_id}" -F '#{pane_id} #{pane_current_command}' 2>/dev/null || true)

# Always publish the window name so the format string can display it via #{@wname}.
tmux set-option -wqt "${window_id}" @wname "${window_name}" 2>/dev/null || true

# Pulse the dot when agent is working.
# Order matters: seed dot BEFORE @busy=1, clear @busy=0 BEFORE unsetting dot.
# This prevents a 1-frame gap where @busy=1 but @busy_dot is empty (causes jitter).
if [ "${is_busy}" -eq 1 ]; then
	# Seed @busy_dot with a static ◐, but ONLY when currently empty. Once the
	# spinner daemon takes over (within one 80ms tick of @busy=1), it writes
	# @busy_dot every frame with the correct animated phase — re-seeding here
	# would race with that and cause visible jitter. The "empty" path covers
	# two cases: very first transition to busy, and fallback if the daemon is
	# dead.
	current_dot=$(tmux show-options -wqvt "${window_id}" @busy_dot 2>/dev/null || printf '')
	if [ -z "${current_dot}" ]; then
		tmux set-option -wqt "${window_id}" @busy_dot "#[fg=#c0caf5]◐" 2>/dev/null || true
		tmux set-option -wqt "${window_id}" @busy_dot_a "#[fg=#02AFFF]◐" 2>/dev/null || true
	fi
	tmux set-option -wqt "${window_id}" @busy 1 2>/dev/null || true
else
	tmux set-option -wqt "${window_id}" @busy 0 2>/dev/null || true
	tmux set-option -wqut "${window_id}" @busy_dot 2>/dev/null || true
	tmux set-option -wqut "${window_id}" @busy_dot_a 2>/dev/null || true
	tmux set-option -wqut "${window_id}" @blink_off 2>/dev/null || true
fi
