# ===============================================
# FZF-TAB CONFIGURATION
# ===============================================

# Disable sort when completing `git checkout`
zstyle ':completion:*:git-checkout:*' sort false

# Set descriptions format to enable group support
zstyle ':completion:*:descriptions' format '[%d]'

# Set list-colors to enable filename colorizing
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# Force zsh not to show completion menu, which allows fzf-tab to capture the unambiguous prefix
zstyle ':completion:*' menu no

# Preview directory's content with ls when completing cd (you can install eza for better preview)
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'echo "Current: $PWD\nTarget: $realpath" && ls -1 --color=always $realpath 2>/dev/null || ls -1 $realpath'

# Switch group using `<` and `>`
zstyle ':fzf-tab:*' switch-group '<' '>'

# Case-insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

# Use single column layout for better vertical display with continuous completion
zstyle ':fzf-tab:*' fzf-flags --layout=reverse --height=40% --border --bind='ctrl-/:toggle-preview,ctrl-j:accept'

# Enable continuous completion with / key
zstyle ':fzf-tab:*' continuous-trigger '/'

# Custom bindings for fzf-tab - auto-accept directories on selection
zstyle ':fzf-tab:*' fzf-bindings 'ctrl-j:accept,ctrl-space:toggle+down'
zstyle ':fzf-tab:complete:cd:*' accept-line enter
zstyle ':fzf-tab:complete:cd:*' fzf-bindings 'enter:accept'

# Show parent directories in cd completion for easier navigation
zstyle ':completion:*:cd:*' ignore-parents parent
# Note: We removed 'pwd' so current directory shows up for reference

# Enable directory stack completion
setopt AUTO_PUSHD          # Automatically push directories to stack
setopt PUSHD_IGNORE_DUPS   # Don't push duplicates
setopt PUSHD_SILENT        # Don't print directory stack after pushd/popd

# Add common useful directories to CDPATH for quick access
export CDPATH=".:$HOME:$HOME/Desktop:$HOME/Documents:$HOME/Downloads"

# ===============================================
# AUTO-TRIGGER FZF-TAB FOR CD AND PACKAGE COMMANDS
# ===============================================

# Custom widget that auto-triggers fzf-tab for cd and package manager commands
auto-fzf-trigger() {
    # Add space to buffer
    LBUFFER="${LBUFFER} "
    
    # Check if the current line matches any of our trigger patterns
    # CD command - trigger on double space
    if [[ "$LBUFFER" == "cd  " ]]; then
        # Auto-trigger fzf-tab specifically (not native completion)
        zle fzf-tab-complete
    # Package manager commands - trigger on double space
    elif [[ "$LBUFFER" == "npm  " ]] || \
         [[ "$LBUFFER" == "npm run  " ]] || \
         [[ "$LBUFFER" == "pnpm  " ]] || \
         [[ "$LBUFFER" == "pn  " ]] || \
         [[ "$LBUFFER" == "yarn  " ]] || \
         [[ "$LBUFFER" == "bun  " ]] || \
         [[ "$LBUFFER" == "b  " ]] || \
         [[ "$LBUFFER" == "br  " ]]; then
        # Auto-trigger fzf-tab for package manager commands
        zle fzf-tab-complete
    fi
}

# Create the widget
zle -N auto-fzf-trigger

# Bind space key to our custom widget
bindkey ' ' auto-fzf-trigger

# Smart "up" navigation widget
cd-up-smart() {
    local current_dir="$PWD"
    
    # If we're in home directory, show common directories
    if [[ "$current_dir" == "$HOME" ]]; then
        BUFFER="cd "
        CURSOR=${#BUFFER}
        zle fzf-tab-complete
        return
    fi
    
    # Get parent directory
    local parent_dir="$(dirname "$current_dir")"
    
    # If parent exists, show parent directory contents with current dir highlighted
    if [[ -d "$parent_dir" ]]; then
        BUFFER="cd $parent_dir/"
        CURSOR=${#BUFFER}
        zle fzf-tab-complete
    fi
}

# Directory stack navigation widget  
cd-stack-smart() {
    # Show directory stack with fzf-tab
    BUFFER="cd -"
    CURSOR=${#BUFFER}
    zle fzf-tab-complete
}

# Recent directories widget (using cd history)
cd-recent-smart() {
    # Show recent directories from cd history
    BUFFER="cd "
    CURSOR=${#BUFFER}
    # This will show recent paths if you have CDPATH or directory stack
    zle fzf-tab-complete
}

# Create the widgets
zle -N cd-up-smart
zle -N cd-stack-smart  
zle -N cd-recent-smart

# Bind convenient keys for smart navigation
bindkey '^[[1;5A' cd-up-smart      # Ctrl+Up Arrow = go up smartly
bindkey '^[u' cd-up-smart          # Alt+U = go up smartly
bindkey '^[s' cd-stack-smart       # Alt+S = directory stack
bindkey '^[r' cd-recent-smart      # Alt+R = recent directories

# ===============================================
# PACKAGE.JSON SCRIPTS COMPLETION
# ===============================================

# Function to get package.json scripts
_get_package_scripts() {
    if [[ -f "package.json" ]]; then
        # Extract script names from package.json using jq if available, otherwise use a simple grep approach
        if command -v jq >/dev/null 2>&1; then
            jq -r '.scripts | keys[]' package.json 2>/dev/null
        else
            # Fallback: simple parsing without jq
            grep -A 100 '"scripts"' package.json 2>/dev/null | \
            grep -E '^\s*"[^"]+":' | \
            sed -E 's/^\s*"([^"]+)".*/\1/' | \
            grep -v '^scripts$'
        fi
    fi
}

# Custom completion for package managers with scripts
_package_manager_completion() {
    local context curcontext="$curcontext" state line
    local -a scripts
    
    # Get scripts from package.json
    if [[ -f "package.json" ]]; then
        scripts=(${(f)"$(_get_package_scripts)"})
    fi
    
    # Standard npm/pnpm/yarn/bun commands
    local -a common_commands
    case $words[1] in
        npm)
            common_commands=(
                'install:Install dependencies'
                'run:Run a script'
                'start:Start the application'
                'test:Run tests'
                'build:Build the project'
                'dev:Start development server'
                'lint:Run linter'
                'format:Format code'
                'clean:Clean build artifacts'
                'audit:Run security audit'
                'update:Update dependencies'
                'outdated:Show outdated packages'
            )
            ;;
        pnpm|pn)
            common_commands=(
                'install:Install dependencies'
                'add:Add a dependency'
                'run:Run a script'
                'start:Start the application'
                'test:Run tests'
                'build:Build the project'
                'dev:Start development server'
                'lint:Run linter'
                'format:Format code'
                'clean:Clean build artifacts'
                'audit:Run security audit'
                'update:Update dependencies'
                'outdated:Show outdated packages'
                'dlx:Execute a package'
            )
            ;;
        yarn)
            common_commands=(
                'install:Install dependencies'
                'add:Add a dependency'
                'run:Run a script'
                'start:Start the application'
                'test:Run tests'
                'build:Build the project'
                'dev:Start development server'
                'lint:Run linter'
                'format:Format code'
                'clean:Clean build artifacts'
                'audit:Run security audit'
                'upgrade:Update dependencies'
                'outdated:Show outdated packages'
                'dlx:Execute a package'
            )
            ;;
        bun|b)
            common_commands=(
                'install:Install dependencies'
                'add:Add a dependency'
                'run:Run a script'
                'start:Start the application'
                'test:Run tests'
                'build:Build the project'
                'dev:Start development server'
                'lint:Run linter'
                'format:Format code'
                'clean:Clean build artifacts'
                'update:Update dependencies'
                'outdated:Show outdated packages'
                'x:Execute a package'
            )
            ;;
        br)
            # For "bun run" alias, only show scripts
            common_commands=()
            ;;
    esac
    
    # Combine scripts and commands
    local -a all_options
    if [[ ${#scripts[@]} -gt 0 ]]; then
        for script in $scripts; do
            # Escape colons in script names since _describe uses : as separator
            local escaped_script="${script//:/\\:}"
            all_options+=("$escaped_script:📜 package.json script")
        done
    fi
    
    # Add common commands for non-run aliases
    if [[ $words[1] != "br" ]]; then
        all_options+=($common_commands)
    fi
    
    _describe 'commands' all_options
}

# Register completions for package managers
compdef _package_manager_completion npm
compdef _package_manager_completion pnpm
compdef _package_manager_completion pn
compdef _package_manager_completion yarn
compdef _package_manager_completion bun
compdef _package_manager_completion b
compdef _package_manager_completion br

# Enhanced fzf-tab styling for package manager completions
zstyle ':fzf-tab:complete:(npm|pnpm|pn|yarn|bun|b|br):*' fzf-preview '
    # Show package.json script content if it exists
    if [[ -f "package.json" && "$word" != "" ]]; then
        echo "=== Script Details ==="
        if command -v jq >/dev/null 2>&1; then
            script_cmd=$(jq -r ".scripts.\"$word\"" package.json 2>/dev/null)
            if [[ "$script_cmd" != "null" && "$script_cmd" != "" ]]; then
                echo "📜 Script: $word"
                echo "🔧 Command: $script_cmd"
                echo ""
                echo "=== package.json preview ==="
                jq -r ".scripts" package.json 2>/dev/null | head -20
            else
                echo "📦 Package manager command: $word"
                echo ""
                echo "=== Available Scripts ==="
                jq -r ".scripts | to_entries | .[] | \"  \(.key): \(.value)\"" package.json 2>/dev/null | head -10
            fi
        else
            echo "📦 Command: $word"
            echo ""
            echo "=== package.json scripts ==="
            grep -A 20 "\"scripts\"" package.json 2>/dev/null | head -15
        fi
    else
        echo "📦 Package manager command: $word"
        echo ""
        echo "No package.json found in current directory"
    fi
'

# Group package manager completions
zstyle ':fzf-tab:complete:(npm|pnpm|pn|yarn|bun|b|br):*' fzf-flags '--header="Package Manager Commands & Scripts"'
