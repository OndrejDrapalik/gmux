#!/usr/bin/env bash

# Session navigator (prefix+a) — a herdr-style searchable session > window > pane
# tree in an fzf popup. Each pane shows its live agent state (working/idle/done/
# blocked) and agent name, fuzzy search, single-key state filters, a live pane
# preview, and Enter switches the attached client to that pane across sessions.
#
# Per-pane state is read with zero forks from the @pane_state / @pane_agent
# options published by the spinner daemon (tmux-agent-spinner.sh). Opening the
# navigator first runs one __scan-once so the tree is fresh even if the daemon
# is idle or stopped; filter changes only re-read the cached options.
#
# Usage:
#   session-navigator.sh [CURRENT_TARGET]              # interactive popup
#   session-navigator.sh --enumerate [--filter STATE] [CURRENT_TARGET]

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
SELF="${SCRIPT_DIR}/$(basename "$0")"
SPINNER="${GMUX_NAV_SPINNER:-${SCRIPT_DIR}/tmux-agent-spinner.sh}"

# Tab-delimited tree lines: "<rendered display>\t<switch target>".
# Header rows (session/window) carry an empty target so Enter on them is a no-op.
enumerate() {
	local filter="" current=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--filter)
				filter="${2:-}"
				shift 2
				;;
			*)
				current="$1"
				shift
				;;
		esac
	done

	local data
	data="$(tmux list-panes -a -F '#{session_name}	#{window_index}	#{window_name}	#{pane_index}	#{pane_current_command}	#{@pane_state}	#{@pane_agent}	#{session_id}:#{window_id}.#{pane_id}' 2>/dev/null || true)"
	[ -n "${data}" ] || return 0

	awk -F '\t' -v filter="${filter}" -v current="${current}" -v COL=40 '
		function esc()       { return sprintf("%c", 27) }
		function paint(c, t) { return esc() "[" c "m" t esc() "[0m" }
		function scolor(s) {
			if (s == "blocked") return "38;2;247;118;142"
			if (s == "working") return "38;2;224;175;104"
			if (s == "done")    return "38;2;125;207;255"
			if (s == "idle")    return "38;2;158;206;106"
			return "38;2;86;95;137"
		}
		function sglyph(s) {
			if (s == "blocked") return "\342\227\211"   # ◉
			if (s == "working") return "\342\240\271"   # ⠹
			if (s == "done")    return "\342\227\217"   # ●
			if (s == "idle")    return "\342\234\223"   # ✓
			return "\342\227\213"                       # ○
		}
		function pad(have,   p, s) {
			p = COL - have
			if (p < 1) p = 2
			s = ""
			while (p-- > 0) s = s " "
			return s
		}
		function activity(sess,   parts) {
			parts = ""
			if (sb[sess]) parts = parts (parts ? " \302\267 " : "") sb[sess] " blocked"
			if (sw[sess]) parts = parts (parts ? " \302\267 " : "") sw[sess] " working"
			if (sd[sess]) parts = parts (parts ? " \302\267 " : "") sd[sess] " done"
			return parts
		}
		function keep_pane(s) { return (filter == "" || s == filter) }

		BEGIN {
			ACCENT = "38;2;122;162;247"; DIM = "38;2;86;95;137"; TITLE = "38;2;192;202;245"
		}

		# pass 1 — tallies for headers and subtree-aware pruning
		FNR == NR {
			if ($1 ~ /^_focus_|^_popup/) next
			s = ($6 == "" ? "unknown" : $6)
			sess = $1; wkey = $1 SUBSEP $2
			septotal[sess]++; wintotal[wkey]++
			if (s == "blocked") sb[sess]++
			else if (s == "working") sw[sess]++
			else if (s == "done") sd[sess]++
			if (keep_pane(s)) { smatch[sess]++; wmatch[wkey]++ }
			next
		}

		# pass 2 — render
		{
			if ($1 ~ /^_focus_|^_popup/) next
			s = ($6 == "" ? "unknown" : $6)
			sess = $1; widx = $2; wname = $3; pidx = $4; cmd = $5; agent = $7; target = $8
			wkey = sess SUBSEP widx

			if (filter != "" && smatch[sess] == 0) next
			if (sess != lastsess) {
				lastsess = sess; lastwin = ""
				lbl = "\342\226\276 " sess                       # ▾ session
				cnt = " (" septotal[sess] ")"
				plain = lbl cnt
				meta = activity(sess)
				line = paint(ACCENT, "\342\226\276 ") paint(TITLE, sess) paint(DIM, cnt)
				if (meta != "") line = line pad(length(plain)) paint(DIM, meta)
				print line "\t"
			}

			if (filter != "" && wmatch[wkey] == 0) next
			if (wkey != lastwin) {
				lastwin = wkey
				lbl = "  \342\224\234\342\224\200 " widx ":" wname  #   ├─ idx:name
				meta = wintotal[wkey] " panes"
				line = paint(DIM, lbl)
				print line pad(length(lbl)) paint(DIM, meta) "\t"
			}

			if (filter != "" && s != filter) next

			# pane row
			cur = (target == current && current != "") ? "\342\227\206 " : "  "  # ◆ current
			if (agent != "") title = agent
			else if (cmd ~ /^(-?zsh|-?bash|-?sh|-?fish|tmux)$/) title = "pane " pidx
			else title = cmd
			glyph = sglyph(s)
			plain = "    " cur glyph " " title
			line = "    " paint(scolor(s), cur) paint(scolor(s), glyph) " " paint(TITLE, title)
			if (agent != "") meta = agent " \302\267 " s
			else meta = "shell"
			mcolor = (agent != "" ? scolor(s) : DIM)
			print line pad(length(plain)) paint(mcolor, meta) "\t" target
		}
	' <(printf '%s\n' "${data}") <(printf '%s\n' "${data}")
}

case "${1:-}" in
	--enumerate)
		shift
		enumerate "$@"
		exit 0
		;;
esac

command -v fzf >/dev/null 2>&1 || {
	tmux display-message "session-navigator: fzf not found" 2>/dev/null
	exit 1
}

CURRENT="${1:-}"

# Refresh the per-pane state cache so the tree is current even when the spinner
# daemon is idle or stopped. Best-effort; the enumerator falls back to whatever
# @pane_state already holds.
[ -x "${SPINNER}" ] && "${SPINNER}" __scan-once >/dev/null 2>&1 || true

enumerate "${CURRENT}" | fzf \
	--ansi \
	--delimiter='\t' \
	--with-nth=1 \
	--nth=1 \
	--no-multi \
	--reverse \
	--disabled \
	--pointer='→' \
	--prompt='[all] > ' \
	--header='enter switch · / search · b/w/i/d/a states · j/k move · esc close' \
	--color='fg:#c0caf5,bg:#1a1b26,hl:#7aa2f7,fg+:#c0caf5,bg+:#283457,hl+:#7dcfff,pointer:#7aa2f7,prompt:#7aa2f7,header:#565f89,border:#7aa2f7,gutter:#1a1b26' \
	--preview-window='right:55%:wrap,border-left' \
	--preview '[ -n {-1} ] && tmux capture-pane -ep -t {-1} 2>/dev/null' \
	--bind 'j:down' \
	--bind 'k:up' \
	--bind "b:reload(${SELF} --enumerate --filter blocked ${CURRENT})+change-prompt([blocked] > )" \
	--bind "w:reload(${SELF} --enumerate --filter working ${CURRENT})+change-prompt([working] > )" \
	--bind "i:reload(${SELF} --enumerate --filter idle ${CURRENT})+change-prompt([idle] > )" \
	--bind "d:reload(${SELF} --enumerate --filter done ${CURRENT})+change-prompt([done] > )" \
	--bind "a:reload(${SELF} --enumerate ${CURRENT})+change-prompt([all] > )" \
	--bind 'slash:unbind(a,b,d,i,w,j,k,slash)+enable-search+change-prompt(search> )' \
	--bind 'esc:abort' \
	--bind 'enter:become([ -n {-1} ] && tmux switch-client -t {-1} && tmux select-window -t {-1} && tmux select-pane -t {-1})'
