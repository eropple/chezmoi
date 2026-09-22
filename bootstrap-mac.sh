#!/usr/bin/env bash
# Bootstrap a macOS machine for this dotfiles repository.
#
# Installs chezmoi, the 1Password CLI, and mise via Homebrew when missing
# (Homebrew performs its own download verification; formula versions are not
# pinned here), verifies GitHub's SSH host key, clones or fast-forward-
# updates ~/.chezmoi, writes the local chezmoi config, applies the dotfiles,
# and runs "mise install" for the declared shell tools (starship, zoxide,
# fzf, direnv, zellij). Any failed step is reported loudly and the script
# exits non-zero. Existing managed targets (including symlink targets) are
# backed up under ~/.chezmoi-backups before anything is overwritten, and
# directory symlinks sitting on a managed target's path (legacy
# ~/.config/ghostty or ~/.config/zellij style links) are backed up and
# removed so chezmoi writes real files instead of through the link. On a
# machine with no ~/.zshrc, one is created from examples/zshrc; it stays
# unmanaged. Idempotent: safe to re-run.
#
# Homebrew itself is NOT installed by this script; install it from
# https://brew.sh first if missing. This script does NOT install shells,
# antidote, vim-plug, fonts, or any other tooling; see AGENTS.md for those
# steps. Read AGENTS.md before running this anywhere except a fresh machine.
#
# Usage:
#   ./bootstrap-mac.sh [--op-service] [--no-apply]
#
#   --op-service   merge "[onepassword]" mode="service" prompt=false into the
#                  local chezmoi config. This is also added automatically when
#                  OP_SERVICE_ACCOUNT_TOKEN is already set in the environment.
#                  The token itself is never written to any file.
#   --no-apply     stop after cloning and config; do not apply dotfiles.
#
# Environment overrides: SOURCE_DIR.

set -euo pipefail

SOURCE_DIR="${SOURCE_DIR:-$HOME/.chezmoi}"
REPO_URL="git@github.com:eropple/chezmoi.git"
KNOWN_HOSTS="$HOME/.chezmoi-github-known-hosts"
CONFIG_FILE="$HOME/.config/chezmoi/chezmoi.toml"
BACKUP_ROOT="$HOME/.chezmoi-backups"
# Pinned from https://api.github.com/meta (Ed25519).
GITHUB_ED25519="AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
GITHUB_FINGERPRINT="SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"
GIT_SSH="ssh -o UserKnownHostsFile=$KNOWN_HOSTS -o StrictHostKeyChecking=yes"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

note() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'bootstrap: %s\n' "$*" >&2; exit 1; }

FAILURES=0
record_failure() {
  FAILURES=$((FAILURES + 1))
  warn "FAILURE ${FAILURES}: $*"
}

backup_file() {
  local dir="$BACKUP_ROOT/bootstrap-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dir"
  chmod 700 "$BACKUP_ROOT" "$dir"
  cp -a "$1" "$dir/"
  note "backed up $1 to $dir/"
}

require_brew() {
  command -v brew >/dev/null 2>&1 \
    || die "Homebrew is required but not on PATH. Install it from https://brew.sh, then re-run."
}

resolve_chezmoi() {
  if command -v chezmoi >/dev/null 2>&1; then
    CHEZMOI_BIN="$(command -v chezmoi)"
    return
  fi
  local candidate
  for candidate in /opt/homebrew/bin/chezmoi /usr/local/bin/chezmoi; do
    if [ -x "$candidate" ]; then
      CHEZMOI_BIN="$candidate"
      return
    fi
  done
  return 1
}

install_chezmoi() {
  if resolve_chezmoi; then
    note "chezmoi found: $CHEZMOI_BIN"
    return
  fi
  require_brew
  note "installing chezmoi via Homebrew"
  brew install chezmoi
  resolve_chezmoi || die "brew install chezmoi did not produce a chezmoi binary"
  note "installed $($CHEZMOI_BIN --version)"
}

install_op() {
  if command -v op >/dev/null 2>&1; then
    note "1Password CLI found: $(command -v op)"
    return
  fi
  require_brew
  note "installing 1Password CLI via Homebrew (formula: 1password-cli)"
  brew install 1password-cli
  if command -v op >/dev/null 2>&1; then
    note "installed 1Password CLI $(op --version)"
  else
    record_failure "1Password CLI not on PATH after brew install; 1Password-backed templates will fail"
  fi
}

resolve_mise() {
  if command -v mise >/dev/null 2>&1; then
    MISE_BIN="$(command -v mise)"
    return
  fi
  local candidate
  for candidate in /opt/homebrew/bin/mise /usr/local/bin/mise; do
    if [ -x "$candidate" ]; then
      MISE_BIN="$candidate"
      return
    fi
  done
  return 1
}

install_mise() {
  if resolve_mise; then
    note "mise found: $MISE_BIN"
    return
  fi
  require_brew
  note "installing mise via Homebrew"
  brew install mise
  resolve_mise || record_failure "brew install mise did not produce a mise binary"
}

run_mise_install() {
  [ -n "${MISE_BIN:-}" ] || { record_failure "mise unavailable; declared tools (starship, zoxide, fzf, direnv, zellij) not installed"; return; }
  note "running mise install for declared tools (starship, zoxide, fzf, direnv, zellij)"
  if "$MISE_BIN" install; then
    "$MISE_BIN" ls
  else
    record_failure "mise install failed; shell tools (starship, zoxide, fzf, direnv, zellij) are missing"
  fi
}

github_host_key() {
  if [ -f "$KNOWN_HOSTS" ] && grep -q '^github.com ' "$KNOWN_HOSTS"; then
    note "using existing GitHub known-hosts file: $KNOWN_HOSTS"
    return
  fi
  local meta_key
  meta_key="$(curl -fsSL --max-time 20 https://api.github.com/meta \
    | grep -o 'ssh-ed25519 [A-Za-z0-9+/=]\+' | head -n1 | cut -d' ' -f2 || true)"
  if [ -n "$meta_key" ]; then
    [ "$meta_key" = "$GITHUB_ED25519" ] \
      || die "GitHub's published Ed25519 key does not match the pinned key; verify api.github.com/meta manually before proceeding"
  else
    warn "could not reach api.github.com/meta; proceeding with the pinned key ($GITHUB_FINGERPRINT)"
  fi
  {
    echo "# GitHub SSH host key, verified against https://api.github.com/meta"
    echo "github.com ssh-ed25519 $GITHUB_ED25519"
  } > "$KNOWN_HOSTS"
  chmod 600 "$KNOWN_HOSTS"
  note "wrote $KNOWN_HOSTS"
}

check_github_auth() {
  local probe
  probe="$(ssh -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=yes \
    -o BatchMode=yes -T git@github.com 2>&1 || true)"
  case "$probe" in
    *"successfully authenticated"*) note "GitHub SSH authentication OK" ;;
    *) die "GitHub SSH authentication failed. Set up an SSH key authorized for github.com, then re-run. Details: $probe" ;;
  esac
}

sync_source() {
  if [ -e "$SOURCE_DIR" ]; then
    git -C "$SOURCE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
      || die "$SOURCE_DIR exists but is not a Git repository; inspect it before proceeding"
    local remote
    remote="$(git -C "$SOURCE_DIR" remote get-url origin)"
    [ "$remote" = "$REPO_URL" ] \
      || die "unexpected origin '$remote' in $SOURCE_DIR; expected $REPO_URL"
    [ -z "$(git -C "$SOURCE_DIR" status --porcelain)" ] \
      || die "$SOURCE_DIR has uncommitted changes; resolve them before running bootstrap"
    note "updating $SOURCE_DIR (fast-forward only)"
    GIT_SSH_COMMAND="$GIT_SSH" git -C "$SOURCE_DIR" pull --ff-only
  else
    note "cloning $REPO_URL into $SOURCE_DIR"
    GIT_SSH_COMMAND="$GIT_SSH" git clone "$REPO_URL" "$SOURCE_DIR"
  fi
}

write_config() {
  mkdir -p "$HOME/.config/chezmoi"
  if [ ! -f "$CONFIG_FILE" ]; then
    {
      echo "# Local chezmoi configuration. Managed by hand after bootstrap."
      echo "sourceDir = \"$SOURCE_DIR\""
    } > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    note "wrote $CONFIG_FILE"
  elif ! grep -Eq '^[[:space:]]*sourceDir[[:space:]]*=' "$CONFIG_FILE"; then
    backup_file "$CONFIG_FILE"
    local tmp_config
    tmp_config="$WORKDIR/chezmoi.toml"
    { echo "sourceDir = \"$SOURCE_DIR\""; echo ""; cat "$CONFIG_FILE"; } > "$tmp_config"
    mv "$tmp_config" "$CONFIG_FILE"
    note "merged sourceDir into $CONFIG_FILE"
  else
    note "sourceDir already present in $CONFIG_FILE"
  fi
  if [ "$OP_SERVICE" = true ] || [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    if grep -Eq '^[[:space:]]*\[onepassword\]' "$CONFIG_FILE"; then
      if awk '/^\s*\[onepassword\]/{in_section=1;next} /^\s*\[/{in_section=0} in_section && /mode\s*=\s*"account"/' "$CONFIG_FILE" | grep -q . \
          && [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
        warn "$CONFIG_FILE sets [onepassword] mode=\"account\" while OP_SERVICE_ACCOUNT_TOKEN is set."
        warn "chezmoi will refuse this combination; change mode to \"service\" or unset the token."
      else
        note "[onepassword] block already present in $CONFIG_FILE"
      fi
    else
      backup_file "$CONFIG_FILE"
      {
        echo ""
        echo "[onepassword]"
        echo "mode = \"service\""
        echo "prompt = false"
      } >> "$CONFIG_FILE"
      note "added [onepassword] service block to $CONFIG_FILE"
    fi
  fi
}

backup_managed_targets() {
  local backup_dir="$BACKUP_ROOT/pre-apply-$(date +%Y%m%d-%H%M%S)"
  local target dest
  while IFS= read -r target; do
    dest="$HOME/$target"
    if [ -f "$dest" ] || [ -L "$dest" ]; then
      mkdir -p "$backup_dir/$(dirname "$target")"
      if [ -L "$dest" ]; then
        printf 'symlink -> %s\n' "$(readlink "$dest")" > "$backup_dir/$target.linkinfo"
        cp -aL "$dest" "$backup_dir/$target" 2>/dev/null || true
      else
        cp -a "$dest" "$backup_dir/$target"
      fi
    fi
  done < <("$CHEZMOI_BIN" managed)
  if [ -d "$backup_dir" ]; then
    chmod 700 "$BACKUP_ROOT"
    chmod -R go-rwx "$backup_dir"
    note "backed up existing managed targets under $backup_dir"
  else
    note "no existing managed targets to back up (fresh machine)"
  fi
}

# Directory symlinks on a managed target's path (for example a legacy
# ~/.config/ghostty -> ~/Dropbox/dotfiles-ng/ghostty link) are not managed
# targets themselves, so chezmoi would write THROUGH them into the legacy
# tree (and whatever syncs it). Back the link definition and the target
# contents up separately, then remove the link so apply creates a real
# directory. The legacy target tree itself is left intact.
replace_path_symlinks() {
  local backup_dir="$BACKUP_ROOT/dir-symlinks-$(date +%Y%m%d-%H%M%S)"
  local target rel depth ancestors a link_target found
  found=false
  while IFS= read -r target; do
    rel="$(dirname "$target")"
    [ "$rel" = "." ] && continue
    ancestors=""
    depth="$rel"
    while [ "$depth" != "." ] && [ -n "$depth" ]; do
      ancestors="$depth"$'\n'"$ancestors"
      depth="$(dirname "$depth")"
    done
    while IFS= read -r a; do
      [ -n "$a" ] || continue
      if [ -L "$HOME/$a" ]; then
        found=true
        link_target="$(readlink "$HOME/$a")"
        mkdir -p "$backup_dir/$a"
        printf 'symlink -> %s\n' "$link_target" > "$backup_dir/$a.linkinfo"
        cp -aR "$HOME/$a/." "$backup_dir/$a/" 2>/dev/null || true
        rm "$HOME/$a"
        note "backed up and removed directory symlink $HOME/$a (-> $link_target); apply will create a real directory"
      fi
    done <<< "$ancestors"
  done < <("$CHEZMOI_BIN" managed)
  if [ "$found" = true ]; then
    chmod 700 "$BACKUP_ROOT"
    chmod -R go-rwx "$backup_dir"
    note "directory-symlink backup under $backup_dir (legacy target trees untouched)"
  fi
}

apply_dotfiles() {
  resolve_chezmoi || die "chezmoi binary not found"
  backup_managed_targets
  replace_path_symlinks
  if command -v op >/dev/null 2>&1 && ! op whoami >/dev/null 2>&1; then
    warn "1Password CLI is installed but not authenticated."
    warn "Templates that resolve 1Password secrets will fail until you authenticate"
    warn "(op signin, or export OP_SERVICE_ACCOUNT_TOKEN). Other targets still apply."
  fi
  note "applying dotfiles to $HOME"
  if "$CHEZMOI_BIN" apply --force --keep-going; then
    note "dotfiles applied"
  else
    record_failure "chezmoi apply reported errors (commonly 1Password templates without auth)"
    warn "Authenticate op (op signin, or ensure ~/.local/1password_token exists), then re-run bootstrap."
  fi
}

seed_zshrc() {
  if [ -e "$HOME/.zshrc" ] || [ -L "$HOME/.zshrc" ]; then
    note "~/.zshrc already exists; merge examples/zshrc into it manually (it stays unmanaged)"
    return
  fi
  [ -f "$SOURCE_DIR/examples/zshrc" ] || return
  install -m 0644 "$SOURCE_DIR/examples/zshrc" "$HOME/.zshrc"
  note "created ~/.zshrc from examples/zshrc (unmanaged; machine-local additions go there)"
}

usage() {
  sed -n '2,32p' "$0"
}

APPLY=true
OP_SERVICE=false
for arg in "$@"; do
  case "$arg" in
    --op-service) OP_SERVICE=true ;;
    --no-apply) APPLY=false ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $arg (see --help)" ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || die "this bootstrap targets macOS"
for cmd in curl git ssh; do
  command -v "$cmd" >/dev/null 2>&1 || die "required command missing: $cmd"
done

install_chezmoi
install_op
install_mise
github_host_key
check_github_auth
sync_source
write_config

if [ "$APPLY" = true ]; then
  apply_dotfiles
  seed_zshrc
  run_mise_install
fi

cat <<EOF

Bootstrap complete. Not yet installed by this script (see AGENTS.md):

  - zsh plugins (antidote) and Vim plugins (vim-plug) are optional and separate
  - Ghostty's configured font (IBM Plex Mono) must be installed separately
    (on macOS: brew install --cask font-ibm-plex-mono)

Machine-local overrides (never committed): shell additions in ~/.zshrc,
Polytoken model/telemetry in ~/.config/chezmoi/polytoken.local.yaml,
Git credentials in ~/.gitconfig-auth. Machines using the 1Password service
token: keep it at ~/.local/1password_token (mode 600); the shared shell
config exports it as OP_SERVICE_ACCOUNT_TOKEN automatically.
Applying replaces ~/.ssh/authorized_keys
with the shared list; any pre-existing copy was backed up under $BACKUP_ROOT/.
Removed directory symlinks (if any) were backed up under $BACKUP_ROOT/ and
their legacy target trees were left in place.
Start a new zsh to pick everything up (including the Starship prompt).
Re-running bootstrap is safe.
EOF

if [ "$FAILURES" -gt 0 ]; then
  echo "" >&2
  warn "BOOTSTRAP FINISHED WITH $FAILURES FAILURE(S) LISTED ABOVE; exit code is 1."
  warn "Fix them (often: authenticate op or provision ~/.local/1password_token), then re-run."
  exit 1
fi
