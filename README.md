# gmux

**Ghostty x tmux configuration for agentic coding.** Run coding agents, dev
servers, and shells in one terminal workspace — agent activity in the status
bar, live port markers, and Cmd shortcuts for tmux. Plain dotfiles and shell
scripts.

<p>
  <a href="https://claude.com/claude-code"><img src="assets/logos/claude.svg" alt="Claude Code"></a>&nbsp;&nbsp;
  <a href="https://github.com/openai/codex"><img src="assets/logos/codex.svg" alt="Codex CLI"></a>&nbsp;&nbsp;
  <a href="https://github.com/google-gemini/gemini-cli"><img src="assets/logos/gemini.svg" alt="Gemini CLI"></a>&nbsp;&nbsp;
  <a href="https://opencode.ai"><img src="assets/logos/opencode.svg" alt="opencode"></a>&nbsp;&nbsp;
  <a href="https://cursor.com"><img src="assets/logos/cursor.svg" alt="Cursor Agent"></a>&nbsp;&nbsp;
  <a href="https://github.com/features/copilot/cli"><img src="assets/logos/copilot.svg" alt="Copilot CLI"></a>&nbsp;&nbsp;
  <a href="https://ampcode.com"><img src="assets/logos/amp.svg" alt="Amp"></a>&nbsp;&nbsp;
  <a href="https://factory.ai"><img src="assets/logos/droid.svg" alt="Droid"></a>&nbsp;&nbsp;
  <a href="https://x.ai"><img src="assets/logos/grok.svg" alt="Grok CLI"></a>&nbsp;&nbsp;
  <a href="https://kiro.dev"><img src="assets/logos/kiro.svg" alt="Kiro"></a>&nbsp;&nbsp;
  <a href="https://github.com/MoonshotAI/kimi-cli"><img src="assets/logos/kimi.svg" alt="Kimi CLI"></a>&nbsp;&nbsp;
  <a href="https://cline.bot"><img src="assets/logos/cline.svg" alt="Cline"></a>
</p>

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
- **Focus and templates**: spotlight the current pane in a popup, or launch a
  repeatable workspace from JSON templates.
- **Usage header**: the top-right status can show Codex, Claude, Cursor, and
  daily spend through CodexBar.

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
rm -rf ~/.tmux/scripts
cp -R dotfiles/tmux/scripts ~/.tmux/scripts
chmod +x ~/.tmux/scripts/*.sh
mkdir -p ~/.config/gmux
cp -R dotfiles/config/gmux/templates ~/.config/gmux/templates
```

Optional Ghostty, zsh, and legacy template files:

```sh
mkdir -p ~/.config/ghostty ~/.config/zsh ~/.config/tmux-gmux
cp dotfiles/config/ghostty/config ~/.config/ghostty/config
cp dotfiles/config/zsh/fzf-tab-config.zsh ~/.config/zsh/fzf-tab-config.zsh
cp -R dotfiles/config/tmux-gmux/templates ~/.config/tmux-gmux/templates
```

Start tmux normally:

```sh
tmux
```

## Test in Docker

```sh
docker build -t gmux-test .
docker run -it --rm gmux-test
```

## What's Inside

| Layer | File | Purpose |
| --- | --- | --- |
| Ghostty | `dotfiles/config/ghostty/config` | Cmd-key to tmux Meta passthrough, Tokyo Night theme, background blur |
| tmux | `dotfiles/tmux.conf` | Single merged tmux config: theme, status bar, hooks, plugins, keybindings |
| tmux scripts | `dotfiles/tmux/scripts/` | Agent detection, spinner, port watcher, pane/layout helpers, refresh helpers |
| gmux templates | `dotfiles/config/gmux/templates/` | JSON workspace templates used by `prefix G` |
| legacy templates | `dotfiles/config/tmux-gmux/templates/` | Compatibility templates for older `tmux-templates.sh` notes |
| zsh | `dotfiles/zshrc` | omz, git aliases, Claude Code environment |
| zsh | `dotfiles/config/zsh/fzf-tab-config.zsh` | fzf-tab completion styling |
| Docker | `Dockerfile` | Sandboxed test environment with the full gmux stack |

## Features

### Agent Working Indicator

`tmux-agent-spinner.sh` is a single self-contained daemon with two loops. A
scanner checks every few seconds whether any pane in a window is running an
agent that is actively working (live spinner in the pane title, or an
"esc to interrupt" footer in a Claude/Codex pane) and marks the window busy.
An animator then spins a braille glyph in the window tab at ~8 fps while any
window is busy — animation never blocks on detection.

The scanner applies hysteresis: a busy window must look idle for three
consecutive scans before its spinner stops. That bridges the short gaps
between tool calls and turn transitions, so the indicator runs continuously
from task start to finish instead of flickering on and off.

The status bar reads only tmux variables (`@busy`, `@spin`, `@wname`) — no
shell forks inside format strings.

### Usage Header

`tmux-codexbar-usage.sh` updates `@codexbar_usage`, rendered in the top-right
status header as:

```text
cdx -- | cl -- | cur -- | spend --
```

When CodexBar is installed, those four slots become Codex usage, Claude usage,
Cursor usage, and total daily spend. The script is intentionally best-effort:
without CodexBar or `jq`, the header stays present with `--` placeholders.

`tmux-agent-detect.sh` provides the deeper process-tree detection (direct
binaries, common wrapper names, symlinked launchers, and runtime launches
through `node`, `bun`, Python, or shells) used by the safe pane refresh. It
intentionally does not treat helper binaries like `codex-helper` or inert
`python -c` commands as agent sessions.

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
- `swap-pane-stay.sh`: swap pane contents in a direction while keeping the
  cursor in place.
- `resize-cycle.sh`: cycle the active pane through 1/3, 1/2, and 2/3 sizes.
- `half-zoom.sh`: toggle a vertical half-zoom inside the current column.
- `custom-zoom.sh`: toggle a larger non-fullscreen zoom for the current pane.
- `focus-mode.sh`: show the current pane in a temporary popup without reflowing
  the background layout.
- `tmux-cohort.sh`: restore named groups of sessions.

### Template Picker

`prefix G` opens `gmux-template-picker.sh`, which reads JSON files from
`~/.config/gmux/templates`. It previews the chosen workspace and creates or
switches to a session rooted at the current pane directory.

### Pane Layout Presets

One-keystroke layouts for agentic work, bound on the number row:

- `prefix 8` builds the three-pane work layout from a clean one-pane window:
  a left column split into editor over terminal, plus a full-height right
  pane. All panes inherit the current working directory.
- `prefix 9` weights the layout toward the top-left work pane: the left
  column gets 2/3 of the width and the top-left pane 2/3 of the height.
- `prefix (` mirrors that to the right: the right pane column gets 2/3 of
  the window width.
- `prefix 0` equalizes everything back to a tiled layout.

## Keybindings

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
| **Select window by number** | `prefix 0-9` | `prefix 1-7` | `8`, `9`, `(`, `0` are layout presets |

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
| **Custom zoom** | `prefix Z` | Toggle 80% zoom without hiding neighboring panes |
| **Focus popup** | `prefix S` / `prefix s` | Toggle a 90% popup for the current pane |
| **Session tree** | `prefix f` | Open the tmux session tree |
| **Template picker** | `prefix G` | Create or switch to a session from JSON templates |
| **Work layout preset** | `prefix 8` | Three-pane layout from a clean window (editor / terminal / full-height right) |
| **Weight top-left pane** | `prefix 9` | Left column 2/3 wide, top-left pane 2/3 tall |
| **Weight right column** | `prefix (` | Right pane column 2/3 of the window width |
| **Equalize panes** | `prefix 0` | Reset to tiled layout |
| **Cycle pane size** | `prefix M-H/J/K/L` | Cycle width or height through 1/3, 1/2, 2/3 |
| **Split above** | `prefix M--` | Create a pane above the current one |
| **Full-height split** | `prefix \|` | Vertical split spanning horizontal panes |
| **Grab scrollback** | `prefix g` | Copy entire scrollback to clipboard |
| **Save session** | `prefix C-s` | tmux-resurrect save |
| **Restore session** | `prefix C-r` | tmux-resurrect restore |
| **Linked session** | `C-x` | Second view into the same session |
| **Restore cohort** | `prefix O` | Open tmux-cohort restore popup |

### Ghostty Shortcuts

These bypass tmux prefix by sending Meta sequences from Ghostty.

| Shortcut | Action |
| --- | --- |
| `Cmd+1` / `Cmd+2` | Previous / next window; close Focus popup when active |
| <code>Cmd+`</code> | Cycle clockwise through panes |
| <code>Opt+`</code> | Rotate pane contents clockwise; rotate focused pane in Focus popup |
| `Cmd+3` | Previous pane |
| `Opt+Cmd+1` / `Opt+Cmd+2` | Reorder window left / right |
| `Cmd+Shift+K` | Clear screen and scrollback |
| `Cmd+Opt+K` | Clear visible screen, preserving history |
| `Cmd+H/J/K/L` | Move focus left / down / up / right |
| `Opt+H/J/K/L` | Swap pane contents left / down / up / right |
| `Opt+Shift+H/J/K/L` | Resize the pane line through thirds |
| `Cmd+P` | Recursive split |
| `Cmd+Shift+P` | Recursive split, vertical-first |
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
