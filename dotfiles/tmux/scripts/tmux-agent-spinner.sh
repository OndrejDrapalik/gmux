#!/usr/bin/env bash

# Lean braille spinner for tmux.
# Two processes: __scan (busy detection, every SCAN_INTERVAL, hysteresis on idle)
# and __loop (pure animation at ~8fps, one tmux fork per frame, never blocks on scans).
# Scanner writes per-window @busy + global @busy_any; animation only reads @busy_any.

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

# Braille spinner — 8 frames, classic "dots" rotation.
CHARS=(⠹ ⢸ ⣰ ⣤ ⣆ ⡇ ⠏ ⠛)
N=${#CHARS[@]}
SCAN_INTERVAL=3
SPIN_INTERVAL=0.12
# Consecutive idle scans required before a busy window is marked idle.
# Bridges short gaps (tool-call boundaries, turn transitions) so the
# spinner runs continuously start-to-end of a task.
MISS_LIMIT=3

TITLE_BUSY_RE='^([⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏⠂⠒⠢⠆⠐⠠⠄◐◓◑◒|/\-] )'

SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null && pwd)"
AGENT_DETECT="${GMUX_AGENT_DETECT:-${SCRIPT_DIR}/tmux-agent-detect.sh}"

clear_spin() {
	tmux set -gqu @spin \; refresh-client -S 2>/dev/null || true
}

pane_is_busy() {
	local pane_id="$1" pane_pid="$2" pane_title="$3"

	# Cheapest check first: live spinner prefix in the pane title. Also covers
	# remote agents (ssh) whose title arrives via OSC with no local process.
	if printf "%s" "${pane_title}" | grep -qE "${TITLE_BUSY_RE}"; then
		return 0
	fi

	# Full per-harness detection (process tree + screen chrome) lives in the
	# detector; the caller shares one ps snapshot per scan via
	# GMUX_AGENT_PROCESS_TABLE so this stays one capture-pane per agent pane.
	[ -x "${AGENT_DETECT}" ] || return 1
	[ "$(GMUX_AGENT_PANE_TITLE="${pane_title}" "${AGENT_DETECT}" pane-state "${pane_id}" "${pane_pid}" 2>/dev/null)" = "working" ]
}

update_window_state() {
	local window_id window_name pane_id pane_pid pane_title
	local busy_now prev_busy prev_miss miss any_busy
	local busy_windows=" "
	local -a batch=()

	# One ps snapshot per scan, shared by every detector call below.
	local ps_table
	ps_table="$(mktemp)"
	ps -axo pid=,ppid=,pgid=,tpgid=,comm=,args= 2>/dev/null | awk '{
		pid=$1; ppid=$2; pgid=$3; tpgid=$4; comm=$5;
		$1=$2=$3=$4=$5="";
		sub(/^[[:space:]]+/, "", $0);
		printf "%s\t%s\t%s\t%s\t%s\t%s\n", pid, ppid, pgid, tpgid, comm, $0
	}' >"${ps_table}"
	export GMUX_AGENT_PROCESS_TABLE="${ps_table}"

	while IFS=$'\t' read -r window_id pane_id pane_pid pane_title; do
		case "${busy_windows}" in *" ${window_id} "*) continue ;; esac
		if pane_is_busy "${pane_id}" "${pane_pid}" "${pane_title}"; then
			busy_windows="${busy_windows}${window_id} "
		fi
	done < <(tmux list-panes -a -F '#{window_id}	#{pane_id}	#{pane_pid}	#{pane_title}' 2>/dev/null || true)

	unset GMUX_AGENT_PROCESS_TABLE
	rm -f "${ps_table}"

	any_busy=0
	while IFS=$'\t' read -r window_id window_name prev_busy prev_miss; do
		[ -n "${window_id}" ] || continue
		batch+=(set-option -wqt "${window_id}" @wname "${window_name}" \;)

		case "${busy_windows}" in
			*" ${window_id} "*) busy_now=1 ;;
			*) busy_now=0 ;;
		esac

		if [ "${busy_now}" -eq 1 ]; then
			any_busy=1
			[ "${prev_busy}" = "1" ] || batch+=(set-option -wqt "${window_id}" @busy 1 \;)
			[ "${prev_miss:-0}" = "0" ] || [ -z "${prev_miss}" ] || batch+=(set-option -wqt "${window_id}" @busy_miss 0 \;)
		elif [ "${prev_busy}" = "1" ]; then
			# Hysteresis: tolerate short detection gaps before going idle.
			miss=$(( ${prev_miss:-0} + 1 ))
			if [ "${miss}" -ge "${MISS_LIMIT}" ]; then
				batch+=(set-option -wqt "${window_id}" @busy 0 \; set-option -wqt "${window_id}" @busy_miss 0 \;)
			else
				any_busy=1
				batch+=(set-option -wqt "${window_id}" @busy_miss "${miss}" \;)
			fi
		else
			[ "${prev_busy}" = "0" ] || batch+=(set-option -wqt "${window_id}" @busy 0 \;)
		fi
	done < <(tmux list-windows -a -F '#{window_id}	#{window_name}	#{@busy}	#{@busy_miss}' 2>/dev/null || true)

	batch+=(set -gq @busy_any "${any_busy}")
	tmux "${batch[@]}" 2>/dev/null || true
}

scan_loop() {
	while true; do
		if ! tmux has-session 2>/dev/null; then
			exit 0
		fi
		if [ -z "$(tmux list-clients -F x 2>/dev/null)" ]; then
			tmux set -gq @busy_any 0 2>/dev/null || true
			sleep 5
			continue
		fi
		update_window_state
		sleep "${SCAN_INTERVAL}"
	done
}

loop() {
	local scan_pid i ch busy last
	"$0" __scan &
	scan_pid=$!
	trap 'kill "${scan_pid}" 2>/dev/null; exit 0' EXIT TERM INT

	i=0
	last=""
	while true; do
		busy="$(tmux show -gqv @busy_any 2>/dev/null)" || {
			tmux has-session 2>/dev/null || exit 0
			sleep 2
			continue
		}

		if [ "${busy}" != "1" ]; then
			if [ -n "${last}" ]; then
				clear_spin
				last=""
			fi
			sleep 0.5
			continue
		fi

		# Animate — single tmux fork per frame, busy state read in the same call.
		ch="${CHARS[$i]}"
		busy="$(tmux set -gq @spin "${ch}" \; refresh-client -S \; show -gqv @busy_any 2>/dev/null || true)"
		last="${ch}"
		i=$(( (i + 1) % N ))
		while [ "${busy}" = "1" ]; do
			sleep "${SPIN_INTERVAL}"
			ch="${CHARS[$i]}"
			busy="$(tmux set -gq @spin "${ch}" \; refresh-client -S \; show -gqv @busy_any 2>/dev/null || true)"
			last="${ch}"
			i=$(( (i + 1) % N ))
		done
	done
}

case "${1:-start}" in
	__loop)
		loop
		;;
	__scan)
		scan_loop
		;;
	start)
		if is_running; then
			exit 0
		fi
		rm -f "${PIDFILE}"
		pkill -f 'tmux-agent-spinner.sh __' 2>/dev/null || true
		clear_spin
		nohup "$0" __loop >/dev/null 2>&1 &
		echo "$!" > "${PIDFILE}"
		;;
	stop)
		if is_running; then
			kill "$(cat "${PIDFILE}")" 2>/dev/null || true
		fi
		pkill -f 'tmux-agent-spinner.sh __' 2>/dev/null || true
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
