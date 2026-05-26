#!/usr/bin/env bash

# Lean braille spinner for tmux. Writes ONE global @spin option at 5 fps
# when any window has @busy=1; idles otherwise. Format reads #{@spin} —
# no per-window writes, no refresh-client spam, no capture-pane.
#
# Detection (setting @busy) is handled by tmux-window-status.sh at
# status-interval cadence. This script only animates the glyph.

set -u

PIDFILE="/tmp/tmux-agent-spinner.pid"

is_running() {
	[ -f "${PIDFILE}" ] || return 1
	local pid
	pid="$(cat "${PIDFILE}" 2>/dev/null || true)"
	[ -n "${pid}" ] || return 1
	kill -0 "${pid}" 2>/dev/null || return 1
	ps -p "${pid}" -o command= 2>/dev/null | grep -q "tmux-agent-spinner.sh __loop"
}

# Braille spinner — 10 frames, classic "dots" rotation.
CHARS=(⠹ ⢸ ⣰ ⣤ ⣆ ⡇ ⠏ ⠛)
N=${#CHARS[@]}

loop() {
	local i=0
	local last=""
	while true; do
		# No clients attached → sleep deep, skip everything.
		if [ -z "$(tmux list-clients -F x 2>/dev/null)" ]; then
			[ -n "${last}" ] && { tmux set -gqu @spin 2>/dev/null || true; last=""; }
			sleep 2
			continue
		fi

		# Any window currently busy?
		if ! tmux list-windows -a -F '#{@busy}' 2>/dev/null | grep -q '^1$'; then
			# Idle — clear @spin once, then poll slowly.
			[ -n "${last}" ] && { tmux set -gqu @spin 2>/dev/null || true; last=""; }
			sleep 1
			continue
		fi

		# Animate.
		local ch="${CHARS[$i]}"
		if [ "${ch}" != "${last}" ]; then
			tmux set -gq @spin "${ch}" 2>/dev/null || true
			last="${ch}"
		fi
		i=$(( (i + 1) % N ))
		sleep 0.15
	done
}

case "${1:-start}" in
	__loop)
		loop
		;;
	start)
		if is_running; then
			exit 0
		fi
		rm -f "${PIDFILE}"
		nohup "$0" __loop >/dev/null 2>&1 &
		echo "$!" > "${PIDFILE}"
		;;
	stop)
		if is_running; then
			kill "$(cat "${PIDFILE}")" 2>/dev/null || true
		fi
		pkill -f 'tmux-agent-spinner.sh __loop' 2>/dev/null || true
		rm -f "${PIDFILE}"
		;;
	restart)
		"$0" stop
		"$0" start
		;;
	status)
		if is_running; then echo "running"; else echo "stopped"; fi
		;;
	*)
		echo "usage: $0 [start|stop|restart|status]" >&2
		exit 1
		;;
esac
