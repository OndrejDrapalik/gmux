#!/usr/bin/env bash
# tmux-cohort — save/restore/offload named groups of tmux sessions
# Compatible with bash 3.2 (macOS default)
set -euo pipefail

COHORT_DIR="$HOME/.tmux/cohorts"
RESURRECT_DIR="$HOME/.tmux/resurrect"
RESURRECT_SAVE="$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"

mkdir -p "$COHORT_DIR"

# ── helpers ──────────────────────────────────────────────────────────────────

die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: tmux-cohort <command> [args]

Commands:
  save  [name] [sessions...]   Save sessions as a named cohort
  restore [name]               Restore a saved cohort
  offload [name] [sessions...] Save + kill selected sessions
  list                         List all saved cohorts
  delete <name>                Delete a saved cohort
  preview <file>               (internal) fzf preview for a cohort file
EOF
  exit 1
}

# Return list of running tmux sessions
running_sessions() {
  tmux list-sessions -F '#{session_name}' 2>/dev/null || true
}

# Pick sessions interactively via fzf
pick_sessions() {
  local sessions
  sessions=$(running_sessions)
  [ -z "$sessions" ] && die "No tmux sessions running"
  echo "$sessions" | fzf --multi --prompt="Select sessions > " --header="TAB to multi-select, ENTER to confirm"
}

# Prompt for cohort name
prompt_name() {
  local name=""
  printf "Cohort name: " >&2
  read -r name
  [ -z "$name" ] && die "Name required"
  # sanitize: allow alphanumeric, dash, underscore
  name=$(echo "$name" | tr ' ' '-' | tr -cd 'a-zA-Z0-9_-')
  [ -z "$name" ] && die "Invalid name"
  echo "$name"
}

# Build preview text from a cohort file (bash 3.2 compatible)
render_preview() {
  local file="$1"
  [ ! -f "$file" ] && return 0

  # parse header
  local header
  header=$(head -1 "$file")
  local name saved
  name=$(echo "$header" | sed -n 's/^# cohort:\([^ ]*\).*/\1/p')
  saved=$(echo "$header" | sed -n 's/.* saved:\([^ ]*\).*/\1/p')

  # human-readable date
  local pretty_date="$saved"
  if [ -n "$saved" ]; then
    pretty_date=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$saved" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$saved")
  fi

  printf '\033[1m%s\033[0m  \033[2m(saved %s)\033[0m\n' "$name" "$pretty_date"
  printf '─────────────────────────────\n'

  # use awk to build the whole preview (avoids associative arrays)
  awk -F'\t' '
    # count windows per session
    $1 == "window" { wcount[$2]++ }
    # track first pane per window for directory info
    $1 == "pane" {
      key = $2 "\t" $3
      if (!(key in seen_pane)) {
        seen_pane[key] = 1
        pane_sess[key] = $2
        pane_widx[key] = $3
        pane_dir[key] = $8
        sub(/^:/, "", pane_dir[key])
        pane_order[++pane_n] = key
      }
    }
    # track window names
    $1 == "window" {
      key = $2 "\t" $3
      wname[key] = $4
      sub(/^:/, "", wname[key])
    }
    END {
      # get sorted unique sessions
      for (s in wcount) sessions[++ns] = s
      # simple sort
      for (i = 1; i <= ns; i++)
        for (j = i+1; j <= ns; j++)
          if (sessions[i] > sessions[j]) {
            t = sessions[i]; sessions[i] = sessions[j]; sessions[j] = t
          }

      for (i = 1; i <= ns; i++) {
        s = sessions[i]
        printf "\033[1;33m%s\033[0m (%d windows)\n", s, wcount[s]
        for (p = 1; p <= pane_n; p++) {
          k = pane_order[p]
          if (pane_sess[k] != s) continue
          dir = pane_dir[k]
          gsub(/\/Users\/[^\/]+/, "~", dir)
          wk = k
          printf "  %s: \033[2m%-20s\033[0m %s\n", pane_widx[k], wname[wk], dir
        }
      }
    }
  ' "$file"
}

# ── save ─────────────────────────────────────────────────────────────────────

cmd_save() {
  local name="${1:-}"
  shift 2>/dev/null || true
  local sessions=""
  local session_count=0

  # collect remaining args as sessions
  for arg in "$@"; do
    [ -n "$sessions" ] && sessions="$sessions"$'\n'
    sessions="${sessions}${arg}"
    session_count=$((session_count + 1))
  done

  # interactive mode
  if [ $session_count -eq 0 ]; then
    sessions=$(pick_sessions) || exit 1
    session_count=$(echo "$sessions" | wc -l | tr -d ' ')
  fi
  if [ -z "$name" ]; then
    name=$(prompt_name) || exit 1
  fi

  [ -z "$sessions" ] && die "No sessions selected"

  # trigger fresh resurrect save (best-effort — might fail outside tmux)
  if [ -x "$RESURRECT_SAVE" ]; then
    info "Saving fresh resurrect snapshot..."
    tmux run-shell "$RESURRECT_SAVE" 2>/dev/null || warn "Could not refresh resurrect snapshot — using existing"
    sleep 1  # wait for file to flush
  fi

  local src="$RESURRECT_DIR/last"
  [ ! -f "$src" ] && die "No resurrect snapshot found at $src"

  local dst="$COHORT_DIR/${name}.txt"
  local ts
  ts=$(date "+%Y-%m-%dT%H:%M:%S")
  local sessions_csv
  sessions_csv=$(echo "$sessions" | tr '\n' ',' | sed 's/,$//')

  # write header
  echo "# cohort:${name} saved:${ts} sessions:${sessions_csv}" > "$dst"

  # build awk pattern from session names
  local session_pattern=""
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    [ -n "$session_pattern" ] && session_pattern="${session_pattern}|"
    session_pattern="${session_pattern}${s}"
  done <<< "$sessions"

  awk -F'\t' -v pat="^(${session_pattern})$" '
    $1 == "pane"   && $2 ~ pat { print }
    $1 == "window" && $2 ~ pat { print }
  ' "$src" >> "$dst"

  local line_count
  line_count=$(wc -l < "$dst" | tr -d ' ')
  info "Saved cohort '$name' → $dst ($((line_count - 1)) lines, sessions: $sessions_csv)"
}

# ── restore ──────────────────────────────────────────────────────────────────

cmd_restore() {
  local name="${1:-}"
  local file=""

  if [ -z "$name" ]; then
    # interactive: fzf pick cohort
    local cohorts
    cohorts=$(ls "$COHORT_DIR"/*.txt 2>/dev/null) || die "No cohorts saved"
    file=$(echo "$cohorts" | fzf \
      --prompt="Restore cohort > " \
      --preview="$0 preview {}" \
      --preview-window=right:60%:wrap) || exit 1
  else
    file="$COHORT_DIR/${name}.txt"
  fi

  [ ! -f "$file" ] && die "Cohort file not found: $file"

  local running
  running=$(running_sessions)

  # collect unique sessions from the file
  local all_sessions
  all_sessions=$(awk -F'\t' '$1=="pane" { print $2 }' "$file" | sort -u)

  local created="" skipped=""

  while IFS= read -r sess; do
    [ -z "$sess" ] && continue

    if echo "$running" | grep -qx "$sess"; then
      [ -n "$skipped" ] && skipped="$skipped "
      skipped="${skipped}${sess}"
      warn "Session '$sess' already exists — skipping"
      continue
    fi

    # get first pane dir for initial session creation
    local first_dir
    first_dir=$(awk -F'\t' -v s="$sess" '$1=="pane" && $2==s { d=$8; sub(/^:/,"",d); print d; exit }' "$file")

    tmux new-session -d -s "$sess" -c "$first_dir"
    [ -n "$created" ] && created="$created "
    created="${created}${sess}"

    # track which windows we've created
    local prev_win=""

    while IFS=$'\t' read -r type s widx wactive wflags pidx ptitle pdir rest; do
      [ "$type" != "pane" ] && continue
      [ "$s" != "$sess" ] && continue

      local dir="${pdir#:}"

      if [ "$widx" != "$prev_win" ]; then
        if [ -n "$prev_win" ]; then
          tmux new-window -t "${sess}" -c "$dir"
        fi
        prev_win="$widx"
      else
        tmux split-window -t "${sess}" -c "$dir"
      fi

      # set pane title if non-default
      case "$ptitle" in
        "pane "*) ;; # skip default pane titles
        "") ;;       # skip empty
        *) tmux select-pane -t "${sess}" -T "$ptitle" ;;
      esac
    done < "$file"

    # set window names from window lines
    while IFS=$'\t' read -r type s widx wname rest; do
      [ "$type" != "window" ] && continue
      [ "$s" != "$sess" ] && continue
      local clean_name="${wname#:}"
      if [ -n "$clean_name" ]; then
        tmux rename-window -t "${sess}:${widx}" "$clean_name" 2>/dev/null || true
      fi
    done < "$file"

  done <<< "$all_sessions"

  [ -n "$created" ] && info "Restored: $created"
  [ -n "$skipped" ] && warn "Skipped (already running): $skipped"
}

# ── offload ──────────────────────────────────────────────────────────────────

cmd_offload() {
  local name="${1:-}"
  shift 2>/dev/null || true
  local sessions=""
  local session_count=0

  for arg in "$@"; do
    [ -n "$sessions" ] && sessions="$sessions"$'\n'
    sessions="${sessions}${arg}"
    session_count=$((session_count + 1))
  done

  # interactive: pick sessions first
  if [ $session_count -eq 0 ]; then
    sessions=$(pick_sessions) || exit 1
    session_count=$(echo "$sessions" | wc -l | tr -d ' ')
  fi
  if [ -z "$name" ]; then
    name=$(prompt_name) || exit 1
  fi

  # save first (pass sessions as args)
  local save_args="$name"
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    save_args="$save_args $s"
  done <<< "$sessions"
  eval cmd_save $save_args

  # kill sessions
  local kill_count=0
  while IFS= read -r sess; do
    [ -z "$sess" ] && continue
    tmux kill-session -t "$sess" 2>/dev/null && info "Killed session: $sess" || warn "Could not kill session: $sess"
    kill_count=$((kill_count + 1))
  done <<< "$sessions"

  info "Offloaded $kill_count session(s) → cohort '$name'"
  info "Restore with: tmux-cohort restore $name"
}

# ── list ─────────────────────────────────────────────────────────────────────

cmd_list() {
  local files
  files=$(ls "$COHORT_DIR"/*.txt 2>/dev/null) || { info "No cohorts saved"; exit 0; }

  for file in $files; do
    local header
    header=$(head -1 "$file")
    local name saved
    name=$(echo "$header" | sed -n 's/^# cohort:\([^ ]*\).*/\1/p')
    saved=$(echo "$header" | sed -n 's/.* saved:\([^ ]*\).*/\1/p')

    local pretty_date="$saved"
    if [ -n "$saved" ]; then
      pretty_date=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$saved" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$saved")
    fi

    # use awk to count windows per session (no associative arrays needed)
    local details
    details=$(awk -F'\t' '
      $1 == "window" { wcount[$2]++ }
      END {
        n = 0
        for (s in wcount) sessions[++n] = s
        for (i = 1; i <= n; i++)
          for (j = i+1; j <= n; j++)
            if (sessions[i] > sessions[j]) {
              t = sessions[i]; sessions[i] = sessions[j]; sessions[j] = t
            }
        first = 1
        for (i = 1; i <= n; i++) {
          if (!first) printf ", "
          printf "%s(%dw)", sessions[i], wcount[sessions[i]]
          first = 0
        }
      }
    ' "$file")

    printf '\033[1m%-20s\033[0m \033[2m%s\033[0m  %s\n' "$name" "$pretty_date" "$details"
  done
}

# ── delete ───────────────────────────────────────────────────────────────────

cmd_delete() {
  local name="${1:-}"
  [ -z "$name" ] && die "Usage: tmux-cohort delete <name>"

  local file="$COHORT_DIR/${name}.txt"
  [ ! -f "$file" ] && die "Cohort '$name' not found"

  rm "$file"
  info "Deleted cohort '$name'"
}

# ── main ─────────────────────────────────────────────────────────────────────

cmd="${1:-}"
shift 2>/dev/null || true

case "$cmd" in
  save)    cmd_save "$@" ;;
  restore) cmd_restore "$@" ;;
  offload) cmd_offload "$@" ;;
  list)    cmd_list ;;
  delete)  cmd_delete "$@" ;;
  preview) render_preview "$@" ;;
  *)       usage ;;
esac
