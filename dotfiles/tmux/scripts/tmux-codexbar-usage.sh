#!/usr/bin/env bash

set -u

PIDFILE="/tmp/tmux-codexbar-usage.pid"
INTERVAL="${TMUX_CODEXBAR_USAGE_INTERVAL:-300}"
WEB_TIMEOUT="${TMUX_CODEXBAR_USAGE_WEB_TIMEOUT:-8}"
KILL_TIMEOUT="${TMUX_CODEXBAR_USAGE_KILL_TIMEOUT:-25}"

find_codexbar() {
	local candidate
	for candidate in \
		"${CODEXBAR_CLI:-}" \
		/opt/homebrew/bin/codexbar \
		/usr/local/bin/codexbar \
		/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI
	do
		if [ -n "${candidate}" ] && [ -x "${candidate}" ]; then
			printf '%s\n' "${candidate}"
			return 0
		fi
	done
	return 1
}

CODEXBAR="$(find_codexbar || true)"

set_usage() {
	tmux set -gq @codexbar_usage "$1" >/dev/null 2>&1 || true
	tmux refresh-client -S >/dev/null 2>&1 || true
}

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
	ps -p "${pid}" -o command= 2>/dev/null | grep -q "tmux-codexbar-usage.sh __loop"
}

primary_percent() {
	local provider="$1"
	local source="$2"
	local json value

	if [ -z "${CODEXBAR}" ] || ! command -v jq >/dev/null 2>&1; then
		return 1
	fi

	json="$(
		perl -e 'alarm shift; exec @ARGV' "${KILL_TIMEOUT}" \
			"${CODEXBAR}" usage \
			--format json \
			--provider "${provider}" \
			--source "${source}" \
			--web-timeout "${WEB_TIMEOUT}" 2>/dev/null
	)" || return 1

	value="$(printf '%s' "${json}" | jq -r '.[0].usage.primary.usedPercent // empty' 2>/dev/null | head -n 1)" || return 1
	if [ -z "${value}" ]; then
		return 1
	fi

	awk 'BEGIN { printf "%.0f%%", ARGV[1] + 0 }' "${value}"
}

claude_daily_spend_value() {
	local cache today

	if ! command -v jq >/dev/null 2>&1; then
		return 1
	fi

	cache="${CODEXBAR_CLAUDE_COST_CACHE:-${HOME}/Library/Caches/CodexBar/cost-usage/claude-v4.json}"
	if [ ! -r "${cache}" ]; then
		return 1
	fi

	today="$(date +%F)"
	jq -r --arg today "${today}" '
		(.days[$today] // {}) as $models |
		(reduce ($models | to_entries[]) as $model (0; . + (($model.value[4] // 0) | tonumber))) / 1000000000
	' "${cache}" 2>/dev/null
}

codex_daily_spend_value() {
	local cache pricing today

	if ! command -v jq >/dev/null 2>&1; then
		return 1
	fi

	cache="${CODEXBAR_CODEX_COST_CACHE:-${HOME}/Library/Caches/CodexBar/cost-usage/codex-v8.json}"
	pricing="${CODEXBAR_MODEL_PRICING_CACHE:-${HOME}/Library/Caches/CodexBar/model-pricing/models-dev-v1.json}"
	if [ ! -r "${cache}" ] || [ ! -r "${pricing}" ]; then
		return 1
	fi

	today="$(date +%F)"
	jq -n -r --arg today "${today}" --slurpfile usage "${cache}" --slurpfile pricing "${pricing}" '
		($usage[0].days[$today] // {}) as $models |
		($pricing[0].catalog.providers.openai.models // {}) as $prices |
		reduce ($models | to_entries[]) as $model (0;
			($model.value[0] // 0 | tonumber) as $input |
			($model.value[1] // 0 | tonumber) as $cached |
			($model.value[2] // 0 | tonumber) as $output |
			($prices[$model.key].cost // {}) as $cost |
			(($input - $cached) | if . > 0 then . else 0 end) as $uncached |
			. + (($uncached * (($cost.input // 0) / 1000000))
				+ ($cached * (($cost.cache_read // 0) / 1000000))
				+ ($output * (($cost.output // 0) / 1000000)))
		)
	' 2>/dev/null
}

cursor_spend_value() {
	local json

	if [ -z "${CODEXBAR}" ] || ! command -v jq >/dev/null 2>&1; then
		return 1
	fi

	json="$(
		perl -e 'alarm shift; exec @ARGV' "${KILL_TIMEOUT}" \
			"${CODEXBAR}" usage \
			--format json \
			--provider cursor \
			--source auto \
			--web-timeout "${WEB_TIMEOUT}" 2>/dev/null
	)" || return 1

	printf '%s' "${json}" | jq -r '.[0].usage.providerCost.used // 0' 2>/dev/null
}

daily_spend() {
	local claude codex cursor

	claude="$(claude_daily_spend_value || true)"
	codex="$(codex_daily_spend_value || true)"
	cursor="$(cursor_spend_value || true)"

	[ -n "${claude}" ] || claude="0"
	[ -n "${codex}" ] || codex="0"
	[ -n "${cursor}" ] || cursor="0"

	awk 'BEGIN { printf "$%.2f", ARGV[1] + ARGV[2] + ARGV[3] }' "${claude}" "${codex}" "${cursor}"
}

update_once() {
	local cdx cla cur spend

	cdx="$(primary_percent codex cli || true)"
	cla="$(primary_percent claude web || true)"
	cur="$(primary_percent cursor auto || true)"
	spend="$(daily_spend || true)"

	[ -n "${cdx}" ] || cdx="--"
	[ -n "${cla}" ] || cla="--"
	[ -n "${cur}" ] || cur="--"
	[ -n "${spend}" ] || spend="--"

	set_usage "cdx ${cdx} | cl ${cla} | cur ${cur} | spend ${spend}"
}

loop() {
	tmux set -gq @codexbar_usage_on "1" >/dev/null 2>&1 || true

	while true; do
		if [ -n "$(tmux list-clients 2>/dev/null || true)" ]; then
			update_once
		fi
		sleep "${INTERVAL}"
	done
}

case "${1:-start}" in
	__loop)
		loop
		;;
	once)
		update_once
		;;
	start)
		if is_running; then
			update_once
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
		tmux set -gq @codexbar_usage_on "0" >/dev/null 2>&1 || true
		tmux set -gq @codexbar_usage "cdx -- | cl -- | cur -- | spend --" >/dev/null 2>&1 || true
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
		tmux show -gqv @codexbar_usage 2>/dev/null || true
		;;
	*)
		echo "usage: $0 [start|stop|restart|status|once]" >&2
		exit 1
		;;
esac
