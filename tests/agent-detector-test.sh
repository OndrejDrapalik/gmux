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

# New harness process names
assert_success "${DETECTOR}" identify-process gemini "gemini"
assert_success "${DETECTOR}" identify-process cursor-agent "cursor-agent chat"
assert_success "${DETECTOR}" identify-process droid "droid"
assert_success "${DETECTOR}" identify-process amp "amp --dangerously-allow-all"
assert_success "${DETECTOR}" identify-process copilot "copilot"
assert_success "${DETECTOR}" identify-process node "node /usr/local/bin/grok"
assert_success "${DETECTOR}" identify-process kiro-cli "kiro-cli"
assert_success "${DETECTOR}" identify-process kimi "kimi-code"
assert_success "${DETECTOR}" identify-process cline "cline task"
assert_failure "${DETECTOR}" identify-process cursor "cursor ."
assert_failure "${DETECTOR}" identify-process amped "amped"

# pane-state fixtures: one agent process under the pane, screen injected.
state_for() {
	local comm="$1" args="$2" content="$3" title="${4:-}"
	printf '100\t1\t100\t200\tzsh\t-zsh\n200\t100\t200\t200\t%s\t%s\n' "${comm}" "${args}" >"${fixture}"
	printf '%s\n' "${content}" >"${screen}"
	GMUX_AGENT_PROCESS_TABLE="${fixture}" GMUX_AGENT_SCREEN_FILE="${screen}" \
		GMUX_AGENT_PANE_TITLE="${title:-Task Name}" "${DETECTOR}" pane-state "%1" 100
}

assert_state() {
	local expected="$1" comm="$2"
	shift 2
	local got
	got="$(state_for "${comm}" "$@")"
	[ "${got}" = "${expected}" ] || fail "expected ${expected} for ${comm}, got ${got}"
}

# claude: glyph spinner + verb + ellipsis, interrupt footer, blocked prompt
assert_state working claude "claude" "✻ Cogitating… (2s · 1.2k tokens)"
assert_state working claude "claude" "running tests
esc to interrupt"
assert_state idle claude "claude" "❯ "
assert_state idle claude "claude" "Do you want to proceed?
❯ 1. Yes
  2. No"
assert_state idle claude "claude" "Which option?
❯ 1. /docs route, render README
Enter to select · ↑/↓ to navigate · n to add notes · Esc to cancel"

# codex: working header, confirm dialog stays idle
assert_state working codex "codex" "• Working (8s • esc to interrupt)"
assert_state idle codex "codex" "press enter to confirm or esc to cancel"
assert_state idle codex "codex" "› "

# opencode: braille spinner in screen content, dotted footer ("esc interrupt", no "to")
assert_state working opencode "opencode run" "⠹ working"
assert_state working opencode "opencode run" "·········· esc interrupt"
assert_state working opencode "opencode run" "⠧ Generating response"
assert_state idle opencode "opencode run" "> "
assert_state idle opencode "opencode run" "△ Permission required
esc dismiss  enter confirm  ↑↓ select"

# Transcript quoting busy chrome (working on the spinner itself inside an
# agent) must not read as busy — only the bottom rows count.
transcript_quote="$(printf 'discussing the gmux spinner:\nthe footer says esc to interrupt when busy\nframes are ⠹ working glyphs\n%.0s\n' 1)
$(printf '~\n%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)
> "
assert_state idle opencode "opencode run" "${transcript_quote}"
assert_state working opencode "opencode run" "old chat line
$(printf '~\n%.0s' 1 2 3 4 5 6 7 8 9 10)
·········· esc interrupt"

# gemini
assert_state working gemini "gemini" "esc to cancel"
assert_state idle gemini "gemini" "Type your message"
assert_state idle gemini "gemini" "Waiting for user confirmation
esc to cancel"

# droid
assert_state working droid "droid" "⠼ Reading files
esc to stop"
assert_state idle droid "droid" "ready"

# kiro
assert_state working kiro-cli "kiro-cli" "Kiro is working"
assert_state idle kiro-cli "kiro-cli" "requires approval
yes, single permission"

# kimi: moon phase spinner
assert_state working kimi "kimi" "🌖 Thinking..."
assert_state idle kimi "kimi" "ready for input"

# cursor-agent: braille + -ing verb, hex spinner
assert_state working cursor-agent "cursor-agent" "⠛ Grepping"
assert_state working cursor-agent "cursor-agent" "⬢ Running…"
assert_state idle cursor-agent "cursor-agent" "Add a follow-up"

# amp / copilot
assert_state working amp "amp" "esc to cancel"
assert_state idle amp "amp" "waiting for approval
approve  deny with feedback"
assert_state working copilot "copilot" "esc again to cancel"
assert_state idle copilot "copilot" "ctrl+c to quit"

# transcript bullets must not read as spinners
assert_state idle claude "claude" "· plain bullet note
- another line"

echo "ok - agent detector"
