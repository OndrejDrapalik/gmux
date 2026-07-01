#!/usr/bin/env bash
# Repair window names after a tmux-resurrect restore.
#
# Why: resurrect restores pane contents by running `cat '<file>'; exec zsh` in
# each pane. tmux names the freshly-created window after that first command, so
# every window is born named "cat". Resurrect then renames windows back from the
# `window` lines in its save file — but when those lines are missing/truncated,
# the rename pass has nothing to apply and windows stay stuck on "cat".
#
# This restores the gmux default (`<index> zsh`) for any window still literally
# named "cat" and republishes @wname so the status bar reflects it immediately.
# Real custom names aren't recoverable (they weren't in the save file).

set -eu

while IFS=$'\t' read -r window_id window_index window_name; do
	[ "${window_name}" = "cat" ] || continue
	name="${window_index} zsh"
	tmux rename-window -t "${window_id}" "${name}"
	tmux set-option -wqt "${window_id}" @wname "${name}"
done < <(tmux list-windows -a -F '#{window_id}	#{window_index}	#{window_name}' 2>/dev/null || true)
