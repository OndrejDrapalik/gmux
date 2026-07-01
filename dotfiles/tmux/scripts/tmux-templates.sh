#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_DIR="${TMUX_GMUX_TEMPLATE_DIR:-$HOME/.config/tmux-gmux/templates}"

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

slug() {
  printf '%s\n' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//'
}

expand_path() {
  case "$1" in
    '~') printf '%s\n' "$HOME" ;;
    '~/'*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

default_session_name() {
  local root="$1"
  local git_root rel base

  if git_root="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)"; then
    base="$(basename "$git_root")"
    if [ "$root" = "$git_root" ]; then
      rel="."
    else
      rel="${root#$git_root/}"
    fi
    if [ "$rel" = "." ]; then
      slug "$base"
    else
      slug "$base-$rel"
    fi
    return
  fi

  if [ "$root" = "$HOME" ]; then
    rel="$(basename "$HOME")"
  else
    rel="${root#$HOME/}"
    [ "$rel" != "$root" ] || rel="$root"
  fi
  slug "$rel"
}

template_name() {
  jq -er '.name // empty' "$1" 2>/dev/null || basename "${1%.json}"
}

template_description() {
  jq -er '.description // empty' "$1" 2>/dev/null || printf ''
}

list_templates() {
  shopt -s nullglob
  local file name description width
  local max_name=0
  local rows=()

  for file in "$TEMPLATE_DIR"/*.json; do
    name="$(template_name "$file")"
    description="$(template_description "$file")"
    rows+=("$name"$'\t'"$description"$'\t'"$file")
    ((${#name} > max_name)) && max_name="${#name}"
  done

  width="$max_name"
  ((width < 18)) && width=18
  ((width > 32)) && width=32

  for row in "${rows[@]}"; do
    IFS=$'\t' read -r name description file <<< "$row"
    printf "%-${width}.${width}s  %s\t%s\n" "$name" "$description" "$file"
  done
}

repeat_char() {
  local char="$1"
  local count="$2"
  local output=''

  while ((count-- > 0)); do
    output+="$char"
  done
  printf '%s' "$output"
}

fit_text() {
  local text="$1"
  local width="$2"

  if ((${#text} > width)); then
    printf '%-*s' "$width" "${text:0:$((width - 3))}..."
  else
    printf '%-*s' "$width" "$text"
  fi
}

pane_label() {
  local file="$1"
  local window_index="$2"
  local pane_index="$3"
  local command split

  command="$(pane_command "$file" "$window_index" "$pane_index")"
  [ -n "$command" ] || command="shell"

  if ((pane_index > 0)); then
    split="$(jq -r ".windows[$window_index].panes[$pane_index].split // \"down\"" "$file")"
    printf '%s: %s' "$((pane_index + 1))" "$command"
    printf '  (%s)' "$split"
  else
    printf '%s: %s' "$((pane_index + 1))" "$command"
  fi
}

draw_single_pane() {
  local label="$1"
  local width=50
  local inner=$((width - 2))

  printf '+%s+\n' "$(repeat_char '-' "$inner")"
  printf '|%s|\n' "$(fit_text " $label" "$inner")"
  printf '+%s+\n' "$(repeat_char '-' "$inner")"
}

draw_two_panes() {
  local one="$1"
  local two="$2"
  local width=24
  local inner=$((width - 2))

  printf '+%s+%s+\n' "$(repeat_char '-' "$inner")" "$(repeat_char '-' "$inner")"
  printf '|%s|%s|\n' "$(fit_text " $one" "$inner")" "$(fit_text " $two" "$inner")"
  printf '+%s+%s+\n' "$(repeat_char '-' "$inner")" "$(repeat_char '-' "$inner")"
}

draw_three_panes() {
  local one="$1"
  local two="$2"
  local three="$3"
  local width=24
  local inner=$((width - 2))

  printf '+%s+%s+\n' "$(repeat_char '-' "$inner")" "$(repeat_char '-' "$inner")"
  printf '|%s|%s|\n' "$(fit_text " $one" "$inner")" "$(fit_text " $two" "$inner")"
  printf '|%s+%s+\n' "$(fit_text '' "$inner")" "$(repeat_char '-' "$inner")"
  printf '|%s|%s|\n' "$(fit_text '' "$inner")" "$(fit_text " $three" "$inner")"
  printf '+%s+%s+\n' "$(repeat_char '-' "$inner")" "$(repeat_char '-' "$inner")"
}

draw_four_panes() {
  local one="$1"
  local two="$2"
  local three="$3"
  local four="$4"
  local width=24
  local inner=$((width - 2))

  printf '+%s+%s+\n' "$(repeat_char '-' "$inner")" "$(repeat_char '-' "$inner")"
  printf '|%s|%s|\n' "$(fit_text " $one" "$inner")" "$(fit_text " $two" "$inner")"
  printf '+%s+%s+\n' "$(repeat_char '-' "$inner")" "$(repeat_char '-' "$inner")"
  printf '|%s|%s|\n' "$(fit_text " $three" "$inner")" "$(fit_text " $four" "$inner")"
  printf '+%s+%s+\n' "$(repeat_char '-' "$inner")" "$(repeat_char '-' "$inner")"
}

draw_window_preview() {
  local file="$1"
  local window_index="$2"
  local pane_count="$3"
  local labels=()
  local pane_index

  for pane_index in $(seq 0 $((pane_count - 1))); do
    labels+=("$(pane_label "$file" "$window_index" "$pane_index")")
  done

  case "$pane_count" in
    1) draw_single_pane "${labels[0]}" ;;
    2) draw_two_panes "${labels[0]}" "${labels[1]}" ;;
    3) draw_three_panes "${labels[0]}" "${labels[1]}" "${labels[2]}" ;;
    4) draw_four_panes "${labels[0]}" "${labels[1]}" "${labels[2]}" "${labels[3]}" ;;
    *)
      for pane_index in $(seq 0 $((pane_count - 1))); do
        printf '  %s\n' "${labels[$pane_index]}"
      done
      ;;
  esac
}

preview_template() {
  local file="$1"
  [ -f "$file" ] || exit 0

  need jq

  local name description window_count window_index window_name pane_count layout
  name="$(template_name "$file")"
  description="$(template_description "$file")"
  window_count="$(jq -er '(.windows // [{ "name": "shell" }]) | length' "$file")"

  printf '%s\n' "$name"
  [ -n "$description" ] && printf '%s\n' "$description"
  printf '\n'

  for window_index in $(seq 0 $((window_count - 1))); do
    window_name="$(jq -r ".windows[$window_index].name // \"window-$((window_index + 1))\"" "$file")"
    pane_count="$(pane_count_for_window "$file" "$window_index")"
    ((pane_count > 0)) || pane_count=1
    layout="$(jq -r ".windows[$window_index].layout // \"\"" "$file")"

    printf 'Window %s: %s' "$((window_index + 1))" "$window_name"
    [ -n "$layout" ] && [ "$layout" != "null" ] && printf '  layout=%s' "$layout"
    printf '\n'
    draw_window_preview "$file" "$window_index" "$pane_count"
    printf '\n'
  done
}

prompt_session_name() {
  local default_name="$1"
  local session_name

  [ -n "$default_name" ] || default_name="gmux"
  printf '\nSession name [%s]: ' "$default_name" > /dev/tty
  IFS= read -r session_name < /dev/tty || session_name=''
  session_name="${session_name:-$default_name}"
  session_name="$(slug "$session_name")"
  printf '%s\n' "${session_name:-$default_name}"
}

send_command() {
  local target="$1"
  local command="$2"

  if [ -n "$command" ] && [ "$command" != "null" ]; then
    tmux send-keys -t "$target" "$command" C-m
  fi
}

first_pane_id() {
  tmux list-panes -t "$1" -F '#{pane_id}' | head -n 1
}

pane_count_for_window() {
  local file="$1"
  local index="$2"

  jq -er "if (.windows[$index].panes | type) == \"array\" then (.windows[$index].panes | length) else 1 end" "$file" 2>/dev/null || printf '1\n'
}

pane_command() {
  local file="$1"
  local window_index="$2"
  local pane_index="$3"

  if jq -e ".windows[$window_index].panes" "$file" >/dev/null; then
    jq -r ".windows[$window_index].panes[$pane_index].command // \"\"" "$file"
  else
    jq -r ".windows[$window_index].command // \"\"" "$file"
  fi
}

apply_template() {
  local file="$1"
  local root="$2"
  local session="$3"

  [ -f "$file" ] || die "template not found: $file"
  root="$(expand_path "$root")"
  [ -d "$root" ] || die "template root does not exist: $root"

  if tmux has-session -t "$session" 2>/dev/null; then
    tmux switch-client -t "$session"
    exit 0
  fi

  local window_count
  window_count="$(jq -er '(.windows // [{ "name": "shell" }]) | length' "$file")"
  [ "$window_count" -gt 0 ] || die "template has no windows: $(template_name "$file")"

  local window_index window_name window_id first_window_id pane_count pane_index pane_id first_pane command split size layout

  window_name="$(jq -r '.windows[0].name // "shell"' "$file")"
  window_id="$(tmux new-session -d -P -F '#{window_id}' -s "$session" -c "$root" -n "$window_name")"
  first_window_id="$window_id"
  first_pane="$(first_pane_id "$window_id")"
  tmux set-option -wqt "$window_id" @wname "$window_name"
  tmux select-pane -t "$first_pane" -T "pane 1"

  for window_index in $(seq 0 $((window_count - 1))); do
    if [ "$window_index" -gt 0 ]; then
      window_name="$(jq -r ".windows[$window_index].name // \"window-$((window_index + 1))\"" "$file")"
      window_id="$(tmux new-window -d -P -F '#{window_id}' -t "$session:" -c "$root" -n "$window_name")"
      first_pane="$(first_pane_id "$window_id")"
      tmux set-option -wqt "$window_id" @wname "$window_name"
      tmux select-pane -t "$first_pane" -T "pane 1"
    fi

    pane_count="$(pane_count_for_window "$file" "$window_index")"
    ((pane_count > 0)) || pane_count=1
    command="$(pane_command "$file" "$window_index" 0)"
    send_command "$first_pane" "$command"

    if [ "$pane_count" -gt 1 ]; then
      for pane_index in $(seq 1 $((pane_count - 1))); do
        split="$(jq -r ".windows[$window_index].panes[$pane_index].split // \"down\"" "$file")"
        size="$(jq -r ".windows[$window_index].panes[$pane_index].size // \"\"" "$file")"
        command="$(pane_command "$file" "$window_index" "$pane_index")"

        case "$split" in
          down|v|vertical) split="-v" ;;
          right|h|horizontal) split="-h" ;;
          *) die "unknown split '$split' in $file" ;;
        esac

        if [ -n "$size" ] && [ "$size" != "null" ]; then
          pane_id="$(tmux split-window -d -P -F '#{pane_id}' "$split" -l "$size" -t "$window_id" -c "$root")"
        else
          pane_id="$(tmux split-window -d -P -F '#{pane_id}' "$split" -t "$window_id" -c "$root")"
        fi

        tmux select-pane -t "$pane_id" -T "pane $((pane_index + 1))"
        send_command "$pane_id" "$command"
      done
    fi

    layout="$(jq -r ".windows[$window_index].layout // \"\"" "$file")"
    if [ -n "$layout" ] && [ "$layout" != "null" ]; then
      tmux select-layout -t "$window_id" "$layout" >/dev/null
    fi
  done

  tmux select-window -t "$first_window_id"
  tmux switch-client -t "$session"
}

pick_template() {
  need jq
  need fzf
  mkdir -p "$TEMPLATE_DIR"

  local root="${1:-$PWD}"
  local templates selection file default_name session
  templates="$(list_templates)"
  [ -n "$templates" ] || die "no templates in $TEMPLATE_DIR"

  selection="$(
    printf '%s\n' "$templates" |
      fzf --prompt='gmux template > ' \
        --delimiter=$'\t' \
        --with-nth=1 \
        --preview="$0 preview {2}" \
        --preview-window='right,52%,border-left' \
        --header="Apply template to: $root"
  )"

  [ -n "$selection" ] || exit 0
  file="$(printf '%s\n' "$selection" | awk -F '\t' '{ print $2 }')"
  default_name="$(default_session_name "$root")"
  session="$(prompt_session_name "$default_name")"
  apply_template "$file" "$root" "$session"
}

case "${1:-pick}" in
  pick) pick_template "${2:-$PWD}" ;;
  preview) preview_template "${2:-}" ;;
  apply) apply_template "${2:?usage: tmux-templates.sh apply TEMPLATE.json ROOT SESSION}" "${3:?usage: tmux-templates.sh apply TEMPLATE.json ROOT SESSION}" "${4:?usage: tmux-templates.sh apply TEMPLATE.json ROOT SESSION}" ;;
  *) die "usage: tmux-templates.sh [pick [ROOT]|apply TEMPLATE.json ROOT SESSION]" ;;
esac
