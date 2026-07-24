<#
.SYNOPSIS
    Revert everything Apply-HP1Fix.ps1 changed for 'Harry Potter and the
    Philosopher's Stone'.

.DESCRIPTION
    Restores the backed-up Default.ini / dgVoodoo.conf, removes the dgVoodoo
    wrapper DLLs that the fix added, and removes the DEP-exclusion token from
    HP.exe's compatibility layer. This returns the install to its pre-fix state
    (which, on modern Windows, means it will crash again - that is what
    "revert" means here).

.PARAMETER GamePath
    Root of the installed game (folder containing 'System\HP.exe').
    Auto-detected if omitted.

.PARAMETER BackupPath
    A specific '_HP1Fix_backup_*' folder to restore from. Defaults to the
    newest one found in the game's System folder.

.NOTES
    Repo: https://github.com/wolffbe/hp1
#>
[CmdletBinding()]
param(
    [string]$GamePath,
    [string]$BackupPath
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
          ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($GamePath)   { $argList += @('-GamePath',"`"$GamePath`"") }
    if ($BackupPath) { $argList += @('-BackupPath',"`"$BackupPath`"") }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    return
}

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok  ($m) { Write-Host "    OK  $m" -ForegroundColor Green }

# --- Locate the game ------------------------------------------------------
if (-not $GamePath) {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Electronic Arts\Harry Potter TM",
        "$env:ProgramFiles\Electronic Arts\Harry Potter TM",
        "${env:ProgramFiles(x86)}\EA Games\Harry Potter TM",
        "$env:ProgramFiles\EA Games\Harry Potter TM",
        "${env:ProgramFiles(x86)}\Harry Potter TM",
        "$env:ProgramFiles\Harry Potter TM"
    ) | Where-Object { $_ }
    $GamePath = $candidates | Where-Object { Test-Path (Join-Path $_ 'System\HP.exe') } | Select-Object -First 1
}
if (-not $GamePath -or -not (Test-Path (Join-Path $GamePath 'System\HP.exe'))) {
    throw "Could not find 'System\HP.exe'. Pass -GamePath 'C:\path\to\Harry Potter TM'."
}
$sysDir = Join-Path $GamePath 'System'
$exe    = Join-Path $sysDir 'HP.exe'

# --- Find the backup ------------------------------------------------------
if (-not $BackupPath) {
    $BackupPath = Get-ChildItem -Path $sysDir -Directory -Filter '_HP1Fix_backup_*' -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending | Select-Object -First 1 | ForEach-Object FullName
}

# --- Restore config files / remove added DLLs -----------------------------
Write-Step 'Reverting game files'
foreach ($f in 'DDraw.dll','D3D8.dll','D3D9.dll','D3DImm.dll','Default.ini','dgVoodoo.conf') {
    $target = Join-Path $sysDir $f
    $backup = if ($BackupPath) { Join-Path $BackupPath $f } else { $null }
    if ($backup -and (Test-Path $backup)) {
        Copy-Item $backup $target -Force            # restore original
        Write-Ok "restored $f"
    } elseif ($f -match '\.dll$' -and (Test-Path $target)) {
        Remove-Item $target -Force                  # added by the fix -> remove
        Write-Ok "removed $f (added by fix)"
    }
}
# dgVoodooCpl.exe is a fix artifact only
$cpl = Join-Path $sysDir 'dgVoodooCpl.exe'
if (Test-Path $cpl) { Remove-Item $cpl -Force; Write-Ok 'removed dgVoodooCpl.exe' }

# Put back any Wine/wined3d leftovers the fix moved aside (restore only).
foreach ($f in 'ddfuk.dll','libwine.dll','wined3d.dll') {
    $backup = if ($BackupPath) { Join-Path $BackupPath $f } else { $null }
    if ($backup -and (Test-Path $backup)) { Copy-Item $backup (Join-Path $sysDir $f) -Force; Write-Ok "restored $f" }
}

# --- Remove the DEP token (HKLM = current, HKCU = older versions) ---------
Write-Step 'Removing DEP exclusion'
foreach ($layers in 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
                    'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers') {
    $existing = (Get-ItemProperty -Path $layers -Name $exe -ErrorAction SilentlyContinue).$exe
    if (-not $existing) { continue }
    $tokens = @($existing -split '\s+' | Where-Object { $_ -and $_ -ne '~' -and $_ -ne 'DisableNXShowUI' })
    if ($tokens.Count -gt 0) {
        New-ItemProperty -Path $layers -Name $exe -Value ((@('~') + $tokens) -join ' ') -PropertyType String -Force | Out-Null
        Write-Ok "$($layers.Substring(0,4)) kept other layers: ~ $($tokens -join ' ')"
    } else {
        Remove-ItemProperty -Path $layers -Name $exe -ErrorAction SilentlyContinue
        Write-Ok "$($layers.Substring(0,4)) removed HP.exe compatibility entry"
    }
}

$running = Join-Path $sysDir 'Running.ini'
if (Test-Path $running) { Remove-Item $running -Force -ErrorAction SilentlyContinue }

Write-Host "`nReverted to pre-fix state." -ForegroundColor Green
if ($BackupPath) { Write-Host "Restored from: $BackupPath" -ForegroundColor DarkGray }
Write-Host "`nPress Enter to close..."; [void][Console]::ReadLine()
