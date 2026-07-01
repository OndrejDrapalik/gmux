#!/usr/bin/env bash
# Focus Mode (prefix + F): spotlight the current pane in a 90% popup while the
# rest of the layout stays EXACTLY in place behind it.
#
# Mechanism: a session GROUPED to the current one gives the popup an independent
# current-window (the "linked session" trick). We spawn a placeholder ("ghost")
# pane in a temp window and SWAP it with the focused pane: the live pane lands in
# the temp window -- viewed ONLY by the popup, so it sizes cleanly to the popup
# (no clipping of bottom-anchored TUIs like Claude Code / Codex) -- while the
# ghost takes the focused pane's exact slot in the original window, so the
# background never reflows. On exit we swap back and kill the temp window.
# swap-pane preserves the layout, so no save/restore is needed.
#
# No -f ignore-size: the popup must DRIVE the temp window's size (window-size
# latest) so the pane fits the popup exactly. The popup's status bar is off (it
# already shows in the background). Restore runs from the bash trap (fires on
# prefix+F/Esc detach and popup-close SIGHUP); a hard SIGKILL is the only path
# that strands the live pane in the temp window (recover: tmux swap-pane).
set -euo pipefail

session="$(tmux display -p '#{session_name}')"
pane="$(tmux display -p '#{pane_id}')"
outer_client="$(tmux display -p '#{client_name}')"

grp="_focus_${pane#%}_$$"
ghost_pane=""
ghost_win=""
snapshot_file=""

shell_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

capture_snapshot() {
  target="$1"
  out="$2"
  tmux capture-pane -aepq -t "$target" >"$out" 2>/dev/null ||
    tmux capture-pane -ep -t "$target" >"$out" 2>/dev/null ||
    : >"$out"
}

snapshot_cmd() {
  snapshot_q="$(shell_quote "$1")"
  printf "printf '\\033[2J\\033[H\\033[0m'; cat %s 2>/dev/null; printf '\\033[0m'; exec sleep 2147483647" "$snapshot_q"
}

cleanup() {
  trap - EXIT HUP INT TERM
  restored_pane=""
  if [ -n "$ghost_pane" ]; then
    # The spotlighted pane (may differ from $pane after opt+` rotation) lives in
    # the temp window; swap whatever is there back home, then drop the ghost.
    live="$(tmux list-panes -t "$ghost_win" -F '#{pane_id}' 2>/dev/null | head -1 || true)"
    if [ -n "$live" ] && [ "$live" != "$ghost_pane" ]; then
      tmux swap-pane -s "$live" -t "$ghost_pane" 2>/dev/null || true
      tmux select-pane -t "$live" 2>/dev/null || true
      restored_pane="$live"
    fi
    tmux kill-window -t "$ghost_win" 2>/dev/null || true
  fi
  # Reap the disposable grouped session (idempotent; destroy-unattached may race).
  tmux kill-session -t "$grp" 2>/dev/null || true
  [ -n "$snapshot_file" ] && rm -f "$snapshot_file"
  if [ -n "$restored_pane" ]; then
    tmux run-shell -b "sleep 0.1; ~/.tmux/scripts/tmux-agent-spinner.sh __scan-once 2>/dev/null || true; tmux select-pane -t '$restored_pane' 2>/dev/null || true; tmux refresh-client -t '$outer_client' 2>/dev/null || true; tmux refresh-client -S -t '$outer_client' 2>/dev/null || true"
  fi
}
trap cleanup EXIT HUP INT TERM

# Throwaway grouped session: shares windows, independent current-window pointer.
tmux new-session -d -t "$session" -s "$grp"
tmux set-option -t "$grp" detach-on-destroy off
tmux set-option -t "$grp" status off
# SIGKILL backstop: reap $grp once the popup client goes away.
tmux set-hook -t "$grp" client-attached "set-option -t $grp destroy-unattached on"

snapshot_file="$(mktemp "${TMPDIR:-/tmp}/tmux-focus-snapshot.XXXXXX")"
capture_snapshot "$pane" "$snapshot_file"

# Spawn a ghost placeholder in a temp window, then swap it with the focused pane:
# the live pane moves to the temp window (popup's, sizes to the popup) while the
# ghost holds the focused pane's exact slot -- the background layout never reflows.
ghost_cmd='exec sleep 2147483647'
read -r ghost_win ghost_win_index ghost_pane < <(tmux new-window -d -P -F '#{window_id} #{window_index} #{pane_id}' "$ghost_cmd")
# Pre-size the temp window to the popup's interior (read from our own pty) BEFORE
# the pane moves in, so the popup attaches at the pane's FINAL size -- no visible
# resize/reflow scroll when focusing a long-scrollback pane (matches prefix+M,
# which resizes once off-screen). Fall back to window-size latest if unreadable.
prows=""; pcols=""
psize="$(stty size </dev/tty 2>/dev/null || true)"
[ -n "$psize" ] && { prows="${psize% *}"; pcols="${psize#* }"; }
if [ -n "$pcols" ] && [ "$pcols" -gt 0 ] 2>/dev/null && [ "$prows" -gt 0 ] 2>/dev/null; then
  tmux set-option -w -t "$ghost_win" window-size manual
  tmux resize-window -t "$ghost_win" -x "$pcols" -y "$prows"
else
  tmux set-option -w -t "$ghost_win" window-size latest
fi
tmux swap-pane -s "$pane" -t "$ghost_pane"
tmux respawn-pane -k -t "$ghost_pane" "$(snapshot_cmd "$snapshot_file")"
tmux select-window -t "$grp:$ghost_win_index"
tmux select-pane -t "$pane"

# State for focus-rotate.sh (opt+` cycles which pane is spotlighted). The ghost
# always sits in the spotlighted pane's home slot, marking it in the bg window.
tmux set-option -t "$grp" @focus_ghost "$ghost_pane"
tmux set-option -t "$grp" @focus_snapshot "$snapshot_file"

# Attach the popup client to $grp (no ignore-size: let it drive the temp window's
# size). NOT exec'd: the foreground attach must return so the EXIT trap restores.
env -u TMUX tmux attach-session -t "$grp"
