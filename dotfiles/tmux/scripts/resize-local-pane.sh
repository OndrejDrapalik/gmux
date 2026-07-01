#!/usr/bin/env bash

set -eu

direction="${1:-}"
case "$direction" in
    L|R) axis="W"; flag="-$direction" ;;
    U|D) axis="H"; flag="-$direction" ;;
    *) echo "usage: resize-local-pane.sh L|R|U|D" >&2; exit 1 ;;
esac

amount="${2:-5}"
window="${3:-$(tmux display-message -p '#{window_id}')}"
pane="${4:-$(tmux display-message -p '#{pane_id}')}"

checksum() {
    perl -Mbytes -e '
        my $s = shift;
        my $c = 0;
        for my $ch (split //, $s) {
            $c = (($c >> 1) + (($c & 1) << 15)) & 0xffff;
            $c = ($c + ord($ch)) & 0xffff;
        }
        printf "%04x", $c;
    ' "$1"
}

apply_grid_layout() {
    local orient="$1"
    local rows
    rows="$(tmux list-panes -t "$window" -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}' | sort -k3,3n -k2,2n)"
    [ "$(printf "%s\n" "$rows" | wc -l | tr -d ' ')" = "4" ] || return 1

    local ids lefts tops widths heights i=0
    while read -r id left top width height; do
        ids[$i]="${id#%}"
        lefts[$i]="$left"
        tops[$i]="$top"
        widths[$i]="$width"
        heights[$i]="$height"
        i=$((i + 1))
    done <<EOF
$rows
EOF

    # Only handle regular 2x2 grids. More complex layouts use tmux's native resize.
    [ "${tops[0]}" = "${tops[1]}" ] || return 1
    [ "${tops[2]}" = "${tops[3]}" ] || return 1
    [ "${lefts[0]}" = "${lefts[2]}" ] || return 1
    [ "${lefts[1]}" = "${lefts[3]}" ] || return 1

    local ww wh body sum
    ww="$(tmux display-message -p -t "$window" '#{window_width}')"
    wh="$(tmux display-message -p -t "$window" '#{window_height}')"

    if [ "$orient" = "rows" ]; then
        body="${ww}x${wh},0,0["
        body+="${ww}x${heights[0]},0,${tops[0]}{${widths[0]}x${heights[0]},${lefts[0]},${tops[0]},${ids[0]},${widths[1]}x${heights[1]},${lefts[1]},${tops[1]},${ids[1]}},"
        body+="${ww}x${heights[2]},0,${tops[2]}{${widths[2]}x${heights[2]},${lefts[2]},${tops[2]},${ids[2]},${widths[3]}x${heights[3]},${lefts[3]},${tops[3]},${ids[3]}}"
        body+="]"
    else
        body="${ww}x${wh},0,0{"
        body+="${widths[0]}x${wh},${lefts[0]},0[${widths[0]}x${heights[0]},${lefts[0]},${tops[0]},${ids[0]},${widths[2]}x${heights[2]},${lefts[2]},${tops[2]},${ids[2]}],"
        body+="${widths[1]}x${wh},${lefts[1]},0[${widths[1]}x${heights[1]},${lefts[1]},${tops[1]},${ids[1]},${widths[3]}x${heights[3]},${lefts[3]},${tops[3]},${ids[3]}]"
        body+="}"
    fi

    sum="$(checksum "$body")"
    tmux select-layout -t "$window" "${sum},${body}" >/dev/null 2>&1 || return 1

    for i in 0 1 2 3; do
        local wanted current
        wanted="%${ids[$i]}"
        current="$(tmux list-panes -t "$window" -F '#{pane_id} #{pane_left} #{pane_top}' |
            awk -v left="${lefts[$i]}" -v top="${tops[$i]}" '$2 == left && $3 == top { print $1; exit }')"
        if [ -n "$current" ] && [ "$current" != "$wanted" ]; then
            tmux swap-pane -d -s "$wanted" -t "$current"
        fi
    done
}

case "$axis" in
    W) apply_grid_layout rows || true ;;
    H) apply_grid_layout columns || true ;;
esac

tmux resize-pane -t "$pane" "$flag" "$amount"
