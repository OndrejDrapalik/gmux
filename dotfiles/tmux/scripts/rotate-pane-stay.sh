#!/usr/bin/env bash
# Rotate pane CONTENTS around the window in clockwise spatial order while the
# cursor STAYS at the current screen position — you sit still and watch the
# panes circle past you. Companion to pane-cycle-clockwise.sh, which instead
# moves focus through the same order and leaves contents put.
#
# Usage: rotate-pane-stay.sh <cw|ccw>
#
# Ordering mirrors pane-cycle-clockwise.sh: sort panes by angle from the window
# centroid (screen coords, y-down, origin rotated to "up" → clockwise = ascending
# angle). A cyclic shift along that order is a chain of swaps carrying one pane
# id through the chain.
#
# Flicker: all swaps + the final select are issued as a SINGLE tmux command
# queue (`swap-pane … \; swap-pane … \; select-pane …`) so tmux redraws once at
# the end instead of once per swap.

set -eu

dir="${1:?direction required: cw|ccw}"

current=$(tmux display -p '#{pane_id}')

panes_raw=$(tmux list-panes -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}')

# Pane ids sorted by clockwise angle from the window centroid.
order_str=$(awk '
  {
    id[NR]=$1; l[NR]=$2; t[NR]=$3; w[NR]=$4; h[NR]=$5;
    cx_sum += $2 + $4/2; cy_sum += $3 + $5/2; n = NR;
  }
  END {
    pi = 3.14159265358979; cx = cx_sum / n; cy = cy_sum / n;
    for (i = 1; i <= n; i++) {
      px = l[i] + w[i]/2; py = t[i] + h[i]/2;
      a = atan2(py - cy, px - cx) + pi/2;
      if (a < 0) a += 2*pi; if (a >= 2*pi) a -= 2*pi;
      printf "%.6f %s\n", a, id[i];
    }
  }
' <<<"$panes_raw" | sort -n | awk '{print $2}')

order=()
while IFS= read -r pid; do order+=("$pid"); done <<<"$order_str"
n=${#order[@]}
[ "$n" -le 1 ] && exit 0

# Index of the pane the cursor is on, in spatial order.
idx=-1
for i in "${!order[@]}"; do [ "${order[$i]}" = "$current" ] && { idx=$i; break; }; done
[ "$idx" -lt 0 ] && exit 0

# Build one batched tmux command: a cyclic shift along the spatial order, then
# re-select whichever pane lands on the cursor's old slot so focus stays put.
# cw moves each pane's content to the next clockwise slot; ccw is the reverse.
cmd=()
case "$dir" in
  cw)
    carry=${order[$((n-1))]}
    for (( i = n-2; i >= 0; i-- )); do cmd+=(swap-pane -d -s "$carry" -t "${order[$i]}" ';'); done
    target=${order[$(( (idx - 1 + n) % n ))]}
    ;;
  ccw)
    carry=${order[0]}
    for (( i = 1; i < n; i++ )); do cmd+=(swap-pane -d -s "$carry" -t "${order[$i]}" ';'); done
    target=${order[$(( (idx + 1) % n ))]}
    ;;
  *) echo "unknown direction: $dir" >&2; exit 2 ;;
esac
cmd+=(select-pane -t "$target")

tmux "${cmd[@]}"
