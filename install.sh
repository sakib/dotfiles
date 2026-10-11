#!/usr/bin/env bash
#
# sakib's dotfiles installer for macOS, Linux and WSL.
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/sakib/dotfiles/master/install.sh)"
#
# Safe to re-run. Existing dotfiles are moved to ~/.dotfiles-backup/<timestamp>/.
#
# Environment overrides:
#   DOTFILES_DIR          where to clone the repo (default: ~/.dotfiles, or the
#                         checkout this script lives in)
#   DOTFILES_REPO         git URL to clone (default: github.com/sakib/dotfiles)
#   DOTFILES_UPDATE=1     upgrade tools (mise upgrade) and pull plugin updates
#   DOTFILES_SKIP_WINDOWS=1  on WSL, don't touch the Windows side (fonts, Terminal)

set -euo pipefail

DOTFILES_REPO=${DOTFILES_REPO:-https://github.com/sakib/dotfiles.git}
BIN="$HOME/.local/bin"
OS=$(uname -s)
LINKS=(.zshrc .bashrc .bash_prompt .bash_git .gitconfig .vimrc .config/mise/config.toml)
POWER_FINDERS_URL=https://gist.githubusercontent.com/mdbfrick/2114066b1f4523727c74daf593ee9644/raw/.zshrc
P10K_MEDIA=https://github.com/romkatv/powerlevel10k-media/raw/master
export PATH="$BIN:$PATH"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
# Not /proc/version: Docker on a WSL2 kernel says "microsoft" there too.
is_wsl() { [[ -n "${WSL_DISTRO_NAME:-}" || -d /run/WSL ]]; }

as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  elif have sudo; then
    sudo "$@"
  else
    warn "need root to run: $*"
    return 1
  fi
}

# Use the checkout this script lives in when run from one; otherwise ~/.dotfiles.
script_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
if [[ -z "${DOTFILES_DIR:-}" && -n "$script_dir" && -e "$script_dir/.git" && -f "$script_dir/.zshrc" ]]; then
  DOTFILES_DIR=$script_dir
fi
DOTFILES_DIR=${DOTFILES_DIR:-$HOME/.dotfiles}

clone_or_update() { # url dir
  if [[ -d "$2/.git" ]]; then
    if [[ -n "${DOTFILES_UPDATE:-}" ]]; then
      git -C "$2" pull -q --ff-only || warn "could not update $2"
    fi
  else
    mkdir -p "$(dirname "$2")"
    git clone -q --depth=1 "$1" "$2"
  fi
}

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------

install_macos_packages() {
  if ! have brew; then
    log "Installing Homebrew"
    [[ -t 0 ]] || export NONINTERACTIVE=1
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  log "Installing git and mise with Homebrew"
  brew install -q git git-lfs mise || warn "some brew formulae failed"
  brew install -q --cask font-meslo-for-powerlevel10k || warn "could not install MesloLGS NF font"
  if [[ ! -d /Applications/iTerm.app ]]; then
    brew install -q --cask iterm2 || warn "could not install iTerm2"
  fi
}

install_linux_packages() {
  if have zsh && have git && have curl && have vim && have less; then
    return
  fi
  log "Installing zsh, git, curl, vim"
  if have apt-get; then
    as_root apt-get update -qq
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zsh git git-lfs curl ca-certificates vim less tar gzip
  elif have dnf; then
    as_root dnf install -y -q zsh git git-lfs curl vim-enhanced less tar gzip findutils
  elif have pacman; then
    as_root pacman -Sy --needed --noconfirm zsh git git-lfs curl vim less tar gzip
  elif have zypper; then
    as_root zypper -n install zsh git git-lfs curl vim less tar gzip
  else
    warn "unknown package manager: install zsh, git, curl and vim yourself"
  fi
}

install_mise() {
  if ! have mise; then
    log "Installing mise"
    curl -fsSL https://mise.run | MISE_QUIET=1 sh
  fi
}

install_tools() { # everything in .config/mise/config.toml
  log "Installing CLI tools with mise (fzf, fd, bat, eza, ripgrep, glow, gh, neovim, uv)"
  # gh's token, when logged in, avoids GitHub API rate limits.
  if [[ -z "${GITHUB_TOKEN:-}" ]] && have gh && gh auth status >/dev/null 2>&1; then
    GITHUB_TOKEN=$(gh auth token)
    export GITHUB_TOKEN
  fi
  if [[ -n "${DOTFILES_UPDATE:-}" ]]; then
    mise upgrade --yes || warn "some tools failed to upgrade"
  else
    mise install --yes || warn "some tools failed to install; re-run, or run: mise install"
  fi
}

# ---------------------------------------------------------------------------
# Dotfiles, shell and editor
# ---------------------------------------------------------------------------

get_dotfiles() {
  if [[ "$DOTFILES_DIR" == "$script_dir" ]]; then
    log "Using dotfiles checkout at $DOTFILES_DIR"
  elif [[ -d "$DOTFILES_DIR/.git" ]]; then
    log "Updating $DOTFILES_DIR"
    git -C "$DOTFILES_DIR" pull -q --ff-only || warn "could not update $DOTFILES_DIR (local changes?)"
  else
    log "Cloning dotfiles into $DOTFILES_DIR"
    git clone -q "$DOTFILES_REPO" "$DOTFILES_DIR"
  fi
}

link_dotfiles() {
  local backup f src dst
  backup="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
  for f in "${LINKS[@]}"; do
    src="$DOTFILES_DIR/$f"
    dst="$HOME/$f"
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
      continue
    fi
    if [[ -e "$dst" || -L "$dst" ]]; then
      mkdir -p "$backup/$(dirname "$f")"
      mv "$dst" "$backup/$f"
      log "Backed up ~/$f to $backup/"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
  done
}

install_zsh_plugins() {
  log "Installing Oh My Zsh, Powerlevel10k and zsh-autosuggestions"
  local custom="$HOME/.oh-my-zsh/custom"
  clone_or_update https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  clone_or_update https://github.com/romkatv/powerlevel10k.git "$custom/themes/powerlevel10k"
  clone_or_update https://github.com/zsh-users/zsh-autosuggestions.git "$custom/plugins/zsh-autosuggestions"
}

install_power_finders() {
  # Frick's Power Finders, patched so a missing alias isn't an error and
  # to use eza (the maintained fork of exa).
  local tmp
  tmp=$(mktemp)
  if curl -fsSL "$POWER_FINDERS_URL" -o "$tmp" && [[ -s "$tmp" ]]; then
    sed -e 's/^unalias \(.*\)$/unalias \1 2>\/dev\/null/' -e 's/exa -ahl/eza -ahl/g' "$tmp" > "$HOME/.power_finders.zsh"
  else
    warn "could not download Power Finders"
  fi
  rm -f "$tmp"
}

install_vim_plugins() {
  log "Installing vim plugins"
  clone_or_update https://github.com/VundleVim/Vundle.vim.git "$HOME/.vim/bundle/Vundle.vim"
  if [[ ! -d "$HOME/.vim/colors" ]]; then
    local tmp
    tmp=$(mktemp -d)
    git clone -q --depth=1 https://github.com/flazz/vim-colorschemes.git "$tmp/schemes"
    mkdir -p "$HOME/.vim/colors"
    cp "$tmp"/schemes/colors/* "$HOME/.vim/colors/"
    rm -rf "$tmp"
  fi
  vim -E -s -u "$HOME/.vimrc" +PluginInstall +qall </dev/null >/dev/null 2>&1 || true
}

set_default_shell() {
  local zsh_path current user
  zsh_path=$(command -v zsh) || return 0
  user=${USER:-$(id -un)}
  if [[ "$OS" == Darwin ]]; then
    current=$(dscl . -read "/Users/$user" UserShell 2>/dev/null | awk '{print $2}')
  else
    current=$(getent passwd "$user" | cut -d: -f7)
  fi
  [[ "$(basename "${current:-}")" == zsh ]] && return
  if [[ -t 0 ]]; then
    log "Making zsh your default shell"
    chsh -s "$zsh_path" || warn "chsh failed; run: chsh -s $zsh_path"
  else
    warn "run 'chsh -s $zsh_path' to make zsh your default shell"
  fi
}

# ---------------------------------------------------------------------------
# Terminal and fonts
# ---------------------------------------------------------------------------

install_linux_font() { # desktop Linux only; WSL fonts live on the Windows side
  have fc-cache || return 0
  local dir="$HOME/.local/share/fonts" style file
  mkdir -p "$dir"
  for style in Regular Bold Italic "Bold Italic"; do
    file="MesloLGS NF $style.ttf"
    [[ -f "$dir/$file" ]] || curl -fsSL "$P10K_MEDIA/${file// /%20}" -o "$dir/$file"
  done
  fc-cache -f "$dir" >/dev/null
}

setup_windows_side() { # from WSL: font + Windows Terminal via install.ps1
  [[ -n "${DOTFILES_SKIP_WINDOWS:-}" ]] && return
  if ! have powershell.exe; then
    warn "can't reach Windows from WSL; run install.ps1 in PowerShell for the font"
    return
  fi
  log "Setting up the Windows side (font, Windows Terminal)"
  local win_temp ps1
  # shellcheck disable=SC2016  # $env:TEMP is PowerShell, not bash
  win_temp=$(wslpath "$(powershell.exe -NoProfile -Command '$env:TEMP' | tr -d '\r')")
  ps1="$win_temp/dotfiles-install.ps1"
  cp "$DOTFILES_DIR/install.ps1" "$ps1"
  DOTFILES_WINDOWS_ONLY=1 WSLENV="${WSLENV:+$WSLENV:}DOTFILES_WINDOWS_ONLY" \
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$ps1")" \
    || warn "Windows setup failed; run install.ps1 in PowerShell"
  rm -f "$ps1"
}

import_iterm_colors() {
  [[ -d /Applications/iTerm.app ]] || return 0
  if ! defaults read com.googlecode.iterm2 "Custom Color Presets" 2>/dev/null | grep -q DimmedMonokai; then
    log "Importing DimmedMonokai into iTerm2"
    open "$DOTFILES_DIR/DimmedMonokai.itermcolors"
  fi
}

# ---------------------------------------------------------------------------

main() {
  case "$OS" in
    Darwin) install_macos_packages ;;
    Linux)  install_linux_packages; install_mise ;;
    *) warn "unsupported OS: $OS (on Windows, use install.ps1)"; exit 1 ;;
  esac

  get_dotfiles
  link_dotfiles
  install_tools
  install_zsh_plugins
  install_power_finders
  install_vim_plugins

  if [[ "$OS" == Darwin ]]; then
    import_iterm_colors
  elif is_wsl; then
    setup_windows_side
  else
    install_linux_font
  fi

  set_default_shell

  log "Done! Next steps:"
  echo "  1. Restart your terminal (or run: exec zsh)"
  echo "  2. Pick a prompt style in the Powerlevel10k wizard (or run: p10k configure)"
  if ! mise exec -- gh auth status >/dev/null 2>&1; then
    echo "  3. Log in to GitHub: gh auth login"
  fi
  if [[ "$OS" == Darwin ]]; then
    echo "  In iTerm2: Settings > Profiles > Colors > Color Presets > DimmedMonokai,"
    echo "  and Settings > Profiles > Text > Font > MesloLGS NF"
  fi
}

main "$@"
