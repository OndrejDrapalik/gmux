#!/usr/bin/env bash
# Print a styled pane list for the Focus Mode top status line, e.g.
#   pane 1 | pane 2 | pane 3
# in clockwise spatial order (the same order opt+` rotation walks), with the
# currently spotlighted pane highlighted. In focus the spotlighted pane lives in
# the popup's temp window; the ghost holds its slot in the original window, so the
# ghost's position in the clockwise order == the spotlighted pane. The emitted
# string carries tmux #[...] style codes, which the status line interprets.
# Args: <ghost_pane> <orig_win>.
set -eu

ghost="$1"
win="$2"

tmux list-panes -t "$win" -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}' | awk -v me="$ghost" '
  { id[NR]=$1; l[NR]=$2; t[NR]=$3; w[NR]=$4; h[NR]=$5; cx+=$2+$4/2; cy+=$3+$5/2; n=NR }
  END {
    if (n == 0) exit
    pi=3.14159265358979; cx/=n; cy/=n
    for (i=1;i<=n;i++){ px=l[i]+w[i]/2; py=t[i]+h[i]/2; a=atan2(py-cy,px-cx)+pi/2; if(a<0)a+=2*pi; if(a>=2*pi)a-=2*pi; ang[i]=a; ord[i]=i }
    for (i=2;i<=n;i++){ k=ord[i]; j=i-1; while(j>=1 && ang[ord[j]]>ang[k]){ ord[j+1]=ord[j]; j-- } ord[j+1]=k }
    out=""
    for (r=1;r<=n;r++){
      if (r>1) out = out "#[fg=colour240,nobold] | #[default]"
      if (id[ord[r]]==me) out = out "#[fg=white,bold]pane " r "#[default]"
      else                out = out "#[fg=colour244,nobold]pane " r "#[default]"
    }
    printf "%s", out
  }'
