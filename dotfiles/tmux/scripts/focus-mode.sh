#!/usr/bin/env bash
# Open the active pane in a popup tmux client, then restore zoom state on exit.

set -euo pipefail

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

tmux_bin="${TMUX_BIN:-tmux}"

session="${GMUX_FOCUS_SESSION:-${1:-}}"
window="${GMUX_FOCUS_WINDOW:-${2:-}}"
window_index="${GMUX_FOCUS_WINDOW_INDEX:-${3:-}}"
pane="${GMUX_FOCUS_PANE:-${4:-}}"
socket="${GMUX_FOCUS_SOCKET:-${5:-}}"

tmux_cmd=("${tmux_bin}")
if [ -n "${socket}" ]; then
  tmux_cmd+=("-S" "${socket}")
fi

run_tmux() {
  "${tmux_cmd[@]}" "$@"
}

[ -n "${session}" ] || session="$(run_tmux display-message -p '#{session_name}')"
[ -n "${window}" ] || window="$(run_tmux display-message -p '#{window_id}')"
[ -n "${window_index}" ] || window_index="$(run_tmux display-message -p -t "${window}" '#{window_index}')"
[ -n "${pane}" ] || pane="$(run_tmux display-message -p '#{pane_id}')"
[ -n "${socket}" ] || socket="$(run_tmux display-message -p '#{socket_path}')"

run_tmux has-session -t "${session}" 2>/dev/null || die "session not found: ${session}"
run_tmux list-panes -a -F '#{pane_id}' | grep -Fx "${pane}" >/dev/null || die "pane not found: ${pane}"

was_zoomed="$(run_tmux display-message -p -t "${window}" '#{window_zoomed_flag}' 2>/dev/null || printf '0')"
focus_session="${GMUX_FOCUS_SESSION_NAME:-__gmux_focus_${pane#%}_$$}"

cleanup() {
  run_tmux kill-session -t "${focus_session}" 2>/dev/null || true

  if [ "${was_zoomed}" = "0" ]; then
    zoomed="$(run_tmux display-message -p -t "${window}" '#{window_zoomed_flag}' 2>/dev/null || printf '0')"
    if [ "${zoomed}" = "1" ]; then
      run_tmux resize-pane -Z -t "${pane}" 2>/dev/null || true
    fi
  fi

  run_tmux select-pane -t "${pane}" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

run_tmux kill-session -t "${focus_session}" 2>/dev/null || true
run_tmux new-session -d -t "${session}" -s "${focus_session}"
run_tmux select-window -t "${focus_session}:${window_index}"
run_tmux select-pane -t "${pane}"

if [ "${was_zoomed}" = "0" ]; then
  run_tmux resize-pane -Z -t "${pane}"
fi

if [ "${GMUX_FOCUS_ATTACH:-1}" = "0" ]; then
  exit 0
fi

attach_cmd=("${tmux_bin}")
if [ -n "${socket}" ]; then
  attach_cmd+=("-S" "${socket}")
fi

env -u TMUX "${attach_cmd[@]}" attach-session -t "${focus_session}"
