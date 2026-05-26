# gmux

**Ghostty x tmux configuration for agentic coding.**

gmux is a tmux and Ghostty configuration for running coding agents, development
servers, test runners, logs, and shells in one terminal workspace. It adds
status-bar indicators for active agents and local servers, layout helpers, and
Ghostty Cmd shortcuts that map to tmux actions.

The repository is dotfiles and shell scripts. Install the tmux files directly,
copy the optional Ghostty/zsh files if needed, and adjust the bindings locally.

<img src="assets/hero-demo.gif" alt="gmux demo" width="100%">

## What It Solves

- **Agent visibility**: Claude, Codex, and opencode panes are detected even when
  launched through common wrappers. A window tab spins only while an agent is
  actually working.
- **Dev server indicators**: windows with local listeners get a live port
  marker.
- **Safe pane refresh**: the refresh command skips agents and servers instead of
  interrupting work.
- **Ghostty shortcuts**: Cmd and Hyper shortcuts can switch, reorder, clear, and
  zoom tmux panes without using the prefix key.
- **Pane layout helpers**: recursive split, clockwise pane cycling, directional
  pane swaps with focus follow, half-zoom, and size cycling are available as
  scripts and keybindings.
- **Two keybinding modes**: use the opinionated gmux flavor, or keep stock tmux
  bindings with the same status bar and observability layer.

## Who It Is For

gmux is for developers running AI coding agents inside tmux/Ghostty who still
want normal shell sessions, real panes, session persistence, and direct control
over the config. It is not a GUI agent app, a package manager, or a framework.

## Quick Start

```sh
git clone https://github.com/OndrejDrapalik/gmux.git
cd gmux

mkdir -p ~/.tmux ~/.config/zsh
ln -sf "$(pwd)/dotfiles/tmux.conf" ~/.tmux.conf
ln -sf "$(pwd)/dotfiles/tmux/base.conf" ~/.tmux/base.conf
ln -sf "$(pwd)/dotfiles/tmux/keys-gmux.conf" ~/.tmux/keys-gmux.conf
ln -sf "$(pwd)/dotfiles/tmux/keys-vanilla.conf" ~/.tmux/keys-vanilla.conf
rm -rf ~/.tmux/scripts
cp -R dotfiles/tmux/scripts ~/.tmux/scripts
chmod +x ~/.tmux/scripts/*.sh
```

Optional Ghostty and zsh files:

```sh
mkdir -p ~/.config/ghostty ~/.config/zsh
cp dotfiles/config/ghostty/config ~/.config/ghostty/config
cp dotfiles/config/zsh/fzf-tab-config.zsh ~/.config/zsh/fzf-tab-config.zsh
```

Start tmux normally:

```sh
tmux
```

Use the stock tmux keybinding flavor:

```sh
GMUX_FLAVOR=vanilla tmux
```

## Test in Docker

```sh
docker build -t gmux-test .
docker run -it --rm gmux-test            # gmux flavor
docker run -it --rm gmux-test vanilla    # vanilla flavor
```

## What's Inside

| Layer | File | Purpose |
| --- | --- | --- |
| Ghostty | `dotfiles/config/ghostty/config` | Cmd-key to tmux Meta passthrough, Tokyo Night theme, background blur |
| tmux | `dotfiles/tmux.conf` | Entry point that sources the shared base and selected keybinding flavor |
| tmux | `dotfiles/tmux/base.conf` | Shared theme, status bar, hooks, plugins, port watcher, agent spinner |
| tmux | `dotfiles/tmux/keys-gmux.conf` | Opinionated `C-Space` keybinding flavor |
| tmux | `dotfiles/tmux/keys-vanilla.conf` | Stock `C-b` keybinding flavor |
| tmux scripts | `dotfiles/tmux/scripts/` | Agent detection, spinner, port watcher, pane/layout helpers, refresh helpers |
| zsh | `dotfiles/zshrc` | omz, git aliases, Claude Code environment |
| zsh | `dotfiles/config/zsh/fzf-tab-config.zsh` | fzf-tab completion styling |
| Docker | `Dockerfile` | Sandboxed test environment with the full gmux stack |

## Features

### Agent Working Indicator

`tmux-window-status.sh` asks `tmux-agent-detect.sh` whether any pane in a window
is running Claude, Codex, or opencode and whether that pane is currently
working. When it is, `tmux-agent-spinner.sh` animates the window tab.

Detection handles direct binaries, common wrapper names, symlinked launchers,
and runtime launches through `node`, `bun`, Python, or shells. It intentionally
does not treat helper binaries like `codex-helper` or inert `python -c` commands
as agent sessions.

### Live Port Watcher

`tmux-live-port-watcher.sh` walks pane process trees, finds local TCP listeners
on development ports, and marks the owning window in the status bar.

### Safe Pane Refresh

`prefix r` refreshes the current window while skipping panes that are running
agents or local dev servers. That keeps a "clean up the screen" command from
accidentally interrupting an agent or server.

### Ghostty to tmux Bridge

Ghostty sends Meta escape sequences that tmux binds directly. Cmd shortcuts can
move between windows, cycle panes, reorder tabs, clear scrollback, and toggle
zoom.

### Pane Layout Scripts

The gmux flavor includes helper scripts for operations that are awkward to
express as one-line tmux bindings:

- `recursive-split.sh`: split the active pane along its longer dimension.
- `pane-cycle-clockwise.sh`: cycle panes by screen position instead of pane
  index.
- `swap-pane-follow.sh`: swap in a direction and keep focus on the moved pane.
- `resize-cycle.sh`: cycle the active pane through 1/3, 1/2, and 2/3 sizes.
- `half-zoom.sh`: toggle a vertical half-zoom inside the current column.
- `tmux-cohort.sh`: save, offload, and restore named groups of sessions.

## Flavors

Both flavors share the Tokyo Night status bar, agent indicators, port watcher,
tmux-resurrect, and tmux-continuum.

- **gmux**: default, `C-Space` prefix, remapped keys, Ghostty shortcuts.
- **vanilla**: stock `C-b` prefix and default tmux bindings.

Switch flavor with `GMUX_FLAVOR=vanilla tmux` or by exporting
`GMUX_FLAVOR=vanilla` in your shell profile.

## Keybindings

The tables below apply to the **gmux** flavor. Vanilla keeps stock tmux
keybindings.

`prefix` means `C-Space`.

### Remapped from stock tmux

| Action | Stock tmux | gmux | Notes |
| --- | --- | --- | --- |
| **Prefix** | `C-b` | `C-Space` | Easier thumb reach; maps well to Hyper/Caps Lock setups |
| **New window** | `prefix c` | `prefix t` | `t` for tab |
| **Split down** | `prefix "` | `prefix "` / `prefix -` | New pane inherits working directory |
| **Split right** | `prefix %` | `prefix %` / `prefix _` | New pane inherits working directory |
| **Navigate panes** | `prefix Arrow` | `prefix h/j/k/l` | Vim-style movement |
| **Kill pane** | `prefix x` | `prefix x` | Same action, with confirmation |
| **Kill window** | `prefix &` | `prefix X` | Capital X, with confirmation |
| **Next window** | `prefix n` | `prefix n` / `prefix ]` | `]` is repeatable |
| **Previous window** | `prefix p` | `prefix p` / `prefix [` | `[` is repeatable |
| **Cycle panes** | `prefix o` | `prefix ;` / `prefix '` | Backward / forward, repeatable |
| **Zoom pane** | `prefix z` | `prefix M` | Also available as `Hyper+M` in Ghostty |
| **Resize pane** | `prefix M-Arrow` | `prefix H/J/K/L` | Vim-style, repeatable, 5 cells per press |
| **Copy mode** | `prefix [` | `prefix C` | `[` is used for window navigation |
| **Paste buffer** | `prefix ]` | `prefix v` | Vi-style paste |
| **Detach** | `prefix d` | `prefix :detach` | `d` is used for clear screen |
| **Clock** | `prefix t` | `prefix :clock-mode` | `t` is used for new window |
| **Display pane numbers** | `prefix q` | - | `q` sends `Ctrl-C` |

### gmux additions

| Action | gmux | Notes |
| --- | --- | --- |
| **Clear screen** | `prefix d` | Clears screen, scrollback, and refreshes prompt |
| **Clear with message** | `prefix C-k` | Clears screen and scrollback with confirmation |
| **Clear visible screen** | `prefix M-k` | Keeps scrollback |
| **Passthrough clear** | `prefix C-l` | Sends raw `C-l` to the shell |
| **Interrupt command** | `prefix q` | Sends `Ctrl-C` to the active pane |
| **Reorder window** | `prefix <` / `prefix >` | Move current window left or right |
| **Refresh panes** | `prefix r` | Skips running agents and dev servers |
| **Reload config** | `prefix R` | Source `tmux.conf` without restarting |
| **Rename pane** | `prefix T` | Name the current pane |
| **Half-zoom** | `prefix V` | Toggle vertical half-zoom for the current pane column |
| **Cycle pane size** | `prefix M-H/J/K/L` | Cycle width or height through 1/3, 1/2, 2/3 |
| **Split above** | `prefix M--` | Create a pane above the current one |
| **Full-height split** | `prefix \|` | Vertical split spanning horizontal panes |
| **Grab scrollback** | `prefix g` | Copy entire scrollback to clipboard |
| **Save session** | `prefix C-s` | tmux-resurrect save |
| **Restore session** | `prefix C-r` | tmux-resurrect restore |
| **Linked session** | `C-x` | Second view into the same session |
| **Offload cohort** | `prefix S` | Open tmux-cohort offload popup |
| **Restore cohort** | `prefix O` | Open tmux-cohort restore popup |

### Ghostty Shortcuts

These bypass tmux prefix by sending Meta sequences from Ghostty.

| Shortcut | Action |
| --- | --- |
| `Cmd+1` / `Cmd+2` | Previous / next window |
| `Cmd+Shift+[` / `Cmd+Shift+]` | Previous / next window |
| <code>Cmd+`</code> | Cycle clockwise through panes |
| `Cmd+3` | Cycle counter-clockwise through panes |
| `Opt+Cmd+1` / `Opt+Cmd+2` | Reorder window left / right |
| `Cmd+Shift+K` | Clear screen and scrollback |
| `Cmd+H/J/K/L` | Move focus left / down / up / right |
| `Opt+Cmd+H/J/K/L` | Swap pane left / down / up / right and follow focus |
| `Cmd+P` | Recursive split |
| `Cmd+Shift+P` | Copy current pane path |
| `Hyper+M` | Toggle pane zoom |

## Development Checks

```sh
bash tests/agent-detector-test.sh
bash -n dotfiles/tmux/scripts/*.sh tests/*.sh
docker build -t gmux-test .
```

## Stack

- [Ghostty](https://ghostty.org): GPU-accelerated terminal
- [tmux](https://github.com/tmux/tmux): terminal multiplexer
- [TPM](https://github.com/tmux-plugins/tpm): tmux plugin manager
- [Tokyo Night](https://github.com/folke/tokyonight.nvim): color palette
