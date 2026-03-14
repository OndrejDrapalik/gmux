# gmux development

Ghostty + tmux terminal layer for agentic coding. Companion to [gstack](https://github.com/garrytan/gstack).

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
│   │       ├── pane-border.sh        # Working dir in pane borders
│   │       ├── refresh-panes.sh      # Pane refresh utility
│   │       ├── session-padding.sh    # Session name padding
│   │       ├── tmux-live-port-watcher.sh  # Dev server port detection
│   │       └── tmux-window-status.sh # Window status formatting
│   ├── tmux.conf                 # Entry point (sources base + flavor)
│   └── zshrc                     # Zsh config (omz + aliases)
├── Dockerfile                    # Sandboxed test environment
├── README.md
└── CLAUDE.md
```

## Key conventions

- **Ghostty → tmux bridge**: Ghostty sends Meta escape sequences (`\x1b...`) which tmux binds as `M-` keys. This avoids prefix-key gymnastics.
- **Two flavors**: `tmux.conf` sources `base.conf` (shared UI) + one of `keys-gmux.conf` or `keys-vanilla.conf` based on `$GMUX_FLAVOR` env var. Default is gmux.
- **Tokyo Night**: All colors use the Tokyo Night palette. Keep it consistent.
- **TPM**: Manages plugins (resurrect + continuum). Auto-installs if missing.

## Testing changes

```bash
docker build -t gmux-test .
docker run -it --rm gmux-test            # gmux flavor (default)
docker run -it --rm gmux-test vanilla    # vanilla flavor (stock keys)
```
