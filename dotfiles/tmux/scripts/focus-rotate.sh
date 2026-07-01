#!/usr/bin/env bash
# Focus Mode rotation (opt+` / M-~ inside a _focus_* popup): move the spotlight to
# the NEXT pane clockwise. Mirrors the clockwise spatial order of
# rotate-pane-stay.sh / pane-cycle-clockwise.sh.
#
# In focus the spotlighted pane sits alone in the popup's temp window; a ghost
# pane holds its slot in the original window (so the bg layout never moves). To
# rotate: in the ORIGINAL window's spatial order the ghost marks the spotlighted
# pane's slot, so the next clockwise pane is the new target. Swap the current pane
# home, swap the target into the temp window, keep the popup on the temp window.
set -eu

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

grp="$(tmux display -p '#{session_name}')"
case "$grp" in _focus_*) ;; *) exit 0 ;; esac

ghost="$(tmux show-options -qv -t "$grp" @focus_ghost)"
[ -n "$ghost" ] || exit 0
snapshot_file="$(tmux show-options -qv -t "$grp" @focus_snapshot || true)"
if [ -z "$snapshot_file" ]; then
  snapshot_file="$(mktemp "${TMPDIR:-/tmp}/tmux-focus-snapshot.XXXXXX")"
  tmux set-option -t "$grp" @focus_snapshot "$snapshot_file"
fi
orig_win="$(tmux display -p -t "$ghost" '#{window_id}')"
cur="$(tmux display -p '#{pane_id}')"            # spotlighted pane (alone in temp window)
temp_idx="$(tmux display -p '#{window_index}')"  # popup's current window (the temp window)

# Clockwise spatial order of the ORIGINAL window's panes (the ghost is in there,
# marking the spotlighted pane's slot; cur itself is in the temp window).
panes_raw="$(tmux list-panes -t "$orig_win" -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}')"
order_str="$(awk '
  { id[NR]=$1; l[NR]=$2; t[NR]=$3; w[NR]=$4; h[NR]=$5; cx+=$2+$4/2; cy+=$3+$5/2; n=NR }
  END { pi=3.14159265358979; cx/=n; cy/=n;
    for (i=1;i<=n;i++){ px=l[i]+w[i]/2; py=t[i]+h[i]/2; a=atan2(py-cy,px-cx)+pi/2;
      if(a<0)a+=2*pi; if(a>=2*pi)a-=2*pi; printf "%.6f %s\n",a,id[i] } }
' <<<"$panes_raw" | sort -n | awk '{print $2}')"

order=(); while IFS= read -r p; do order+=("$p"); done <<<"$order_str"
n=${#order[@]}
[ "$n" -le 1 ] && exit 0

# Ghost's index = the spotlighted pane's slot; the next clockwise pane is target.
idx=-1
for i in "${!order[@]}"; do [ "${order[$i]}" = "$ghost" ] && { idx=$i; break; }; done
[ "$idx" -lt 0 ] && exit 0
j=$(( (idx + 1) % n ))
next="${order[$j]}"
[ "$next" = "$ghost" ] && exit 0

capture_snapshot "$next" "$snapshot_file"

# Batched (single redraw): current pane home, next pane into the temp window, pin
# the popup back on the temp window, select the newly-spotlighted pane.
tmux swap-pane -d -s "$cur" -t "$ghost" \; \
     swap-pane -d -s "$next" -t "$ghost" \; \
     select-window -t "$grp:$temp_idx" \; \
     select-pane -t "$next"
tmux respawn-pane -k -t "$ghost" "$(snapshot_cmd "$snapshot_file")" 2>/dev/null || true
tmux select-window -t "$grp:$temp_idx" \; select-pane -t "$next"
