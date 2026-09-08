# pattern: Imperative Shell
# Initialize modern shell tools

# Ensure mise-installed tools are discoverable before activation
export PATH="$HOME/.local/bin:$PATH"

# mise - version manager (replaces asdf)
# Should be activated early to make tools available
if command -v mise &>/dev/null; then
    eval "$(mise activate zsh)"
fi

# Starship prompt
if command -v starship &>/dev/null; then
    eval "$(starship init zsh)"
fi

# zoxide - smarter cd
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi

# fzf - fuzzy finder
if command -v fzf &>/dev/null; then
    # Set up fzf key bindings and completion
    eval "$(fzf --zsh 2>/dev/null || true)"
fi

# kubie - kubernetes context/namespace isolation per shell
if command -v kubie &>/dev/null; then
    source <(kubie generate-completion zsh)
fi
