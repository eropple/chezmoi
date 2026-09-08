# pattern: Imperative Shell
# Key bindings

# Use emacs-style keybindings
bindkey -e

# macOS terminal navigation
bindkey '^[[H' beginning-of-line      # Home
bindkey '^[[F' end-of-line            # End
bindkey '^[[4~' end-of-line           # fn-right (some terminals)
bindkey '^[[1~' beginning-of-line     # fn-left (some terminals)
bindkey '\e[1;9D' backward-word       # alt-left
bindkey '\e[1;9C' forward-word        # alt-right
bindkey '^[[1;5D' backward-word       # ctrl-left
bindkey '^[[1;5C' forward-word        # ctrl-right

# History search with up/down arrows
bindkey '^[[A' history-beginning-search-backward  # Up
bindkey '^[[B' history-beginning-search-forward   # Down

# Delete key
bindkey '^[[3~' delete-char
