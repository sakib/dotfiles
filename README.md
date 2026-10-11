# sakib's dev environment

zsh + Oh My Zsh + Powerlevel10k, modern CLI tools managed by [mise](https://mise.jdx.dev), vim, and git config, set up with one command.

## Install

**macOS** (Terminal):
```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/sakib/dotfiles/master/install.sh)"
```

**Linux** (any distro with apt, dnf, pacman or zypper):
```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/sakib/dotfiles/master/install.sh)"
```

**Windows** (PowerShell):
```powershell
irm https://raw.githubusercontent.com/sakib/dotfiles/master/install.ps1 | iex
```
On a brand-new machine this installs WSL first. Reboot if asked, open Ubuntu once to create your user, then run the same line again.

Then restart your terminal. The Powerlevel10k wizard starts on first launch (re-run it any time with `p10k configure`), and `gh auth login` connects GitHub.

The installer is safe to re-run. Anything it would overwrite is moved to `~/.dotfiles-backup/<timestamp>/` first. To upgrade all tools and plugins later:
```sh
DOTFILES_UPDATE=1 ~/.dotfiles/install.sh
```

## What you get

| | macOS | Linux | Windows |
|---|---|---|---|
| Terminal | iTerm2 + DimmedMonokai preset | your terminal | Windows Terminal (your color scheme is kept) |
| Font | MesloLGS NF | MesloLGS NF (desktop) | MesloLGS NF, set on WSL profiles |
| Shell | zsh, [Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh), [Powerlevel10k](https://github.com/romkatv/powerlevel10k), [autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | same | same, inside WSL |
| Tools | via mise | via mise | via mise, inside WSL |

**Tools** ([`.config/mise/config.toml`](.config/mise/config.toml)): [fzf](https://github.com/junegunn/fzf), [fd](https://github.com/sharkdp/fd), [bat](https://github.com/sharkdp/bat), [eza](https://github.com/eza-community/eza), [ripgrep](https://github.com/BurntSushi/ripgrep), [glow](https://github.com/charmbracelet/glow), [gh](https://github.com/cli/cli), [neovim](https://neovim.io/), [uv](https://docs.astral.sh/uv/). They install into your home directory without root and are the same versions on every OS. Add one with `mise use -g <tool>@latest` (it's written back to this repo); update them all with `mise upgrade`. For Python, use uv: `uv python install`, `uv tool install <pkg>`, `uvx <cmd>`.

**Shortcuts**:
- `Ctrl+R`: fuzzy history search. `Ctrl+T`: file picker. `Alt+C`: fuzzy cd. (These come from fzf.)
- `Ctrl+F`, `g`/`G`, `glog`, `gd`: [Frick's Power Finders](https://gist.github.com/mdbfrick/2114066b1f4523727c74daf593ee9644). In order: open a file, grep into vim, search git history, jump to a repo.

**Vim**: [vim-sublime](https://github.com/grigio/vim-sublime) plugins via Vundle, plus [vim-colorschemes](https://github.com/flazz/vim-colorschemes).

**Git**: aliases (`git la` lists them), rebase on pull, `main` as the default branch, and `push.autoSetupRemote`. After `gh auth login`, git pushes to GitHub without further setup.

## Files

| File | Linked to |
|---|---|
| `.zshrc` | `~/.zshrc` |
| `.bashrc`, `.bash_prompt`, `.bash_git` | `~/` (a fallback for bash) |
| `.gitconfig` | `~/.gitconfig` |
| `.vimrc` | `~/.vimrc` |
| `.config/mise/config.toml` | `~/.config/mise/config.toml` |
| `DimmedMonokai.itermcolors` | imported into iTerm2 |

The files are symlinked, so edit them in `~/.dotfiles` and commit.

**Machine-specific settings and secrets** go in untracked files, never in this repo:
- `~/.zshrc.local` and `~/.bashrc.local` for API keys and per-machine aliases.
- `~/.gitconfig.local` for things like a work email:
  ```sh
  git config -f ~/.gitconfig.local user.email you@work.com
  ```
