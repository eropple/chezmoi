# Shared dotfiles

Chezmoi source: `~/.chezmoi`. Remote: `git@github.com:eropple/chezmoi.git`.

Read [AGENTS.md](AGENTS.md) for setup on a new machine, daily syncing, adding files, local overrides, secrets policy, and recovery.

`~/.zshrc` is intentionally unmanaged. Merge [examples/zshrc](examples/zshrc) into it only after shared files are deployed and existing configuration is backed up.

Configuration deployment does not install applications or plugins. No automatic installation hooks are included. The original `~/dotfiles-ng` should remain intact during migration.
