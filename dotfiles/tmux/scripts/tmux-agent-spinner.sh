#!/usr/bin/env bash

# Lean braille spinner for tmux.
# Two processes: __scan (busy detection, every SCAN_INTERVAL, hysteresis on idle)
# and __loop (pure animation at ~8fps, one tmux fork per frame, never blocks on scans).
# Scanner writes per-window @busy + global @busy_any; animation only reads @busy_any.

set -u

PIDFILE="/tmp/tmux-agent-spinner.pid"
LOCKDIR="/tmp/tmux-agent-spinner.lock"

# Serializes start/stop so overlapping restarts (tmux.conf run-shell -b can
# fire several at once) can't interleave pkill/spawn and double-spawn.
# Lock held >5s is presumed stale (holder crashed) and stolen.
acquire_lock() {
	local tries=0
	until mkdir "${LOCKDIR}" 2>/dev/null; do
		tries=$(( tries + 1 ))
		if [ "${tries}" -ge 50 ]; then
			rm -rf "${LOCKDIR}"
			tries=0
			continue
		fi
		sleep 0.1
	done
	trap 'rm -rf "${LOCKDIR}"' EXIT
}

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
SCAN_INTERVAL=1
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

	# Full per-harness detection (process tree + screen chrome) lives in the
	# detector. The caller prefilters local agent panes and shares one ps
	# snapshot per scan, so this stays one capture-pane per local agent pane.
	[ -x "${AGENT_DETECT}" ] || return 1
	[ "$(GMUX_AGENT_ASSUME_PANE_AGENT=1 GMUX_AGENT_PANE_TITLE="${pane_title}" "${AGENT_DETECT}" pane-state "${pane_id}" "${pane_pid}" 2>/dev/null)" = "working" ]
}

agent_pane_ids() {
	local ps_table="$1"
	tmux list-panes -a -F '#{pane_id}	#{pane_pid}' 2>/dev/null \
		| awk -F '\t' '
			function basename_token(token) {
				gsub(/^["'\'']|["'\'']$/, "", token)
				sub(/[[:space:]].*$/, "", token)
				sub(/^.*\//, "", token)
				sub(/^-/, "", token)
				return tolower(token)
			}
			function is_agent_token(token) {
				token = basename_token(token)
				return token ~ /^(\.claude-code-wrapped|codex-aarch64-[^[:space:]\/]*|codex-x86_64-[^[:space:]\/]*|claude|claude-code|\.codex-wrapped|codex|\.opencode-wrapped|opencode|open-code|\.gemini-wrapped|gemini|\.cursor-agent-wrapped|cursor-agent|\.droid-wrapped|droid|\.amp-wrapped|amp|amp-local|\.copilot-wrapped|copilot|github-copilot|ghcs|\.grok-wrapped|grok|grok-build|\.kiro-wrapped|kiro|kiro-cli|\.kimi-wrapped|kimi|kimi-code|\.cline-wrapped|cline)$/
			}
			function is_agent(comm, args, first) {
				first = args
				sub(/[[:space:]].*$/, "", first)
				return is_agent_token(comm) || is_agent_token(first) || args ~ /(^|[[:space:]\/])(\.claude-code-wrapped|codex-aarch64-[^[:space:]\/]*|codex-x86_64-[^[:space:]\/]*|claude|claude-code|\.codex-wrapped|codex|\.opencode-wrapped|opencode|open-code|\.gemini-wrapped|gemini|\.cursor-agent-wrapped|cursor-agent|\.droid-wrapped|droid|\.amp-wrapped|amp|amp-local|\.copilot-wrapped|copilot|github-copilot|ghcs|\.grok-wrapped|grok|grok-build|\.kiro-wrapped|kiro|kiro-cli|\.kimi-wrapped|kimi|kimi-code|\.cline-wrapped|cline)([[:space:]]|$)/
			}
			FNR == NR {
				pane_by_pid[$2] = $1
				next
			}
			{
				pid = $1
				ppid = $2
				parent[pid] = ppid
				pgid[pid] = $3
				tpgid[pid] = $4
				comm[pid] = $5
				args = $0
				sub(/^[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t/, "", args)
				argv[pid] = args
				next
			}
			END {
				for (pid in pane_by_pid) {
					root_tpgid[pid] = tpgid[pid]
				}
				for (pid in parent) {
					if (!is_agent(comm[pid], argv[pid])) {
						continue
					}
					cur = pid
					while (cur != "" && cur != "0") {
						if (cur in pane_by_pid) {
							if (root_tpgid[cur] == "" || root_tpgid[cur] == "0" || root_tpgid[cur] == "-1" || pgid[pid] == root_tpgid[cur]) {
								print pane_by_pid[cur]
							}
							break
						}
						cur = parent[cur]
					}
				}
			}
		' - "${ps_table}" | sort -u
}

update_window_state() {
	local window_id window_name pane_id pane_pid pane_title
	local busy_now prev_busy prev_miss miss any_busy
	local busy_windows=" "
	local agent_panes=" "
	local agent_windows=" "
	local -a batch=()

	# One ps snapshot per scan, shared by every detector call below. The
	# scanner provides a reusable file (PS_TABLE) so a 1s scan cadence does
	# not churn a new mktemp per scan; one-shot callers fall back to mktemp.
	local ps_table="${PS_TABLE:-}" own_table=0
	if [ -z "${ps_table}" ]; then
		ps_table="$(mktemp)"
		own_table=1
	fi
	ps -axo pid=,ppid=,pgid=,tpgid=,comm=,args= 2>/dev/null | awk '{
		pid=$1; ppid=$2; pgid=$3; tpgid=$4; comm=$5;
		$1=$2=$3=$4=$5="";
		sub(/^[[:space:]]+/, "", $0);
		printf "%s\t%s\t%s\t%s\t%s\t%s\n", pid, ppid, pgid, tpgid, comm, $0
	}' >"${ps_table}"
	export GMUX_AGENT_PROCESS_TABLE="${ps_table}"
	agent_panes="$(agent_pane_ids "${ps_table}" | awk '{ printf " %s ", $0 }')"

	while IFS=$'\t' read -r window_id pane_id pane_pid pane_title; do
		case "${busy_windows}" in *" ${window_id} "*) continue ;; esac
		case "${agent_panes}" in
			*" ${pane_id} "*)
				case "${agent_windows}" in
					*" ${window_id} "*) ;;
					*) agent_windows="${agent_windows}${window_id} " ;;
				esac
				if pane_is_busy "${pane_id}" "${pane_pid}" "${pane_title}"; then
					busy_windows="${busy_windows}${window_id} "
				fi
				continue
				;;
		esac
		# Remote agents can only advertise activity through OSC pane titles.
		# For local agent panes, stale Braille titles must not pin busy forever.
		if printf "%s" "${pane_title}" | grep -qE "${TITLE_BUSY_RE}"; then
			busy_windows="${busy_windows}${window_id} "
		fi
	done < <(tmux list-panes -a -F '#{window_id}	#{pane_id}	#{pane_pid}	#{pane_title}' 2>/dev/null || true)

	unset GMUX_AGENT_PROCESS_TABLE
	[ "${own_table}" -eq 1 ] && rm -f "${ps_table}"

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
			# Hysteresis bridges short detection gaps (tool-call boundaries)
			# only while a live local agent process remains in the window.
			# Process gone (or remote title cleared) is definitive: idle now.
			case "${agent_windows}" in
				*" ${window_id} "*)
					miss=$(( ${prev_miss:-0} + 1 ))
					;;
				*)
					miss="${MISS_LIMIT}"
					;;
			esac
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
	# Wake the animation loop whenever anything is busy — it blocks on this
	# channel instead of polling. Signalling with no waiter just marks the
	# channel woken (never lost to a race), and signalling every busy scan
	# self-heals a missed wake at zero cost: it rides the same batched call.
	if [ "${any_busy}" = "1" ]; then
		batch+=(\; wait-for -S gmux-spinner-wake)
	fi
	tmux "${batch[@]}" 2>/dev/null || true
}

scan_loop() {
	PS_TABLE="$(mktemp)"
	# TERM/INT must exit explicitly — a bare cleanup trap swallows the
	# signal and the loop keeps running, making the scanner unkillable.
	trap 'rm -f "${PS_TABLE}"' EXIT
	trap 'exit 0' TERM INT
	while true; do
		if ! tmux has-session 2>/dev/null; then
			exit 0
		fi
		# Orphan self-check: parent __loop gone means this scanner leaked.
		if [ "$(ps -o ppid= -p $$ 2>/dev/null | tr -d '[:space:]')" = "1" ]; then
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
	local scan_pid="" waiter_pid="" i ch busy last
	# Trap before fork: a signal landing between spawn and trap install
	# would otherwise orphan the scanner.
	trap 'kill "${scan_pid}" "${waiter_pid}" 2>/dev/null; exit 0' EXIT TERM INT
	"$0" __scan &
	scan_pid=$!

	i=0
	last=""
	while true; do
		# Singleton invariant: the pidfile names the one legitimate loop.
		# A loop that lost ownership (newer start ran) exits, taking its
		# scanner with it via the trap.
		if [ "$(cat "${PIDFILE}" 2>/dev/null)" != "$$" ]; then
			exit 0
		fi
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
			# Block until the scanner signals idle→busy: zero CPU while idle,
			# instant spin-up. Run the blocking client in the background and
			# `wait` on it — bash defers signal traps while a foreground
			# command runs, so a foreground wait-for would make this loop
			# unkillable by TERM for as long as it stays idle.
			tmux wait-for gmux-spinner-wake 2>/dev/null &
			waiter_pid=$!
			wait "${waiter_pid}" || sleep 2
			waiter_pid=""
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
	__scan-once)
		update_window_state
		;;
	start)
		acquire_lock
		if is_running; then
			exit 0
		fi
		rm -f "${PIDFILE}"
		pkill -f 'tmux-agent-spinner.sh __' 2>/dev/null || true
		clear_spin
		# Child writes its own pid before exec'ing into __loop, so the
		# pidfile is guaranteed populated before the loop's singleton
		# check ever runs. The trailing comment token keeps the pre-exec
		# cmdline matchable by stop's pkill pattern — without it a child
		# caught mid-spawn is invisible to pkill and leaks.
		nohup bash -c 'echo "$$" >"$1"; exec "$0" __loop # tmux-agent-spinner.sh __spawn' "$0" "${PIDFILE}" >/dev/null 2>&1 &
		# Hold the lock until the child has exec'd (pidfile holds a live
		# pid whose cmdline matches __loop) so a following stop sees it.
		for _ in 1 2 3 4 5 6 7 8 9 10; do
			is_running && break
			sleep 0.1
		done
		;;
	stop)
		acquire_lock
		if is_running; then
			kill "$(cat "${PIDFILE}")" 2>/dev/null || true
		fi
		pkill -f 'tmux-agent-spinner.sh __' 2>/dev/null || true
		# Wake any loop parked in wait-for so its TERM trap can fire,
		# then escalate to KILL for whatever still ignores TERM.
		tmux wait-for -S gmux-spinner-wake 2>/dev/null || true
		sleep 0.3
		pkill -9 -f 'tmux-agent-spinner.sh __' 2>/dev/null || true
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
		echo "usage: $0 [start|stop|restart|status|__scan-once]" >&2
		exit 1
		;;
esac
