# pattern: Functional Core
# Shell aliases

# ls with colors (works on both GNU and BSD ls)
if command -v gls &>/dev/null; then
    alias ls="gls -F --color=auto"
elif ls --color=auto &>/dev/null 2>&1; then
    alias ls="ls -F --color=auto"
else
    alias ls="ls -F -G"  # BSD ls color flag
fi

alias ll="ls -lh"
alias la="ls -lah"

# Reload shell config
alias rezsh="source ~/.zshrc"

# Open dotfiles in editor
alias zshcode='${EDITOR:-code} "$ZSH_NG"'

# Kill all mosh sessions that aren't me
alias demosh='_mypid=$(ps -o ppid= -p $$ | tr -d " "); while [ "$_mypid" != "1" ]; do ps -o comm= -p $_mypid 2>/dev/null | grep -q mosh-server && break; _mypid=$(ps -o ppid= -p $_mypid | tr -d " "); done; pgrep -u $(whoami) mosh-server | while read pid; do [ "$pid" != "$_mypid" ] && kill "$pid"; done'

# Claude Code with permissions bypass
if command -v claude &>/dev/null; then
    alias dangerclaude="claude --dangerously-skip-permissions"
fi
