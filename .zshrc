# Powerlevel10k instant prompt. Keep this near the top; anything that prints
# output or needs input must go above it.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Homebrew (macOS)
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

export PATH="$HOME/.local/bin:$PATH"
export EDITOR=vim

# mise: CLI tools from ~/.config/mise/config.toml (fzf, bat, gh, uv, ...)
if (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
fi

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(
  git
  zsh-autosuggestions
)
source $ZSH/oh-my-zsh.sh

# History
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt histignorealldups sharehistory

# WSL: open links in the Windows browser, and wt-backup to save Windows
# Terminal settings into this repo (install.ps1 restores them)
if [[ -n "$WSL_DISTRO_NAME" ]]; then
  export BROWSER="explorer.exe"

  _dotfiles_dir=${${(%):-%x}:A:h}
  wt-backup() {
    local win_temp ps1
    win_temp=$(wslpath "$(powershell.exe -NoProfile -Command '$env:TEMP' | tr -d '\r')")
    ps1="$win_temp/dotfiles-install.ps1"
    cp "$_dotfiles_dir/install.ps1" "$ps1"
    DOTFILES_WT_BACKUP_TO="$(wslpath -w "$_dotfiles_dir/windows-terminal")" WSLENV="${WSLENV:+$WSLENV:}DOTFILES_WT_BACKUP_TO" \
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$ps1")"
    rm -f "$ps1"
    git -C "$_dotfiles_dir" status --short -- windows-terminal
  }
fi

# fzf keybindings: Ctrl+R history search, Ctrl+T file picker, Alt+C cd
if (( $+commands[fzf] )); then
  source <(fzf --zsh 2>/dev/null)
fi

# Frick's Power Finders (Ctrl+F, g, G, glog, gd), fetched by install.sh
[[ -f ~/.power_finders.zsh ]] && source ~/.power_finders.zsh

# Powerlevel10k config (created by `p10k configure`)
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# Machine-specific settings and secrets (not tracked)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
