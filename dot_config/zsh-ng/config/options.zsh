# pattern: Functional Core
# Zsh options and settings

# History configuration
HISTFILE="${ZDOTDIR:-$HOME}/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000

setopt HIST_IGNORE_DUPS      # Don't record duplicate entries
setopt HIST_IGNORE_ALL_DUPS  # Remove older duplicate entries
setopt HIST_SAVE_NO_DUPS     # Don't write duplicates to history file
setopt HIST_REDUCE_BLANKS    # Remove excess blanks before saving
setopt INC_APPEND_HISTORY    # Write to history immediately
setopt SHARE_HISTORY         # Share history between sessions
setopt EXTENDED_HISTORY      # Record timestamp with history

# Directory navigation
setopt AUTO_CD               # cd by typing directory name
setopt AUTO_PUSHD            # Push directories onto stack
setopt PUSHD_IGNORE_DUPS     # Don't push duplicates
setopt PUSHD_SILENT          # Don't print directory stack

# Completion
setopt COMPLETE_IN_WORD      # Complete from both ends of word
setopt ALWAYS_TO_END         # Move cursor to end after completion
setopt AUTO_MENU             # Show completion menu on tab
setopt LIST_PACKED           # Compact completion lists

# Globbing
setopt EXTENDED_GLOB         # Extended pattern matching
setopt NO_CASE_GLOB          # Case-insensitive globbing

# Misc
setopt INTERACTIVE_COMMENTS  # Allow comments in interactive shell
setopt NO_BEEP               # Disable beep

# Make word-based operations (ctrl-w, alt-backspace) stop at path separators
WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'

# zsh-autosuggestions configuration (set before plugin loads)
ZSH_AUTOSUGGEST_STRATEGY=(history)       # Use history (most recent first)
ZSH_AUTOSUGGEST_USE_ASYNC=1              # Async mode
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20       # Don't suggest for very long lines

# Completion system initialization
autoload -Uz compinit
compinit -C  # -C skips security check for faster startup

# Enable completion caching
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"
