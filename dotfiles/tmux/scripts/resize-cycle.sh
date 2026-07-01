#!/bin/bash
# Cycle pane size through 1/3, 1/2, 2/3 of window dimension.
# Usage: resize-cycle.sh [--line] W|H [+|-]
#   W = width axis, H = height axis
#   no step: cycle 1/3 -> 1/2 -> 2/3 -> 1/3 (stored index)
#   + / -:   step one rung wider/taller or narrower/shorter from the pane's
#            CURRENT size (nearest rung), wrapping past the ends

scope="pane"
if [ "${1:-}" = "--line" ]; then
    scope="line"
    shift
fi

axis="$1"
step="${2:-}"
pane=$(tmux display -p '#{pane_id}')
window=$(tmux display -p '#{window_id}')

case "$axis" in
    W) opt="@resize_w_idx"; dim="window_width";  pdim="pane_width";  flag="-x"; coord="pane_left"; fcoord="pane_right" ;;
    H) opt="@resize_h_idx"; dim="window_height"; pdim="pane_height"; flag="-y"; coord="pane_top";  fcoord="pane_bottom" ;;
    *) echo "axis must be W or H" >&2; exit 1 ;;
esac

# fractions: 1/3, 1/2, 2/3
nums=(1 1 2)
dens=(3 2 3)

total=$(tmux display -p "#{$dim}")

if [ -n "$step" ]; then
    # directional: find the rung nearest the pane's actual size, then step.
    # +/- arrive as size semantics for a pane anchored at the near (left/top)
    # edge; a pane anchored only at the far (right/bottom) edge grows the
    # opposite way on screen, so flip the step for it.
    cur=$(tmux display -p "#{$pdim}")
    near=$(tmux display -p "#{$coord}")
    far=$(tmux display -p "#{$fcoord}")
    if [ "$near" -gt 0 ] && [ "$far" -eq $(( total - 1 )) ]; then
        case "$step" in +) step="-" ;; -) step="+" ;; esac
    fi
    idx=0; best=$total
    for i in 0 1 2; do
        t=$(( total * ${nums[$i]} / ${dens[$i]} ))
        d=$(( cur > t ? cur - t : t - cur ))
        if (( d < best )); then best=$d; idx=$i; fi
    done
    case "$step" in
        +) idx=$(( (idx + 1) % 3 )) ;;
        -) idx=$(( (idx + 2) % 3 )) ;;
        *) echo "step must be + or -" >&2; exit 1 ;;
    esac
else
    idx=$(tmux show -pqv "$opt" 2>/dev/null)
    [[ -z "$idx" ]] && idx=-1
    idx=$(( (idx + 1) % 3 ))
fi
tmux set -pq "$opt" "$idx"

target=$(( total * ${nums[$idx]} / ${dens[$idx]} ))

if [ "$scope" = "line" ]; then
    active_coord=$(tmux display -p "#{${coord}}")
    tmux list-panes -t "$window" -F "#{$coord} #{pane_id}" |
        awk -v active="$active_coord" '$1 == active { print $2 }' |
        while read -r pane; do
            tmux resize-pane -t "$pane" "$flag" "$target"
        done
else
    tmux resize-pane -t "$pane" "$flag" "$target"
fi
