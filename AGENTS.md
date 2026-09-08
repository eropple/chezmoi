# Chezmoi operating guide

## Contract

- Source checkout: `~/.chezmoi`, remote `git@github.com:eropple/chezmoi.git`.
- Git distributes source; chezmoi deploys files. Pushing does not update other machines automatically.
- `~/.zshrc` is deliberately UNMANAGED. It loads deployed `~/.config/zsh-ng/zshrc.zsh`, not the checkout. Preserve local settings and credential integration when editing it.
- Stage and review first. Never run apply, installation scripts, or overwrite existing files without the operator's approval. Back up affected live files AND symlink targets before cutover.
- On the original machine, do not read anything beneath `.local` without new explicit permission. References to paths there are not permission to inspect their contents. Never source the live `.zshrc` during investigation: it loads secrets.
- Leave the old `~/dotfiles-ng` intact during migration. Legacy `zsh` and Zed are excluded.
- No automatic install hooks or external downloads are configured. Tool installation is separate and explicit.

## Layout

`dot_config/zsh-ng/` deploys to `~/.config/zsh-ng/`; `dot_vimrc` to `~/.vimrc`; `dot_gitconfig` to `~/.gitconfig`, and so on. `dot_config` also contains mise, Ghostty, and Zellij settings. `dot_tmux.conf` and `dot_editorconfig` are shared.

`AGENTS.md`, `README.md`, and `examples/` are excluded from deployment by `.chezmoiignore`. `examples/zshrc` is an example to merge manually, never a managed target.

The Starship `starship.toml.template` is a literal runtime input, NOT a chezmoi `.tmpl` file. Shell startup generates Starship config and its color cache. Antidote generates `.zsh_plugins.zsh`. Do not add those outputs, downloaded plugins, Vim runtime distributions, histories, databases, backups, credentials, or tool binaries.

## New machine: from download to working setup

1. Install Git, chezmoi, Zsh, Vim, and curl using a trusted method appropriate to the OS. Set up GitHub SSH authentication and verify GitHub's host key. Never disable host-key checking. A clone alone does not install or activate configuration.
2. Clone if not already downloaded:
   ```sh
   git clone git@github.com:eropple/chezmoi.git "$HOME/.chezmoi"
   ```
   If already downloaded elsewhere, deliberately choose the source path; examples assume `~/.chezmoi`.
3. Configure chezmoi to use this source. Create or merge into `~/.config/chezmoi/chezmoi.toml` (do not overwrite existing configuration):
   ```toml
   sourceDir = "~/.chezmoi"
   ```
   Until configured, pass `--source "$HOME/.chezmoi"` on every command. Optional host data belongs in this local config, not in Git.
4. Review this repository and local differences:
   ```sh
   chezmoi --source "$HOME/.chezmoi" managed
   chezmoi --source "$HOME/.chezmoi" diff
   chezmoi --source "$HOME/.chezmoi" apply --dry-run --verbose
   ```
   Inspect existing symlinks and back up both their link definitions and target contents outside the repository. In particular, the original machine has symlinks into `~/dotfiles-ng`. Do not assume replacing them is harmless. Verify Git identity, work includes, credential helpers, and application availability. Do not publish diffs containing private local data.
5. After explicit approval, apply selected targets first or all reviewed targets:
   ```sh
   chezmoi --source "$HOME/.chezmoi" apply
   ```
   This deploys settings, not applications or plugins. It does NOT create `.zshrc`.
6. Install mise using its current official instructions. Review `~/.config/mise/config.toml`, then run `mise install` to install the declared tools. Versions currently use `latest`; they are not a reproducible lock.
7. If shell plugins are wanted, install Antidote into `~/.antidote` from `https://github.com/mattmc3/antidote.git` after reviewing/trusting that source. Shared shell startup detects it and bundles the plugin list. Without it, basic shell configuration still loads.
8. If Vim plugins are wanted, install vim-plug into `~/.vim/autoload/plug.vim` using the current instructions at `https://github.com/junegunn/vim-plug`, then run `:PlugInstall` in Vim. Plain Vim must work without it. Do not copy old plugin directories or Vim distribution files. Ghostty's configured font (IBM Plex Mono) must be installed separately or changed locally.
9. Back up existing `.zshrc`. Merge `examples/zshrc` into it, replacing old shared-loader and duplicate mise initialization lines, while preserving machine-local additions. Pre-initialization prompt settings go above the shared loader; local integrations go below. Do not retain old `NG_DOTFILES_ROOT`/`ZSH_NG` exports merely to load this configuration. Check whether other local scripts still need them before removing them wholesale.
10. Provision secrets separately. The original machine uses 1Password-backed environment loading; do not copy its service-account token, assume its paths exist, or commit resolved environment values. Decide which machines actually require that integration.
11. Keep the current terminal open. Check `zsh -n ~/.zshrc`, open a separate terminal, and verify prompt, completion, direnv where installed, and `vim`. Check `git config --show-origin --get user.email` and authentication separately; config deployment does not authenticate Git.

Recovery: restore affected files and symlinks from the pre-cutover backup and restore the previous `.zshrc` loader. The old dotfiles directory is intentionally retained. A Git revert alone does not restore overwritten unmanaged content; preview and apply the reverted source only after review.

## Daily workflow and syncing

```sh
chezmoi edit ~/.config/zsh-ng/config/aliases.zsh
chezmoi diff
chezmoi apply                 # after reviewing
git -C ~/.chezmoi diff
git -C ~/.chezmoi add <specific-source-files>
git -C ~/.chezmoi commit -m "Describe the configuration change"
git -C ~/.chezmoi push
```

On another machine, use `git -C ~/.chezmoi pull --ff-only`, then `chezmoi diff`, then approved `chezmoi apply`. `chezmoi update` combines pulling and applying: use it only when intentional. Resolve Git conflicts in source, never by blindly forcing an apply. If you edit a deployed file directly, inspect and re-add that specific file to source; otherwise a later apply can overwrite it.

## Adding shared files

1. Inspect the exact file for secrets, host paths, vendor content, and generated state. Never recursively add home or the old dotfiles universe.
2. For a safe regular file, `chezmoi add ~/.config/example/config` imports it into source without deploying. Inspect the resulting source and `chezmoi diff` before committing. Existing symlinks need explicit review: do not accidentally manage a link back to the old checkout instead of the desired content.
3. Use chezmoi naming (`dot_`, `private_`, `executable_`, `.tmpl`) deliberately. `private_` controls destination permissions, NOT encryption or Git secrecy.
4. Test the affected target and stage only intended source paths. Never use `chezmoi add ~/.zshrc`.

## Machine-specific settings and files

Prefer shared defaults plus supported local overrides. Shell-only local settings belong in unmanaged `.zshrc`; no separate branches per machine.

For templates, put non-secret per-machine values in local `~/.config/chezmoi/chezmoi.toml`:
```toml
[data]
profile = "personal"
```
A managed `dot_config/example/config.tmpl` can use `{{ .profile }}`. If a field is required, document it in this setup checklist before adding the template; otherwise supply an explicit safe default, e.g. `{{ default "personal" (index . "profile") }}`. Built-in `{{ .chezmoi.os }}` supports OS-dependent content without local data.

To deploy a file only on macOS, place it in source and add to `.chezmoiignore`:
```gotemplate
{{ if ne .chezmoi.os "darwin" }}
.config/example/mac-only.conf
{{ end }}
```
Ignore patterns use DESTINATION names, not `dot_` source names. Ignoring a formerly managed file does not automatically remove its existing deployed copy; review any cleanup explicitly. For host-specific files use an explicit local profile/flag where possible rather than accumulating hostname checks. Keep the file entirely unmanaged if it is truly local or sensitive.

## SSH authorized keys

`private_dot_ssh/private_authorized_keys` manages the complete `~/.ssh/authorized_keys` on EVERY machine, by explicit operator choice. The private attributes request directory mode 0700 and file mode 0600. The directory is not `exact_`: other SSH files are not managed or deleted by this entry. Never import private keys or the whole `.ssh` directory.

Before first apply on a new machine, compare its existing authorized keys with the shared list and back up the file and any symlink target. Applying replaces the list; it does not merge machine-local entries. Confirm that granting every listed key access to that machine is intended. The initial list has 20 public keys without identifying comments; key ownership has not been independently verified.

Adding or removing a shared key changes login access on every machine that subsequently pulls and applies. Preserve key options/restrictions exactly, review fingerprints with `ssh-keygen -lf`, and record owners in comments when known. Public keys are not private secrets, but the access list is security-sensitive metadata. Revoking a key in Git alone does not revoke access on machines that have not applied the update.

During cutover, keep the current SSH session open and test a second connection before disconnecting. SSH daemon configuration, account policy, and other authorized-key sources can affect access; this repository does not configure them. On platforms with different SSH permission conventions, review applicability before applying.

## Secrets and privacy

Private Git repositories are not secret stores. Never commit tokens, private keys, kubeconfigs, Git credential-store files, resolved `.env` files, or 1Password output. Audit secret-reference templates before sharing too: identifiers and vault paths can be private metadata. Do not automatically migrate the original plaintext Git `store` helper behavior. Configure an appropriate credential helper per machine. Git identity and work paths are personal metadata and must be reviewed before making the repository public.

## Verification expectations

Run syntax checks without executing credential loading. Review chezmoi's managed target list to ensure `.zshrc`, documentation, examples, and generated files are absent. Preview changes before applying. For staging under the original `.local` read restriction, use an explicit config, source, cache, and persistent-state location outside `.local`; do not inspect chezmoi's default source or state there. Report exactly what was checked and what still requires a real cutover test.
