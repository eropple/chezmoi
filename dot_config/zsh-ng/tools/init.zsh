# pattern: Imperative Shell
# Initialize modern shell tools

# 1Password CLI service-account token (machine-local, never committed).
# ~/.local/1password_token holds the token on machines provisioned for it.
# Export only if not already set in the environment.
if [[ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" && -r "$HOME/.local/1password_token" ]]; then
    ZSH_NG_OP_TOKEN="$(< "$HOME/.local/1password_token")"
    if [[ -n "$ZSH_NG_OP_TOKEN" ]]; then
        export OP_SERVICE_ACCOUNT_TOKEN="$ZSH_NG_OP_TOKEN"
    fi
    unset ZSH_NG_OP_TOKEN
fi

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
