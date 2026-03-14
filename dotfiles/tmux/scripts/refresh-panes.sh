#!/usr/bin/env bash
# Refresh all panes in current window: sends Enter + clears screen.
# Skips panes that are:
#   - Running claude or codex (AI agent sessions)
#   - Running a process listening on a localhost port (dev servers)

set -eu

# Build set of pane IDs whose process tree includes a listening port.
# Same process-tree-walking technique as tmux-live-port-watcher.sh.
port_pane_ids=$(
  {
    tmux list-panes -F 'P #{pane_id} #{pane_pid}' 2>/dev/null
    ps -axo pid=,ppid= | awk '{ print "R " $1 " " $2 }'
    lsof -nP -iTCP -sTCP:LISTEN -Fp 2>/dev/null | awk '
      /^p[0-9]/ { pid = substr($0, 2) }
      /^n/ && pid != "" {
        port = $0; sub(/^.*:/, "", port); sub(/[^0-9].*$/, "", port)
        if (port ~ /^[0-9]+$/ && port+0 >= 1024 && port+0 <= 20000)
          print "L " pid
        pid = ""
      }
    '
  } | awk '
    $1=="P" { pane_id[$3]=$2; next }
    $1=="R" { ppid[$2]=$3; next }
    $1=="L" { listen[++n]=$2; next }
    END {
      for (i=1; i<=n; i++) {
        pid = listen[i]
        while (pid != "" && pid+0 > 0) {
          if (pane_id[pid] != "") {
            result[pane_id[pid]] = 1
            break
          }
          pid = ppid[pid]
        }
      }
      for (id in result) print id
    }
  '
) || true

for entry in $(tmux list-panes -F '#{pane_id}:#{pane_pid}'); do
  id="${entry%%:*}"
  pid="${entry#*:}"

  # Skip panes with a process listening on a port
  case " $port_pane_ids " in
    *" $id "*) continue ;;
  esac

  # Skip panes running claude or codex
  if pgrep -P "$pid" "claude|codex" >/dev/null 2>&1; then
    continue
  fi

  tmux send-keys -t "$id" Enter
  tmux send-keys -t "$id" -R
  tmux send-keys -t "$id" C-l
done
