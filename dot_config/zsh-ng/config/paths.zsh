# pattern: Imperative Shell
# Auto-detect and add tool paths to $PATH

# Directories to check and add if they exist
local -a tool_paths=(
    "$HOME/.cargo/bin"       # Rust (rustup)
    "$HOME/go/bin"           # Go binaries
    "$HOME/.local/bin"       # Common user bin (pipx, etc.)
    "$HOME/.deno/bin"        # Deno
    "$HOME/.bun/bin"         # Bun
    "$HOME/.npm-global/bin"  # npm global (manual prefix)
    "$HOME/.npm/bin"         # npm global (alternate)
)

for p in "${tool_paths[@]}"; do
    # Add to path if directory exists and not already in path
    if [[ -d "$p" ]] && [[ ":$PATH:" != *":$p:"* ]]; then
        path=("$p" $path)
    fi
done
