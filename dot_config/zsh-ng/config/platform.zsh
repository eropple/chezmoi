# pattern: Imperative Shell
# Platform-specific configuration based on $OSTYPE

case "$OSTYPE" in
    darwin*)
        # macOS-specific settings

        # Homebrew (if installed, for system packages only)
        if [[ -x /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi

        # GNU coreutils from Homebrew (if installed)
        if [[ -d /opt/homebrew/opt/coreutils/libexec/gnubin ]]; then
            path=(/opt/homebrew/opt/coreutils/libexec/gnubin $path)
        fi
        ;;

    linux*)
        # Linux-specific settings

        # WSL detection
        if [[ -n "$WSL_DISTRO_NAME" ]]; then
            # WSL-specific settings
            :
        fi
        ;;
esac
