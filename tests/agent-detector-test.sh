#!/usr/bin/env bash

set -eu

ROOT="$(cd "$(dirname "$0")/.." >/dev/null && pwd)"
DETECTOR="${ROOT}/dotfiles/tmux/scripts/tmux-agent-detect.sh"

fail() {
	echo "not ok - $*" >&2
	exit 1
}

assert_success() {
	"$@" >/dev/null || fail "expected success: $*"
}

assert_failure() {
	if "$@" >/dev/null 2>&1; then
		fail "expected failure: $*"
	fi
}

fixture="$(mktemp)"
screen="$(mktemp)"
symlink_dir="$(mktemp -d)"
trap 'rm -f "${fixture}" "${screen}"; rm -rf "${symlink_dir}"' EXIT

assert_success "${DETECTOR}" identify-process codex "codex --yolo"
assert_success "${DETECTOR}" identify-process node "node /tmp/bin/codex --model gpt-5"
assert_success "${DETECTOR}" identify-process python3 "python3 /tmp/opencode --help"
assert_success "${DETECTOR}" identify-process sh "/bin/sh /tmp/claude-code"
assert_success "${DETECTOR}" identify-process .codex-wrapped "/nix/store/example/bin/codex --model gpt-5"
assert_success "${DETECTOR}" identify-process opencode "opencode run"
touch "${symlink_dir}/codex"
ln -s "${symlink_dir}/codex" "${symlink_dir}/agent"
assert_success "${DETECTOR}" identify-process agent "${symlink_dir}/agent --model gpt-5"

assert_failure "${DETECTOR}" identify-process python3 "python3 -c 'import time' /tmp/codex"
assert_failure "${DETECTOR}" identify-process node "node -e 'setTimeout(() => {}, 60)' /tmp/opencode"
assert_failure "${DETECTOR}" identify-process bash "bash -c 'sleep 60' /tmp/claude"
assert_failure "${DETECTOR}" identify-process my-codex-helper "/tmp/my-codex-helper"
assert_failure "${DETECTOR}" identify-process codex-helper "codex-helper"

cat >"${fixture}" <<'EOF'
100	1	100	200	zsh	-zsh
200	100	200	200	node	node /tmp/bin/codex --model gpt-5
300	100	300	200	opencode	opencode run
EOF
GMUX_AGENT_PROCESS_TABLE="${fixture}" assert_success "${DETECTOR}" pane-agent 100

cat >"${fixture}" <<'EOF'
100	1	100	200	zsh	-zsh
200	100	200	200	node	node /tmp/bin/codex --model gpt-5
300	100	300	200	opencode	opencode run
EOF
printf 'thinking\nesc to interrupt\n' >"${screen}"
state="$(GMUX_AGENT_PROCESS_TABLE="${fixture}" GMUX_AGENT_SCREEN_FILE="${screen}" "${DETECTOR}" pane-state "%1" 100)"
[ "${state}" = "working" ] || fail "expected working state, got ${state}"

printf 'idle screen\n' >"${screen}"
state="$(GMUX_AGENT_PROCESS_TABLE="${fixture}" GMUX_AGENT_SCREEN_FILE="${screen}" GMUX_AGENT_PANE_TITLE="◐ Thinking" "${DETECTOR}" pane-state "%1" 100)"
[ "${state}" = "working" ] || fail "expected title working state, got ${state}"

state="$(GMUX_AGENT_PROCESS_TABLE="${fixture}" GMUX_AGENT_SCREEN_FILE="${screen}" GMUX_AGENT_PANE_TITLE="Task Name" "${DETECTOR}" pane-state "%1" 100)"
[ "${state}" = "idle" ] || fail "expected idle state, got ${state}"

cat >"${fixture}" <<'EOF'
100	1	100	300	zsh	-zsh
200	100	200	300	node	node /tmp/bin/codex --model gpt-5
300	100	300	300	opencode	opencode run
EOF
GMUX_AGENT_PROCESS_TABLE="${fixture}" assert_success "${DETECTOR}" pane-agent 100

cat >"${fixture}" <<'EOF'
100	1	100	100	zsh	-zsh
200	100	200	100	python3	python3 -c import_time /tmp/codex
EOF
GMUX_AGENT_PROCESS_TABLE="${fixture}" assert_failure "${DETECTOR}" pane-agent 100

echo "ok - agent detector"
