#!/bin/bash
# Pane border format: left = cwd path (truncated to fit), right = branch + git counts.
# Active pane uses themed colors; inactive uses gray.

pane_active="$1"
pane_path="$2"
pane_width="${3:-80}"

path="${pane_path/#$HOME/~}"

gray="#565f89"
normal="#E0AF69"
worktree="#D77757"
branch_color="#7aa2f7"
modified_color="#d7af00"   # p10k 178 — unstaged + staged
untracked_color="#00afff"  # p10k 39 — untracked

if [[ "$pane_active" != "1" ]]; then
    fg="$gray"
elif [[ "$pane_path" == *"_worktrees/"* ]]; then
    fg="$worktree"
else
    fg="$normal"
fi

# --- Build right side (git_info) first; need its visible length for budget.
git_info=""
git_visible=""
if cd "$pane_path" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    porcelain=$(git status --porcelain 2>/dev/null)
    mod=0; staged=0; untracked=0
    if [[ -n "$porcelain" ]]; then
        while IFS= read -r line; do
            xy="${line:0:2}"
            case "$xy" in
                '??') ((untracked++)) ;;
                *)
                    x="${xy:0:1}"
                    y="${xy:1:1}"
                    [[ "$y" =~ [MD] ]] && ((mod++))
                    [[ "$x" =~ [MADRC] ]] && ((staged++))
                    ;;
            esac
        done <<< "$porcelain"
    fi
    if [[ "$pane_active" == "1" ]]; then
        bc="$branch_color"; mc="$modified_color"; uc="$untracked_color"
    else
        bc="$gray"; mc="$gray"; uc="$gray"
    fi
    git_info="#[fg=${bc}]${branch}"
    git_visible="${branch}"
    if (( staged > 0 )); then
        git_info+="#[fg=${mc}] +${staged}"; git_visible+=" +${staged}"
    fi
    if (( mod > 0 )); then
        git_info+="#[fg=${mc}] !${mod}"; git_visible+=" !${mod}"
    fi
    if (( untracked > 0 )); then
        git_info+="#[fg=${uc}] ?${untracked}"; git_visible+=" ?${untracked}"
    fi
fi

# --- Path truncation tiers based on remaining budget.
gap=4
budget=$(( pane_width - ${#git_visible} - gap ))
(( budget < 6 )) && budget=6

if (( ${#path} <= budget )); then
    display_path="$path"
else
    IFS='/' read -r -a parts <<< "$path"
    n=${#parts[@]}
    head1="${parts[0]}"
    [[ -z "$head1" ]] && head1="/"
    head2="${parts[1]}"
    tail="${parts[n-1]}"

    # Tier 1: head1/head2/…/tail (needs >=4 segments to avoid duplication)
    if (( n >= 4 )); then
        candidate="${head1}/${head2}/…/${tail}"
        if (( ${#candidate} <= budget )); then
            display_path="$candidate"
        else
            # Tier 2: head1/…/tail
            candidate="${head1}/…/${tail}"
            if (( ${#candidate} <= budget )); then
                display_path="$candidate"
            else
                # Tier 3: …/tail
                candidate="…/${tail}"
                if (( ${#candidate} <= budget )); then
                    display_path="$candidate"
                else
                    # Tier 4: hard char-clip
                    keep=$(( budget - 1 ))
                    (( keep < 1 )) && keep=1
                    display_path="…${tail: -keep}"
                fi
            fi
        fi
    elif (( n == 3 )); then
        candidate="${head1}/…/${tail}"
        if (( ${#candidate} <= budget )); then
            display_path="$candidate"
        else
            candidate="…/${tail}"
            if (( ${#candidate} <= budget )); then
                display_path="$candidate"
            else
                keep=$(( budget - 1 ))
                (( keep < 1 )) && keep=1
                display_path="…${tail: -keep}"
            fi
        fi
    else
        keep=$(( budget - 1 ))
        (( keep < 1 )) && keep=1
        display_path="…${path: -keep}"
    fi
fi

if [[ -n "$git_info" ]]; then
    printf '#[fg=%s]%s#[align=right]%s' "$fg" "$display_path" "$git_info"
else
    printf '#[fg=%s]%s' "$fg" "$display_path"
fi
