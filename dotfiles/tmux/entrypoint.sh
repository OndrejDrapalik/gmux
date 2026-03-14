#!/bin/bash
export GMUX_FLAVOR="${1:-gmux}"
exec tmux new-session
