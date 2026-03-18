# 🪏 gmux

**Ghostty × tmux - the terminal layer for agentic coding.**

While [gstack](https://github.com/garrytan/gstack) gives Claude Code cognitive
workflows (plan → review → ship → QA), **gmux** gives you the terminal
infrastructure those workflows run inside: an agent working indicator,
a live port watcher, and a Ghostty → tmux bridge that maps Cmd‑keys straight to tmux
actions — no prefix gymnastics.

gstack is the brain. gmux is the trenches.

<img src="assets/hero-demo.gif" alt="gmux demo" width="100%">

## What's Inside

| Layer | File | Purpose |
|-------|------|---------|
| Ghostty | `dotfiles/config/ghostty/config` | Cmd-key → tmux Meta passthrough, Tokyo Night theme, background blur |
| tmux | `dotfiles/tmux.conf` | Entry point — sources shared theme + keybinding flavor |
| tmux | `dotfiles/tmux/base.conf` | Shared theme, status bar, hooks, plugins (both flavors) |
| tmux | `dotfiles/tmux/keys-*.conf` | Keybinding flavors: `gmux` (opinionated) or `vanilla` (stock) |
| tmux scripts | `dotfiles/tmux/scripts/` | Agent working indicator, live port watcher, pane borders |
| zsh | `dotfiles/zshrc` | omz + git aliases + Claude Code env |
| zsh | `dotfiles/config/zsh/fzf-tab-config.zsh` | fzf-tab completion styling |
| Docker | `Dockerfile` | Sandboxed test environment with full stack |

## Key Features

**Agent working indicator** — Claude Code and Codex sessions show a
visible "working" state in the tab so you always know which panes are
thinking.

**Live port watcher** — Detects dev servers and annotates window status
with active ports.

**Pane borders** — Shows working directory in the pane border line.

**Worktree colors** — Git worktree windows get a distinct color so you
can tell them apart from your main branch at a glance.

**Ghostty → tmux bridge** — Cmd+1/2/3 switch windows and panes natively.
Opt+Cmd reorders. Hyper+M zooms. No prefix gymnastics.

**Docker sandbox** — `docker run -it --rm gmux-test` drops you into
the full setup for testing config changes without touching your current setup.

## Flavors

gmux ships two keybinding flavors. Both share the same visual theme, agent indicators, and plugins.

- **gmux** (default) — `C-Space` prefix, remapped keys, Ghostty shortcuts
- **vanilla** — stock `C-b` prefix, all default tmux bindings, terminal-agnostic

Switch flavor: `export GMUX_FLAVOR=vanilla` in your shell profile, or `GMUX_FLAVOR=vanilla tmux`.

In Docker: `docker run -it --rm gmux-test vanilla`

## Keybindings (gmux flavor)

The tables below apply to the **gmux** flavor. Vanilla uses stock tmux keybindings.

`prefix` means `C-Space` throughout.

### Remapped from stock tmux

| Action | Stock tmux | gmux | Notes |
|--------|-----------|------|-------|
| **Prefix** | `C-b` | `C-Space` | `C-b` is an awkward reach — `C-Space` sits under both thumbs, and maps nicely to Hyper key (Caps Lock) via Karabiner |
| **New window** | `prefix c` | `prefix t` | `t` for tab; `c` is freed for other use |
| **Split ↓** | `prefix "` | `prefix "` / `prefix -` | New pane inherits working directory; `-` is an easier-to-reach alias |
| **Split →** | `prefix %` | `prefix %` / `prefix _` | New pane inherits working directory; `_` is an easier-to-reach alias |
| **Navigate panes** | `prefix Arrow` | `prefix h/j/k/l` | Vim-style directional pane selection |
| **Kill pane** | `prefix x` | `prefix x` | Same, with a confirmation prompt |
| **Kill window** | `prefix &` | `prefix X` | Capital X; also asks for confirmation |
| **Next window** | `prefix n` | `prefix n` | Also repeatable with `prefix ]` |
| **Previous window** | `prefix p` | `prefix p` | Also repeatable with `prefix [` |
| **Cycle panes** | `prefix o` | `prefix ;` / `prefix '` | Backward / forward, repeatable and wraps around |
| **Zoom pane** | `prefix z` | `prefix M` | Also available as `Hyper+M` without prefix via Ghostty |
| **Resize pane** | `prefix M-Arrow` | `prefix H/J/K/L` | Vim-style, repeatable, 5 cells per press |
| **Copy mode** | `prefix [` | `prefix C` | `[` is rebound to window navigation |
| **Paste buffer** | `prefix ]` | `prefix v` | Vi-style; `]` is rebound to window navigation |
| **Detach** | `prefix d` | — | `d` is rebound to clear screen; detach with `prefix :detach` |
| **Clock** | `prefix t` | — | `t` is rebound to new window; clock with `prefix :clock-mode` |
| **Display pane numbers** | `prefix q` | — | `q` sends `Ctrl-C` (interrupt current command) |

### gmux additions

| Action | gmux | Notes |
|--------|------|-------|
| **Clear screen** | `prefix d` | Clears screen + scrollback + refreshes prompt |
| **Clear + history msg** | `prefix C-k` | Clears screen + scrollback with confirmation message |
| **Clear (keep history)** | `prefix M-k` | Clears visible screen only |
| **Passthrough C-l** | `prefix C-l` | Sends raw `C-l` to the shell (standard clear) |
| **Interrupt command** | `prefix q` | Sends `Ctrl-C` to the active pane |
| **Reorder window** | `prefix <` / `prefix >` | Move the current window left or right in the tab bar |
| **Refresh all panes** | `prefix r` | Clears screen in all panes, skips running agents and dev servers |
| **Reload config** | `prefix R` | Live-reload `tmux.conf` without restarting |
| **Rename pane** | `prefix T` | Name panes for easy identification on the pane tab bar |
| **Split ↑** | `prefix M--` | New pane above the current one |
| **Full-height split** | `prefix \|` | Vertical split that spans all horizontal panes |
| **Grab all content** | `prefix g` | Selects entire scrollback and copies to clipboard |
| **Save session** | `prefix C-s` | tmux-resurrect: persist windows, panes, and layout across restarts |
| **Restore session** | `prefix C-r` | tmux-resurrect: restore a previously saved session |
| **Linked session** | `C-x` (no prefix) | Opens a second view into the same session for independent window browsing |

### Ghostty Shortcuts (no prefix needed)

These bypass the prefix entirely — Ghostty sends Meta escape sequences that tmux binds directly.

| Shortcut | Action |
|----------|--------|
| `Cmd+1` / `Cmd+2` | Previous / next window |
| `Cmd+`` ` | Cycle to next pane |
| `Cmd+3` | Cycle to previous pane |
| `Opt+Cmd+1` / `Opt+Cmd+2` | Reorder window left / right |
| `Cmd+Shift+K` | Clear screen + scrollback |
| `Hyper+M` | Toggle pane zoom |

## Quick Start

### Use the dotfiles

```sh
# Clone
git clone https://github.com/OndrejDrapalik/gmux-wip.git
cd gmux-wip

# Symlink tmux config + supporting files
ln -sf $(pwd)/dotfiles/tmux.conf ~/.tmux.conf
ln -sf $(pwd)/dotfiles/tmux/base.conf ~/.tmux/base.conf
ln -sf $(pwd)/dotfiles/tmux/keys-gmux.conf ~/.tmux/keys-gmux.conf
ln -sf $(pwd)/dotfiles/tmux/keys-vanilla.conf ~/.tmux/keys-vanilla.conf
cp -r dotfiles/tmux/scripts/ ~/.tmux/scripts/

# Ghostty config (optional)
cp dotfiles/config/ghostty/config ~/.config/ghostty/config
```

### Test in Docker

```sh
docker build -t gmux-test .
docker run -it --rm gmux-test            # gmux flavor
docker run -it --rm gmux-test vanilla    # vanilla flavor
```

## Stack

- [Ghostty](https://ghostty.org) — GPU-accelerated terminal
- [TPM](https://github.com/tmux-plugins/tpm) — tmux plugin manager (resurrect + continuum)
- [Tokyo Night](https://github.com/folke/tokyonight.nvim) — color scheme
- [gstack](https://github.com/garrytan/gstack) — Claude Code workflow skills (complementary)
