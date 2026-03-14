#!/usr/bin/env bash

# Watches listening ports for processes inside tmux windows and updates:
#   @tmux_live_port_windows = space-separated window IDs (e.g. "@8 @10")
# Triggers status refresh only when the set changes.

set -eu

PIDFILE="/tmp/tmux-live-port-watcher.pid"
INTERVAL="${TMUX_LIVE_PORT_WATCH_INTERVAL:-0.6}"

is_running() {
	if [ ! -f "${PIDFILE}" ]; then
		return 1
	fi
	pid="$(cat "${PIDFILE}" 2>/dev/null || true)"
	if [ -z "${pid}" ]; then
		return 1
	fi
	if ! kill -0 "${pid}" 2>/dev/null; then
		return 1
	fi
	ps -p "${pid}" -o command= 2>/dev/null | grep -q "tmux-live-port-watcher.sh __loop"
}

compute_live_windows() {
	if ! command -v lsof >/dev/null 2>&1; then
		echo ""
		return 0
	fi

	{
		tmux list-panes -a -F '#{window_id} #{pane_pid}' 2>/dev/null | awk 'NF == 2 { print "P " $1 " " $2 }'
		ps -axo pid=,ppid= | awk 'NF == 2 { print "R " $1 " " $2 }'
		lsof -nP -iTCP -sTCP:LISTEN -FpPn 2>/dev/null | awk '
			/^p[0-9][0-9]*$/ {
				pid = substr($0, 2)
				next
			}
			/^n/ && pid != "" {
				name = substr($0, 2)
				port = name
				sub(/^.*:/, "", port)
				sub(/[^0-9].*$/, "", port)
				port_num = port + 0
				if (port ~ /^[0-9][0-9]*$/ && port_num >= 1024 && port_num <= 20000) {
					print "L " pid
				}
			}
		'
	} | awk '
		$1 == "P" {
			pane_window[$3] = $2
			next
		}
		$1 == "R" {
			ppid[$2] = $3
			next
		}
		$1 == "L" {
			listen_pid[++n] = $2
			next
		}
		END {
			for (i = 1; i <= n; i++) {
				pid = listen_pid[i]
				while (pid != "" && pid != 0) {
					if (pane_window[pid] != "") {
						live_window[pane_window[pid]] = 1
						break
					}
					pid = ppid[pid]
				}
			}
			for (wid in live_window) {
				print wid
			}
		}
	' | sort -u | paste -sd' ' - || true
}

loop() {
	last_live="__unset__"
	tmux set -gq @tmux_live_port_watcher_on "1" >/dev/null 2>&1 || true

	while true; do
		if [ -z "$(tmux list-clients 2>/dev/null || true)" ]; then
			sleep "${INTERVAL}"
			continue
		fi

		live_windows="$(compute_live_windows)"
		if [ "${live_windows}" != "${last_live}" ]; then
			tmux set -gq @tmux_live_port_windows "${live_windows}" >/dev/null 2>&1 || true
			# Set per-window @has_port for instant format-string rendering.
			# Ordering: seed @pulse BEFORE @has_port=1, clear @has_port BEFORE @pulse
			# to prevent empty flash.
			while IFS=$'\t' read -r wid wname; do
				[[ -z "${wid}" ]] && continue
				has=0
				case " ${live_windows} " in
					*" ${wid} "*) has=1 ;;
				esac
				if [ "${has}" -eq 1 ]; then
					# Seed pulse with plain name before flipping @has_port on
					current_pulse="$(tmux show -wqvt "${wid}" @pulse 2>/dev/null || true)"
					if [ -z "${current_pulse}" ]; then
						tmux set-option -wqt "${wid}" @pulse "${wname}" 2>/dev/null || true
						tmux set-option -wqt "${wid}" @pulse_a "${wname}" 2>/dev/null || true
						tmux set-option -wqt "${wid}" @pulse_dot "#[fg=#3a6b00]⏺" 2>/dev/null || true
						tmux set-option -wqt "${wid}" @pulse_dot_a "#[fg=#02AFFF]⏺" 2>/dev/null || true
					fi
					tmux set-option -wqt "${wid}" @has_port 1 2>/dev/null || true
				else
					# Clear @has_port before clearing pulse
					tmux set-option -wqt "${wid}" @has_port 0 2>/dev/null || true
					tmux set-option -wqut "${wid}" @pulse 2>/dev/null || true
					tmux set-option -wqut "${wid}" @pulse_a 2>/dev/null || true
					tmux set-option -wqut "${wid}" @pulse_dot 2>/dev/null || true
					tmux set-option -wqut "${wid}" @pulse_dot_a 2>/dev/null || true
				fi
			done < <(tmux list-windows -a -F '#{window_id}	#{window_name}' 2>/dev/null || true)
			tmux refresh-client -S >/dev/null 2>&1 || true
			last_live="${live_windows}"
		fi
		sleep "${INTERVAL}"
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
		rm -f "${PIDFILE}"
		tmux set -gq @tmux_live_port_watcher_on "0" >/dev/null 2>&1 || true
		tmux set -gq @tmux_live_port_windows "" >/dev/null 2>&1 || true
		for wid in $(tmux list-windows -a -F '#{window_id}' 2>/dev/null || true); do
			tmux set-option -wqt "${wid}" @has_port 0 2>/dev/null || true
			tmux set-option -wqut "${wid}" @pulse 2>/dev/null || true
			tmux set-option -wqut "${wid}" @pulse_a 2>/dev/null || true
			tmux set-option -wqut "${wid}" @pulse_dot 2>/dev/null || true
			tmux set-option -wqut "${wid}" @pulse_dot_a 2>/dev/null || true
		done
		tmux refresh-client -S >/dev/null 2>&1 || true
		;;
	restart)
		"$0" stop
		"$0" start
		;;
	status)
		if is_running; then
			echo "running"
		else
			echo "stopped"
		fi
		;;
	*)
		echo "usage: $0 [start|stop|restart|status]" >&2
		exit 1
		;;
esac
