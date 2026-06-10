#!/usr/bin/env bash

set -eu

basename_token() {
	local token="${1:-}"
	token="${token%\"}"
	token="${token#\"}"
	token="${token%\'}"
	token="${token#\'}"
	token="${token%%[[:space:]]*}"
	token="${token##*/}"
	token="${token#-}"
	printf '%s' "${token}"
}

agent_from_basename() {
	case "$(basename_token "${1:-}" | tr '[:upper:]' '[:lower:]')" in
		.claude-code-wrapped | claude | claude-code) printf 'claude' ;;
		.codex-wrapped | codex) printf 'codex' ;;
		.opencode-wrapped | opencode | open-code) printf 'opencode' ;;
		.gemini-wrapped | gemini) printf 'gemini' ;;
		.cursor-agent-wrapped | cursor-agent) printf 'cursor' ;;
		.droid-wrapped | droid) printf 'droid' ;;
		.amp-wrapped | amp | amp-local) printf 'amp' ;;
		.copilot-wrapped | copilot | github-copilot | ghcs) printf 'copilot' ;;
		.grok-wrapped | grok | grok-build) printf 'grok' ;;
		.kiro-wrapped | kiro | kiro-cli) printf 'kiro' ;;
		.kimi-wrapped | kimi | kimi-code) printf 'kimi' ;;
		.cline-wrapped | cline) printf 'cline' ;;
		*) return 1 ;;
	esac
}

resolved_agent_from_path() {
	local token="${1:-}"
	[ -n "${token}" ] || return 1
	case "${token}" in
		*/*) ;;
		*) return 1 ;;
	esac
	[ -e "${token}" ] || return 1

	local dir base target
	dir="$(dirname "${token}")"
	base="$(basename "${token}")"
	dir="$(cd "${dir}" 2>/dev/null && pwd -P)" || return 1

	while [ -L "${dir}/${base}" ]; do
		target="$(readlink "${dir}/${base}")" || return 1
		case "${target}" in
			/*)
				dir="$(dirname "${target}")"
				base="$(basename "${target}")"
				;;
			*)
				base="$(basename "${target}")"
				dir="$(cd "${dir}/$(dirname "${target}")" 2>/dev/null && pwd -P)" || return 1
				;;
		esac
	done

	agent_from_basename "${base}"
}

agent_from_token() {
	local token="${1:-}"
	[ -n "${token}" ] || return 1
	agent_from_basename "${token}" || resolved_agent_from_path "${token}"
}

option_takes_value() {
	case "${1:-}" in
		-r | --require | --loader | --import | --experimental-loader | --inspect-port | -W | -X | -S | -L | -o)
			return 0
			;;
		*) return 1 ;;
	esac
}

script_arg_agent() {
	local runtime="$1"
	shift
	local arg
	while [ "$#" -gt 0 ]; do
		arg="$1"
		shift
		case "${arg}" in
			--)
				[ "$#" -gt 0 ] || return 1
				agent_from_token "$1"
				return
				;;
			-c | -e | -p | --eval | --print | --eval=* | --print=*)
				return 1
				;;
			-m)
				[ "${runtime}" = "python" ] || [ "${runtime}" = "python3" ] || continue
				return 1
				;;
			-*)
				if option_takes_value "${arg}" && [ "$#" -gt 0 ]; then
					shift
				fi
				continue
				;;
			*)
				agent_from_token "${arg}"
				return
				;;
		esac
	done
	return 1
}

identify_process() {
	local comm="${1:-}"
	local args="${2:-}"
	local argv0 runtime

	if agent_from_token "${comm}"; then
		return 0
	fi

	argv0="${args%%[[:space:]]*}"
	if agent_from_token "${argv0}"; then
		return 0
	fi

	runtime="$(basename_token "${argv0:-${comm}}" | tr '[:upper:]' '[:lower:]')"
	case "${runtime}" in
		node | bun | python | python3 | sh | bash | zsh | fish)
			# shellcheck disable=SC2086
			set -- ${args}
			[ "$#" -gt 0 ] && shift
			script_arg_agent "${runtime}" "$@"
			return
			;;
	esac

	return 1
}

process_rows() {
	if [ -n "${GMUX_AGENT_PROCESS_TABLE:-}" ]; then
		cat "${GMUX_AGENT_PROCESS_TABLE}"
	else
		ps -axo pid=,ppid=,pgid=,tpgid=,comm=,args= | awk '{
			pid=$1; ppid=$2; pgid=$3; tpgid=$4; comm=$5;
			$1=$2=$3=$4=$5="";
			sub(/^[[:space:]]+/, "", $0);
			printf "%s\t%s\t%s\t%s\t%s\t%s\n", pid, ppid, pgid, tpgid, comm, $0
		}'
	fi
}

pane_process_rows() {
	local pane_pid="$1"
	process_rows | awk -F '\t' -v root="${pane_pid}" '
		{
			pid=$1; ppid=$2
			rows[pid]=$0
			parent[pid]=ppid
			if (pid == root) {
				root_tpgid=$4
			}
		}
		END {
			for (pid in rows) {
				cur=pid
				while (cur != "" && cur != "0") {
					if (cur == root) {
						if (root_tpgid == "" || root_tpgid == "0" || root_tpgid == "-1" || rows[pid] ~ "^[^\t]+\t[^\t]+\t" root_tpgid "\t") {
							print rows[pid]
						}
						break
					}
					cur=parent[cur]
				}
			}
		}
	'
}

pane_agent() {
	local pane_pid="$1"
	local agent
	while IFS=$'\t' read -r _pid _ppid _pgid _tpgid comm args; do
		if agent="$(identify_process "${comm}" "${args}")"; then
			printf '%s\n' "${agent}"
			return 0
		fi
	done < <(pane_process_rows "${pane_pid}")
	return 1
}

screen_content() {
	local pane_id="$1"
	if [ -n "${GMUX_AGENT_SCREEN_FILE:-}" ]; then
		cat "${GMUX_AGENT_SCREEN_FILE}"
	else
		tmux capture-pane -p -J -t "${pane_id}" 2>/dev/null || true
	fi
}

pane_title() {
	local pane_id="$1"
	if [ -n "${GMUX_AGENT_PANE_TITLE:-}" ]; then
		printf '%s' "${GMUX_AGENT_PANE_TITLE}"
	else
		tmux display-message -p -t "${pane_id}" "#{pane_title}" 2>/dev/null || true
	fi
}

# Multibyte glyphs matched as alternations under LC_ALL=C — bracket classes
# of multibyte chars silently fail on C-locale grep (Docker) and BSD grep.
has_working_title() {
	local braille=$'\xe2[\xa0-\xa3][\x80-\xbf]'
	printf '%s' "${1:-}" | LC_ALL=C grep -qE "^((${braille})+|◐|◓|◑|◒|◔|◕|[|/\\-]) "
}

# Permission/confirm prompts mean the agent is waiting on the user, not
# working — they win over interrupt footers that share the same dialog.
has_blocked_screen() {
	local lower
	lower="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
	if printf '%s' "${lower}" | LC_ALL=C grep -qE 'press enter to confirm or esc to cancel|waiting for permission|waiting for approval|waiting for user confirmation|permission required|requesting approval|requires approval|let cline use this tool'; then
		return 0
	fi
	if printf '%s' "${lower}" | LC_ALL=C grep -qE 'do you want to proceed|would you like to proceed'; then
		printf '%s' "${lower}" | LC_ALL=C grep -qE '1\. yes|❯' && return 0
	fi
	return 1
}

has_working_screen() {
	local lower
	lower="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
	printf '%s' "${lower}" | LC_ALL=C grep -Eq 'esc to interrupt|ctrl\+c to interrupt|esc.*interrupt|esc to cancel|ctrl\+c to stop|esc to stop|esc again to cancel|ctrl\+c cancel|kiro is working|• working \('
}

# Spinner glyph at line start followed by an activity word. Braille frames
# (opencode/cursor/droid/grok) are matched as UTF-8 bytes (U+2800-U+28FF)
# under LC_ALL=C so every frame works on BSD and GNU grep alike.
has_spinner_screen() {
	local content="${1:-}"
	local braille=$'\xe2[\xa0-\xa3][\x80-\xbf]'
	if printf '%s\n' "${content}" \
		| LC_ALL=C grep -E "^[[:space:]]*(${braille})+[[:space:]]+[A-Za-z]" \
		| LC_ALL=C grep -qiE '[a-z]ing([^a-z]|$)|thinking|working|loading'; then
		return 0
	fi
	# Claude-style glyph + verb + ellipsis ("✻ Thinking…"); kimi moon phases.
	local glyphs='·|✱|✲|✳|✴|✵|✶|✷|✸|✹|✺|✻|✼|✽|✾|✿|❀|❁|❂|❃|❇|❈|❉|❊|❋|✢|✣|✤|✥|✦|✧|✨|⊛|⊕|⊙|◉|◎|◍|◔|◑|◕|⬡|⬢|🌕|🌖|🌗|🌘|🌑|🌒|🌓|🌔'
	printf '%s\n' "${content}" | LC_ALL=C grep -qE "^[[:space:]]*(${glyphs})[[:space:]]+[A-Za-z].*(…|\.\.\.)"
}

pane_state() {
	local pane_id="$1"
	local pane_pid="$2"
	if ! pane_agent "${pane_pid}" >/dev/null; then
		printf 'unknown\n'
		return 0
	fi
	if has_working_title "$(pane_title "${pane_id}")"; then
		printf 'working\n'
		return 0
	fi
	local content
	content="$(screen_content "${pane_id}")"
	if has_blocked_screen "${content}"; then
		printf 'idle\n'
		return 0
	fi
	if has_working_screen "${content}" || has_spinner_screen "${content}"; then
		printf 'working\n'
	else
		printf 'idle\n'
	fi
}

case "${1:-}" in
	identify-process)
		identify_process "${2:-}" "${3:-}" || exit 1
		;;
	pane-agent)
		pane_agent "${2:-}" || exit 1
		;;
	pane-state)
		pane_state "${2:-}" "${3:-}"
		;;
	*)
		echo "usage: $0 identify-process <comm> <args> | pane-agent <pane_pid> | pane-state <pane_id> <pane_pid>" >&2
		exit 2
		;;
esac
