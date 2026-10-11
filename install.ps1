# sakib's dotfiles installer for Windows (Windows Terminal + WSL).
#
#   irm https://raw.githubusercontent.com/sakib/dotfiles/master/install.ps1 | iex
#
# Installs Windows Terminal and WSL (Ubuntu) if missing, the MesloLGS NF font,
# restores the Windows Terminal settings saved in windows-terminal/, makes sure
# WSL profiles use the font, then runs install.sh inside WSL. Safe to re-run.
#
# Environment overrides:
#   DOTFILES_WSL_DISTRO=Ubuntu   which WSL distro to set up
#   DOTFILES_WINDOWS_ONLY=1      skip WSL (used by install.sh when run from WSL)
#   DOTFILES_WT_BACKUP_TO=<dir>  only save Windows Terminal settings to <dir>
#                                (used by the wt-backup command in WSL)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # Invoke-WebRequest is very slow with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$DotfilesRaw = 'https://raw.githubusercontent.com/sakib/dotfiles/master'
$P10kMedia = 'https://github.com/romkatv/powerlevel10k-media/raw/master'
$FontFace = 'MesloLGS NF'
$TerminalPackage = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe"
$TerminalSettingsPaths = @(
    "$TerminalPackage\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)
# Hash of the settings file as of the last backup/restore, so a restore never
# overwrites changes made in the Settings UI since then.
$SyncRecord = Join-Path $env:LOCALAPPDATA 'sakib-dotfiles\terminal-settings.sha256'

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

function ConvertFrom-TerminalJson([string]$Text) {
    # settings.json may contain // comment lines, which ConvertFrom-Json rejects.
    (($Text -split "`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n") | ConvertFrom-Json
}

function Get-TerminalProfiles($Settings) {
    if ($Settings.profiles -is [array]) { return $Settings.profiles }
    return @($Settings.profiles.defaults) + @($Settings.profiles.list) | Where-Object { $_ }
}

# Image files (tab icons, backgrounds) that settings point to under your user folder.
function Get-TerminalImages($Settings) {
    foreach ($prof in Get-TerminalProfiles $Settings) {
        foreach ($field in 'icon', 'backgroundImage') {
            $image = $prof.$field
            if ($image -and $image.StartsWith($env:USERPROFILE, [StringComparison]::OrdinalIgnoreCase)) { $image }
        }
    }
}

function Save-SyncRecord([string]$Path) {
    New-Item -ItemType Directory -Force -Path (Split-Path $SyncRecord) | Out-Null
    (Get-FileHash -Algorithm SHA256 -Path $Path).Hash | Set-Content -Path $SyncRecord
}

function Backup-TerminalSettings([string]$Destination) {
    $path = $TerminalSettingsPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $path) {
        Write-Warn 'No Windows Terminal settings found'
        return
    }
    $text = [IO.File]::ReadAllText($path)
    # Store paths as %USERPROFILE% so they work under any Windows username.
    $userJson = [regex]::Escape($env:USERPROFILE.Replace('\', '\\'))
    $portable = [regex]::Replace($text, $userJson, '%USERPROFILE%', 'IgnoreCase')
    New-Item -ItemType Directory -Force -Path (Join-Path $Destination 'icons') | Out-Null
    [IO.File]::WriteAllText((Join-Path $Destination 'settings.json'), $portable)
    foreach ($image in Get-TerminalImages (ConvertFrom-TerminalJson $text)) {
        if (Test-Path $image) { Copy-Item -Path $image -Destination (Join-Path $Destination 'icons') -Force }
    }
    Save-SyncRecord $path
    Write-Step "Saved Windows Terminal settings to $Destination"
}

function Restore-TerminalSettings {
    if (-not (Test-Path $TerminalPackage)) {
        Write-Warn "Windows Terminal isn't installed yet; skipping its settings"
        return
    }
    try {
        $saved = (Invoke-WebRequest -UseBasicParsing -Uri "$DotfilesRaw/windows-terminal/settings.json").Content
    } catch {
        Write-Warn 'No saved Windows Terminal settings to restore'
        return
    }
    $saved = $saved.Replace('%USERPROFILE%', $env:USERPROFILE.Replace('\', '\\'))
    $path = $TerminalSettingsPaths[0]

    if (Test-Path $path) {
        if ([IO.File]::ReadAllText($path) -ceq $saved) {
            Save-SyncRecord $path
            return
        }
        $lastSync = if (Test-Path $SyncRecord) { (Get-Content -Raw -Path $SyncRecord).Trim() } else { $null }
        if ($lastSync -and (Get-FileHash -Algorithm SHA256 -Path $path).Hash -ne $lastSync) {
            Write-Warn 'Windows Terminal settings were changed since the last backup, so they were not overwritten.'
            Write-Host '  Keep them: run wt-backup in WSL and commit. Use the saved ones: delete settings.json and re-run.'
            return
        }
        $backup = "$path.$(Get-Date -Format yyyyMMdd-HHmmss).bak"
        Copy-Item -Path $path -Destination $backup
        Write-Step "Restoring Windows Terminal settings (previous ones saved to $backup)"
    } else {
        Write-Step 'Restoring Windows Terminal settings'
        New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    }
    [IO.File]::WriteAllText($path, $saved)

    foreach ($image in Get-TerminalImages (ConvertFrom-TerminalJson $saved)) {
        if (Test-Path $image) { continue }
        New-Item -ItemType Directory -Force -Path (Split-Path $image) | Out-Null
        $name = [uri]::EscapeDataString((Split-Path $image -Leaf))
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "$DotfilesRaw/windows-terminal/icons/$name" -OutFile $image
        } catch {
            Write-Warn "Couldn't restore $image"
        }
    }
    Save-SyncRecord $path
}

function Set-TerminalFont {
    $found = $false
    foreach ($path in $TerminalSettingsPaths) {
        if (-not (Test-Path $path)) { continue }
        $found = $true
        $settings = ConvertFrom-TerminalJson (Get-Content -Raw -Path $path)
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
            if ($path -eq $TerminalSettingsPaths[0]) { Save-SyncRecord $path }
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
    if ($env:DOTFILES_WT_BACKUP_TO) {
        Backup-TerminalSettings $env:DOTFILES_WT_BACKUP_TO
        return
    }

    Install-WindowsTerminal
    Install-Font
    Restore-TerminalSettings
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
