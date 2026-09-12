#!/usr/bin/env bash
# Bootstrap a Linux machine for this dotfiles repository.
#
# Installs chezmoi and the 1Password CLI when missing, verifies GitHub's SSH
# host key, clones or fast-forward-updates ~/.chezmoi, and creates or merges
# the local chezmoi config. Idempotent: safe to re-run.
#
# This script does NOT apply dotfiles, install shells/editors/mise, provision
# secrets, or modify ~/.zshrc. Read AGENTS.md before applying anything.
#
# Usage:
#   ./bootstrap.sh [--op-service]
#
#   --op-service   also merge "[onepassword]" mode="service" prompt=false into
#                  the local chezmoi config. The OP_SERVICE_ACCOUNT_TOKEN
#                  itself must come from the environment at run time; it is
#                  never written to any file.
#
# Environment overrides: CHEZMOI_VERSION (pinned default below), BIN_DIR,
# SOURCE_DIR.

set -euo pipefail

CHEZMOI_VERSION="${CHEZMOI_VERSION:-v2.72.1}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
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

backup_file() {
  local dir="$BACKUP_ROOT/bootstrap-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dir"
  chmod 700 "$BACKUP_ROOT" "$dir"
  cp -a "$1" "$dir/"
  note "backed up $1 to $dir/"
}

install_chezmoi() {
  if command -v chezmoi >/dev/null 2>&1; then
    note "chezmoi found: $(command -v chezmoi)"
    return
  fi
  local candidate
  for candidate in "$BIN_DIR/chezmoi" "$HOME/bin/chezmoi"; do
    if [ -x "$candidate" ]; then
      note "chezmoi found: $candidate (not on PATH; add it if needed)"
      return
    fi
  done

  note "installing chezmoi $CHEZMOI_VERSION into $BIN_DIR"
  local arch libc ver asset base line
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
  if ldd --version 2>&1 | grep -q musl; then libc=musl; else libc=glibc; fi
  ver="${CHEZMOI_VERSION#v}"
  asset="chezmoi_${ver}_linux-${libc}_${arch}.tar.gz"
  base="https://github.com/twpayne/chezmoi/releases/download/${CHEZMOI_VERSION}"
  curl -fsSL "$base/chezmoi_${ver}_checksums.txt" -o "$WORKDIR/checksums.txt"
  curl -fsSL "$base/$asset" -o "$WORKDIR/$asset"
  line="$(grep "  $asset\$" "$WORKDIR/checksums.txt")" \
    || die "no checksum entry for $asset"
  printf '%s\n' "$line" | (cd "$WORKDIR" && sha256sum -c -)
  tar -xzf "$WORKDIR/$asset" -C "$WORKDIR"
  mkdir -p "$BIN_DIR"
  install -m 0755 "$WORKDIR/chezmoi" "$BIN_DIR/chezmoi"
  note "installed $($BIN_DIR/chezmoi --version)"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) note "add $BIN_DIR to PATH to use chezmoi in this shell" ;;
  esac
}

install_op() {
  if command -v op >/dev/null 2>&1; then
    note "1Password CLI found: $(command -v op)"
    return
  fi
  if ! command -v apt-get >/dev/null 2>&1; then
    warn "no apt-get on this system; install the 1Password CLI manually:"
    warn "  https://developer.1password.com/docs/cli/get-started/"
    warn "chezmoi operations that resolve 1Password secrets will fail without it."
    return
  fi
  command -v sudo >/dev/null 2>&1 \
    || die "sudo is required to install the 1Password CLI from its apt repository"
  command -v gpg >/dev/null 2>&1 || die "gpg is required for the 1Password apt setup"
  command -v dpkg >/dev/null 2>&1 || die "dpkg is required for the 1Password apt setup"

  note "installing 1Password CLI from its official apt repository"
  local arch
  arch="$(dpkg --print-architecture)"
  sudo rm -f /usr/share/keyrings/1password-archive-keyring.gpg
  curl -fsSL https://downloads.1password.com/linux/keys/1password.asc \
    | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
  printf 'deb [arch=%s signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/%s stable main\n' \
    "$arch" "$arch" | sudo tee /etc/apt/sources.list.d/1password.list >/dev/null
  sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22 \
    /usr/share/debsig/keyrings/AC2D62742012EA22
  curl -fsSL https://downloads.1password.com/linux/debian/debsig/1password.pol \
    | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null
  sudo rm -f /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
  curl -fsSL https://downloads.1password.com/linux/keys/1password.asc \
    | sudo gpg --dearmor \
        --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y 1password-cli
  command -v op >/dev/null 2>&1 || die "1Password CLI install did not produce op on PATH"
  note "installed 1Password CLI $(op --version)"
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
  if [ "$OP_SERVICE" = true ]; then
    if grep -Eq '^[[:space:]]*\[onepassword\]' "$CONFIG_FILE"; then
      note "[onepassword] block already present in $CONFIG_FILE"
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

usage() {
  sed -n '2,20p' "$0"
}

OP_SERVICE=false
for arg in "$@"; do
  case "$arg" in
    --op-service) OP_SERVICE=true ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $arg (see --help)" ;;
  esac
done

[ "$(uname -s)" = "Linux" ] || die "this bootstrap targets Linux"
for cmd in curl git tar; do
  command -v "$cmd" >/dev/null 2>&1 || die "required command missing: $cmd"
done

install_chezmoi
install_op
github_host_key
check_github_auth
sync_source
write_config

cat <<EOF

Bootstrap complete. Next steps (see AGENTS.md for the full checklist):

  cd "$SOURCE_DIR"
  chezmoi doctor
  chezmoi managed
  chezmoi diff        # renders 1Password-backed templates; needs an authorized
                      # op session or OP_SERVICE_ACCOUNT_TOKEN in the environment

Applying dotfiles requires your explicit review and approval; this script never
runs chezmoi apply. Merging examples/zshrc into ~/.zshrc stays manual, and
migration backups belong under $BACKUP_ROOT/.
EOF
