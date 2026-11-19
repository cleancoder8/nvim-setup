#!/usr/bin/env bash
# Install the Neovim config from this repo into ~/.config/nvim.
# Safe to run on a machine that already has a config: the old one is backed up.
set -euo pipefail

REPO_URL="https://github.com/cleancoder8/nvim-setup.git"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
OMARCHY_THEME="$HOME/.local/state/omarchy/current/theme/neovim.lua"

ASSUME_YES=0
SKIP_PLUGINS=0

usage() {
  cat <<'EOF'
Usage: setup.sh [options]

  -y, --yes           Don't ask for confirmation (install Neovim if missing).
      --skip-plugins  Copy the config but don't install plugins now.
  -h, --help          Show this help.

By default the script asks before installing Neovim on a machine that lacks it.
EOF
}

for arg in "$@"; do
  case "$arg" in
    -y | --yes) ASSUME_YES=1 ;;
    --skip-plugins) SKIP_PLUGINS=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

confirm() {
  if ((ASSUME_YES)); then
    return 0
  fi
  printf '%s [y/N] ' "$1"
  read -r reply
  [[ "$reply" =~ ^[Yy] ]]
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

# --- prerequisites ---------------------------------------------------------

command -v git >/dev/null 2>&1 || fail "git is required to clone the config."

nvim_major=0
nvim_minor=0
if command -v nvim >/dev/null 2>&1; then
  read -r nvim_major nvim_minor < <(nvim --version | head -n1 | sed -E 's/^NVIM v([0-9]+)\.([0-9]+).*/\1 \2/')
fi

if ((nvim_major == 0 && nvim_minor < 11)); then
  echo "Neovim $([[ $nvim_major -eq 0 && $nvim_minor -eq 0 ]] && echo 'is not installed' || echo 'is too old; need >= 0.11')."
  if ! confirm "Install Neovim now?"; then
    fail "Install Neovim >= 0.11 and re-run this script."
  fi

  case "$(uname -s)" in
    Darwin)
      command -v brew >/dev/null 2>&1 || fail "Homebrew is required: https://brew.sh"
      brew install neovim
      ;;
    Linux)
      if command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed neovim
      elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y neovim
        echo "Note: distro packages can be old. If Neovim is < 0.11, use an AppImage or https://github.com/neovim/neovim/releases"
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y neovim
      else
        fail "No supported package manager found. Install Neovim >= 0.11 manually."
      fi
      ;;
    *)
      fail "Unsupported OS. Install Neovim >= 0.11 manually."
      ;;
  esac

  command -v nvim >/dev/null 2>&1 || fail "Neovim still not found on PATH. Open a new shell and retry."
  read -r nvim_major nvim_minor < <(nvim --version | head -n1 | sed -E 's/^NVIM v([0-9]+)\.([0-9]+).*/\1 \2/')
  if ((nvim_major == 0 && nvim_minor < 11)); then
    fail "Neovim is still older than 0.11; this config needs a newer build."
  fi
fi

echo "Found Neovim $(nvim --version | head -n1 | awk '{print $2}')."

# --- back up whatever is there ---------------------------------------------

mkdir -p "$(dirname "$CONFIG_DIR")"
backup=""
if [[ -e "$CONFIG_DIR" || -L "$CONFIG_DIR" ]]; then
  if [[ -d "$CONFIG_DIR" && -z "$(ls -A "$CONFIG_DIR")" ]]; then
    rmdir "$CONFIG_DIR"
  else
    backup="${CONFIG_DIR}.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$CONFIG_DIR" "$backup"
    echo "Backed up existing config to: $backup"
  fi
fi

restore_backup() {
  if [[ -n "$backup" && ! -e "$CONFIG_DIR" ]]; then
    mv "$backup" "$CONFIG_DIR"
    echo "Restored previous config from backup." >&2
  fi
}

echo "Cloning $REPO_URL into $CONFIG_DIR ..."
if ! git clone "$REPO_URL" "$CONFIG_DIR"; then
  restore_backup
  fail "Clone failed. Check your internet connection and try again."
fi

# --- theme: Omarchy owns it on Omarchy machines, otherwise use the snapshot --

if [[ -f "$OMARCHY_THEME" ]]; then
  ln -s "$OMARCHY_THEME" "$CONFIG_DIR/lua/plugins/theme.lua"
  echo "Theme: linked to Omarchy's current theme ($OMARCHY_THEME)"
else
  cp "$CONFIG_DIR/theme/neovim.lua" "$CONFIG_DIR/lua/plugins/theme.lua"
  echo "Theme: installed saved snapshot (tokyonight-night)"
fi

# --- install the exact plugin versions pinned in lazy-lock.json -------------

if ((SKIP_PLUGINS)); then
  echo "Skipping plugin install. Run: nvim --headless -c 'Lazy! install' -c 'qa!'"
else
  echo "Installing pinned plugin versions from lazy-lock.json (this can take a minute) ..."
  # "Lazy! install" honours lazy-lock.json; "Lazy! sync" would update plugins
  # to their latest commits and change the lockfile.
  if ! nvim --headless -c 'Lazy! install' -c 'qa!'; then
    echo "Warning: plugin install reported an error. Run this manually to retry:" >&2
    echo "  nvim --headless -c 'Lazy! install' -c 'qa!'" >&2
  elif [[ -d "$DATA_DIR/lazy/LazyVim" ]]; then
    echo "Plugins installed at $DATA_DIR/lazy"
  fi
fi

echo
echo "Done. Run 'nvim' to start with your config."
echo "To pull later changes: cd $CONFIG_DIR && git pull"
[[ -n "$backup" ]] && echo "Old config is still at: $backup"
