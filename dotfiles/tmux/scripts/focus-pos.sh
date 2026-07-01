#!/usr/bin/env bash
# Print "rank/total" -- the clockwise position (centroid-angle order, same as
# rotate-pane-stay.sh / focus-rotate.sh) of a pane within its window. Used by the
# focus popup's border title (prefix+f). Args: [pane_id] [window_id]; defaults to
# the current active pane/window. Passing them explicitly (the binding does, via
# #{pane_id} #{window_id}) avoids ambiguity when run from tmux #(...) expansion.
set -eu

pane="${1:-$(tmux display -p '#{pane_id}')}"
win="${2:-$(tmux display -p -t "$pane" '#{window_id}')}"

tmux list-panes -t "$win" -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}' | awk -v me="$pane" '
  { id[NR]=$1; l[NR]=$2; t[NR]=$3; w[NR]=$4; h[NR]=$5; cx+=$2+$4/2; cy+=$3+$5/2; n=NR }
  END {
    if (n == 0) exit
    pi=3.14159265358979; cx/=n; cy/=n;
    for (i=1;i<=n;i++){ px=l[i]+w[i]/2; py=t[i]+h[i]/2; a=atan2(py-cy,px-cx)+pi/2; if(a<0)a+=2*pi; if(a>=2*pi)a-=2*pi; ang[i]=a; ord[i]=i }
    for (i=2;i<=n;i++){ k=ord[i]; j=i-1; while(j>=1 && ang[ord[j]]>ang[k]){ ord[j+1]=ord[j]; j-- } ord[j+1]=k }
    for (r=1;r<=n;r++) if (id[ord[r]]==me){ printf "%d/%d", r, n; exit }
  }'
