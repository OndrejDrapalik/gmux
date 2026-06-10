# gmux development

Ghostty + tmux terminal layer for agentic coding.

## Project structure

```
gmux/
├── dotfiles/
│   ├── config/
│   │   ├── ghostty/config        # Ghostty terminal config (keybinds, theme, blur)
│   │   └── zsh/fzf-tab-config.zsh  # fzf-tab completion styling
│   ├── tmux/
│   │   ├── base.conf             # Shared theme, status bar, hooks, plugins
│   │   ├── keys-gmux.conf       # Opinionated keybindings (C-Space prefix)
│   │   ├── keys-vanilla.conf    # Stock keybindings (C-b prefix)
│   │   ├── entrypoint.sh        # Docker entrypoint with flavor toggle
│   │   └── scripts/             # tmux helper scripts
│   │       ├── half-zoom.sh          # Column-local vertical zoom toggle
│   │       ├── pane-border.sh        # Optional pane border formatter
│   │       ├── pane-cycle-clockwise.sh # Spatial pane cycling
│   │       ├── recursive-split.sh    # Aspect-ratio based pane splitting
│   │       ├── refresh-panes.sh      # Pane refresh utility
│   │       ├── resize-cycle.sh       # 1/3, 1/2, 2/3 pane size cycling
│   │       ├── session-padding.sh    # Session name padding
│   │       ├── swap-pane-follow.sh   # Directional swap with focus follow
│   │       ├── tmux-agent-detect.sh  # Agent process/state detection (used by refresh-panes)
│   │       ├── tmux-agent-spinner.sh # Agent busy detection + working spinner daemon
│   │       ├── tmux-cohort.sh        # Save/offload/restore session groups
│   │       └── tmux-live-port-watcher.sh  # Dev server port detection
│   ├── tmux.conf                 # Entry point (sources base + flavor)
│   └── zshrc                     # Zsh config (omz + aliases)
├── Dockerfile                    # Sandboxed test environment
├── README.md
└── CLAUDE.md
```

## Key conventions

- **Ghostty → tmux bridge**: Ghostty sends Meta escape sequences (`\x1b...`) which tmux binds as `M-` keys.
- **Two flavors**: `tmux.conf` sources `base.conf` (shared UI) + one of `keys-gmux.conf` or `keys-vanilla.conf` based on `$GMUX_FLAVOR` env var. Default is gmux.
- **Tokyo Night**: All colors use the Tokyo Night palette. Keep it consistent.
- **TPM**: Manages plugins (resurrect + continuum). Auto-installs if missing.

## Testing changes

```bash
bash tests/agent-detector-test.sh
bash -n dotfiles/tmux/scripts/*.sh tests/*.sh dotfiles/tmux/entrypoint.sh
docker build -t gmux-test .
docker run -it --rm gmux-test            # gmux flavor (default)
docker run -it --rm gmux-test vanilla    # vanilla flavor (stock keys)
```
