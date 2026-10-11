# sakib's dotfiles installer for Windows (Windows Terminal + WSL).
#
#   irm https://raw.githubusercontent.com/sakib/dotfiles/master/install.ps1 | iex
#
# Installs Windows Terminal and WSL (Ubuntu) if missing, the MesloLGS NF font,
# sets it as the font for WSL profiles (your color scheme is left alone), then
# runs install.sh inside WSL. Safe to re-run.
#
# Environment overrides:
#   DOTFILES_WSL_DISTRO=Ubuntu   which WSL distro to set up
#   DOTFILES_WINDOWS_ONLY=1      skip WSL (used by install.sh when run from WSL)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # Invoke-WebRequest is very slow with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$DotfilesRaw = 'https://raw.githubusercontent.com/sakib/dotfiles/master'
$P10kMedia = 'https://github.com/romkatv/powerlevel10k-media/raw/master'
$FontFace = 'MesloLGS NF'

function Write-Step($Message) { Write-Host "==> $Message" -ForegroundColor Blue }
function Write-Warn($Message) { Write-Host "warning: $Message" -ForegroundColor Yellow }

function Install-WindowsTerminal {
    if (Get-Command wt.exe -ErrorAction SilentlyContinue) { return }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warn 'winget not found; install Windows Terminal from the Microsoft Store'
        return
    }
    Write-Step 'Installing Windows Terminal'
    $ErrorActionPreference = 'Continue'
    winget install -e --id Microsoft.WindowsTerminal --accept-source-agreements --accept-package-agreements
}

function Install-Font {
    Write-Step "Installing $FontFace font"
    # Per-user font install: no admin needed.
    $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    foreach ($style in 'Regular', 'Bold', 'Italic', 'Bold Italic') {
        $file = "$FontFace $style.ttf"
        $path = Join-Path $dir $file
        if (-not (Test-Path $path)) {
            Invoke-WebRequest -UseBasicParsing -Uri "$P10kMedia/$([uri]::EscapeDataString($file))" -OutFile $path
        }
        New-ItemProperty -Path $key -Name "$FontFace $style (TrueType)" -Value $path -PropertyType String -Force | Out-Null
    }
}

function Set-TerminalFont {
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    $found = $false
    foreach ($path in $candidates) {
        if (-not (Test-Path $path)) { continue }
        $found = $true
        # settings.json may contain // comment lines, which ConvertFrom-Json rejects.
        $text = (Get-Content -Raw -Path $path) -split "`n" | Where-Object { $_ -notmatch '^\s*//' }
        $settings = ($text -join "`n") | ConvertFrom-Json
        $profiles = if ($settings.profiles -is [array]) { $settings.profiles } else { $settings.profiles.list }
        $changed = $false
        foreach ($prof in $profiles) {
            $isWsl = $prof.source -in 'Microsoft.WSL', 'Windows.Terminal.Wsl' -or
                $prof.source -like 'CanonicalGroupLimited.*' -or
                $prof.commandline -match '\bwsl(\.exe)?\b'
            if (-not $isWsl) { continue }
            if (-not $prof.PSObject.Properties['font']) {
                $prof | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{})
            }
            if ($prof.font.face -ne $FontFace) {
                $prof.font | Add-Member -NotePropertyName face -NotePropertyValue $FontFace -Force
                $changed = $true
            }
        }
        if ($changed) {
            Write-Step "Setting $FontFace as the font for WSL profiles in Windows Terminal"
            Copy-Item -Path $path -Destination "$path.bak" -Force
            [IO.File]::WriteAllText($path, ($settings | ConvertTo-Json -Depth 32))
        }
    }
    if (-not $found) {
        Write-Warn "Windows Terminal hasn't been opened yet; open it once, then re-run to set the font"
    }
}

function Get-WslDistros {
    $ErrorActionPreference = 'Continue'  # PowerShell 5.1 throws on native stderr under 'Stop'
    $env:WSL_UTF8 = '1'
    $out = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    # Older WSL versions print UTF-16 even with WSL_UTF8 set.
    return @($out | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
}

function Install-Dotfiles {
    Install-WindowsTerminal
    Install-Font
    Set-TerminalFont

    if ($env:DOTFILES_WINDOWS_ONLY) { return }

    $distro = if ($env:DOTFILES_WSL_DISTRO) { $env:DOTFILES_WSL_DISTRO } else { 'Ubuntu' }
    if ((Get-WslDistros) -notcontains $distro) {
        Write-Step "Installing WSL with $distro (asks for admin)"
        Start-Process -FilePath wsl.exe -ArgumentList '--install', '-d', $distro -Verb RunAs -Wait
        Write-Host ''
        Write-Host "Next: reboot if asked, open $distro from the Start menu to create your Linux user,"
        Write-Host 'then run this one-liner again to finish:'
        Write-Host "  irm $DotfilesRaw/install.ps1 | iex"
        return
    }

    Write-Step "Running install.sh inside WSL ($distro)"
    $ErrorActionPreference = 'Continue'
    # --exec skips the login shell, so the command reaches bash unchanged.
    & wsl.exe -d $distro --cd '~' --exec bash -c "f=`$(mktemp) && curl -fsSL $DotfilesRaw/install.sh -o `$f && DOTFILES_SKIP_WINDOWS=1 bash `$f; rc=`$?; rm -f `$f; exit `$rc"
    if ($LASTEXITCODE -ne 0) { Write-Warn "install.sh exited with code $LASTEXITCODE" }
}

Install-Dotfiles
