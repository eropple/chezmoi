# pattern: Imperative Shell
# Modern zsh configuration entry point
# Source this from ~/.zshrc: source "$HOME/.config/zsh-ng/zshrc.zsh"

# Establish base directory
export ZSH_NG="${${(%):-%x}:A:h}"

# Starship config is generated to ~/.config/starship.toml by colors.zsh
# Unset any old STARSHIP_CONFIG to use the default location
unset STARSHIP_CONFIG

# Source configuration files in order
# 1. Core options and settings
source "$ZSH_NG/config/options.zsh"

# 2. Platform-specific setup (may modify PATH)
source "$ZSH_NG/config/platform.zsh"

# 3. Auto-detect tool paths
source "$ZSH_NG/config/paths.zsh"

# 4. Key bindings
source "$ZSH_NG/config/keybindings.zsh"

# 5. Compute hostname colors (before Starship init)
source "$ZSH_NG/config/colors.zsh"

# 6. Initialize tools (mise, starship, zoxide, fzf)
source "$ZSH_NG/tools/init.zsh"

# 7. Set up Antidote plugin manager
# Antidote is installed via mise: mise use -g antidote
if [[ -n "$MISE_ANTIDOTE_INSTALL_PATH" ]]; then
    source "$MISE_ANTIDOTE_INSTALL_PATH/antidote.zsh"
elif command -v antidote &>/dev/null; then
    source "$(antidote home)/antidote.zsh" 2>/dev/null || true
elif [[ -f "$HOME/.antidote/antidote.zsh" ]]; then
    source "$HOME/.antidote/antidote.zsh"
fi

# Load plugins if antidote is available
if (( $+functions[antidote] )); then
    # Generate static plugin file if plugins.txt is newer
    local plugins_txt="$ZSH_NG/plugins.txt"
    local plugins_zsh="${ZDOTDIR:-$HOME}/.zsh_plugins.zsh"

    if [[ ! -f "$plugins_zsh" || "$plugins_txt" -nt "$plugins_zsh" ]]; then
        antidote bundle < "$plugins_txt" > "$plugins_zsh"
    fi

    source "$plugins_zsh"
fi

# 8. Aliases (after plugins so they can override if needed)
source "$ZSH_NG/config/aliases.zsh"
