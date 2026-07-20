<#
.SYNOPSIS
    One-command fix to run 'Harry Potter and the Philosopher's Stone' (2001, EA)
    on modern Windows 10 / 11.

.DESCRIPTION
    The 2001 game crashes on startup on modern Windows (Unreal Engine 1 hitting
    DEP during Direct3D init) and its DirectDraw/D3D8 path does not work on
    current GPUs. This script applies every fix automatically:

      1. Downloads the latest dgVoodoo2 from GitHub and installs the 32-bit
         DirectX wrapper DLLs into the game's System folder.
      2. Writes a tuned dgVoodoo.conf (watermark off, fullscreen scaling).
      3. Detects your display resolution / aspect ratio and picks the right
         dgVoodoo scaling mode so the 4:3 game fills your screen cleanly.
      4. Sets the game's internal resolution to its engine maximum (1024x768).
      5. Adds a DEP exclusion for HP.exe (the actual crash fix).
      6. Clears the stale crash-recovery marker.

    The script self-elevates (UAC) because the game usually lives in
    Program Files. It changes nothing outside the game folder except one
    machine-wide compatibility-layer registry value for HP.exe (the DEP
    exclusion, which must be in HKLM to be honored by DEP enforcement).

.PARAMETER GamePath
    Root of the installed game (the folder containing 'System\HP.exe').
    Auto-detected from the usual EA Games locations if omitted.

.PARAMETER DgVoodooZip
    Use a local dgVoodoo2 zip instead of downloading (offline installs).

.PARAMETER Scaling
    Force a dgVoodoo ScalingMode instead of auto-picking from your display
    (e.g. 'stretched', 'stretched_ar', 'centered', 'unspecified').

.EXAMPLE
    .\Apply-HP1Fix.ps1

.EXAMPLE
    .\Apply-HP1Fix.ps1 -GamePath 'D:\Games\Harry Potter TM'

.NOTES
    Repo: https://github.com/wolffbe/hp1
    dgVoodoo2 by Dege - https://github.com/dege-diosg/dgVoodoo2
#>
[CmdletBinding()]
param(
    [string]$GamePath,
    [string]$DgVoodooZip,
    [ValidateSet('auto','stretched','stretched_ar','stretched_4_3','centered','unspecified')]
    [string]$Scaling = 'auto'
)

$ErrorActionPreference = 'Stop'

# --- Self-elevate ---------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
          ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Requesting administrator rights (needed to write into Program Files)...' -ForegroundColor Yellow
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($GamePath)    { $argList += @('-GamePath',"`"$GamePath`"") }
    if ($DgVoodooZip) { $argList += @('-DgVoodooZip',"`"$DgVoodooZip`"") }
    if ($Scaling)     { $argList += @('-Scaling',$Scaling) }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    return
}

# --- Logging --------------------------------------------------------------
$logDir = Join-Path $env:LOCALAPPDATA 'HP1Fix'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp  = (Get-Date).ToString('yyyyMMdd-HHmmss')
Start-Transcript -Path (Join-Path $logDir "apply-$stamp.log") | Out-Null

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok  ($m) { Write-Host "    OK  $m" -ForegroundColor Green }

try {
    Write-Host 'Harry Potter 1 - modern Windows fix' -ForegroundColor White

    # --- 1. Locate the game ----------------------------------------------
    Write-Step 'Locating the game'
    if (-not $GamePath) {
        $candidates = @(
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
    Write-Ok $GamePath

    # --- 2. Detect display & choose scaling ------------------------------
    Write-Step 'Detecting display'
    $vc = Get-CimInstance Win32_VideoController |
          Where-Object { $_.CurrentHorizontalResolution } |
          Sort-Object CurrentHorizontalResolution -Descending | Select-Object -First 1
    $dw = [int]$vc.CurrentHorizontalResolution
    $dh = [int]$vc.CurrentVerticalResolution
    if (-not $dw -or -not $dh) { $dw = 1920; $dh = 1080 }   # sane fallback
    $aspect = [math]::Round($dw / $dh, 3)
    Write-Ok "$dw x $dh  (aspect $aspect)"

    if ($Scaling -eq 'auto') {
        # The game is 4:3 (1024x768). Fill a 4:3 screen; pillarbox a wide one
        # so nothing is distorted.
        if ([math]::Abs($aspect - (4/3)) -lt 0.02) { $scalingMode = 'stretched' }
        else                                       { $scalingMode = 'stretched_ar' }
    } else {
        $scalingMode = $Scaling
    }
    Write-Ok "dgVoodoo ScalingMode = $scalingMode"

    # --- 3. Obtain dgVoodoo2 ---------------------------------------------
    Write-Step 'Getting dgVoodoo2'
    $work = Join-Path $env:TEMP "hp1fix-$stamp"
    New-Item -ItemType Directory -Force -Path $work | Out-Null

    if ($DgVoodooZip) {
        $zip = $DgVoodooZip
        Write-Ok "Using local zip: $zip"
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $rel = Invoke-RestMethod 'https://api.github.com/repos/dege-diosg/dgVoodoo2/releases/latest' `
                                 -Headers @{ 'User-Agent' = 'hp1-fix' }
        # main release zip only: dgVoodoo2_XX_X.zip  (skip _dbg / _dev64 / API / WinMM)
        $asset = $rel.assets | Where-Object { $_.name -match '^dgVoodoo2_\d+_\d+\.zip$' } | Select-Object -First 1
        if (-not $asset) { throw 'Could not find a dgVoodoo2 release zip on GitHub.' }
        $zip = Join-Path $work $asset.name
        Write-Host "    downloading $($rel.tag_name)  ($($asset.name))..."
        Invoke-WebRequest $asset.browser_download_url -OutFile $zip -Headers @{ 'User-Agent' = 'hp1-fix' }
        Write-Ok "Downloaded dgVoodoo2 $($rel.tag_name)"
    }

    $ext = Join-Path $work 'dgv'
    Expand-Archive -Path $zip -DestinationPath $ext -Force

    $msx86 = Get-ChildItem -Path $ext -Recurse -Directory |
             Where-Object { $_.FullName -match '\\MS\\x86$' } | Select-Object -First 1
    if (-not $msx86) { throw 'dgVoodoo2 zip layout unexpected: MS\x86 not found.' }
    $confSrc = Get-ChildItem -Path $ext -Recurse -Filter 'dgVoodoo.conf' | Select-Object -First 1
    $cplSrc  = Get-ChildItem -Path $ext -Recurse -Filter 'dgVoodooCpl.exe' | Select-Object -First 1

    # --- 4. Back up, then install wrapper DLLs ---------------------------
    Write-Step 'Installing DirectX wrapper into the game'
    $backupDir = Join-Path $sysDir ('_HP1Fix_backup_' + $stamp)
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    foreach ($f in 'Default.ini','dgVoodoo.conf','DDraw.dll','D3D8.dll','D3D9.dll','D3DImm.dll') {
        $p = Join-Path $sysDir $f
        if (Test-Path $p) { Copy-Item $p (Join-Path $backupDir $f) -Force }
    }
    Write-Ok "Backed up existing files to $backupDir"

    foreach ($dll in 'DDraw.dll','D3D8.dll','D3D9.dll','D3DImm.dll') {
        Copy-Item (Join-Path $msx86.FullName $dll) (Join-Path $sysDir $dll) -Force
    }
    if ($cplSrc) { Copy-Item $cplSrc.FullName (Join-Path $sysDir 'dgVoodooCpl.exe') -Force }
    Write-Ok 'Copied DDraw/D3D8/D3D9/D3DImm (32-bit) + control panel'

    # Relocate leftovers from an earlier Wine / wined3d wrapper. They coexist
    # with dgVoodoo's DLLs but make the game crash during Direct3D init
    # (exit -805306369). Move them into the backup folder, not delete.
    $moved = @()
    foreach ($w in 'ddfuk.dll','libwine.dll','wined3d.dll') {
        $wp = Join-Path $sysDir $w
        if (Test-Path $wp) { Move-Item $wp (Join-Path $backupDir $w) -Force; $moved += $w }
    }
    if ($moved) { Write-Ok "Moved conflicting Wine/wined3d leftovers aside: $($moved -join ', ')" }

    # --- 5. Write a tuned dgVoodoo.conf ----------------------------------
    Write-Step 'Configuring dgVoodoo'
    $conf = Get-Content $confSrc.FullName
    $conf = $conf `
        -replace '^(\s*ScalingMode\s*=).*$',        "`$1 $scalingMode" `
        -replace '^(\s*FullScreenMode\s*=).*$',       '$1 true' `
        -replace '^(\s*dgVoodooWatermark\s*=).*$',     '$1 false' `
        -replace '^(\s*3DfxWatermark\s*=).*$',         '$1 false' `
        -replace '^(\s*FastVideoMemoryAccess\s*=).*$', '$1 true'
    $conf | Set-Content (Join-Path $sysDir 'dgVoodoo.conf') -Encoding ASCII
    Write-Ok 'dgVoodoo.conf written (watermark off, fullscreen scaling on)'

    # --- 6. Set the game's internal resolution (engine max 1024x768) -----
    Write-Step 'Setting game resolution'
    $iniPath = Join-Path $sysDir 'Default.ini'
    $ini = Get-Content $iniPath
    # Anchor on the WinDrv.WindowsClient defaults (800x600); the unused
    # XDrv.XClient section keeps its own 640x480 values.
    $ini = $ini `
        -replace '^WindowedViewportX=800$',  'WindowedViewportX=1024' `
        -replace '^WindowedViewportY=600$',  'WindowedViewportY=768'  `
        -replace '^FullscreenViewportX=800$','FullscreenViewportX=1024' `
        -replace '^FullscreenViewportY=600$','FullscreenViewportY=768'
    $ini | Set-Content $iniPath -Encoding ASCII
    Write-Ok 'Game set to 1024x768 (its engine maximum); dgVoodoo scales it to your screen'

    # --- 7. DEP exclusion for HP.exe (the crash fix) ---------------------
    # MUST be HKLM (machine-wide). DEP enforcement only honors the machine
    # exclusion list - a per-user HKCU 'DisableNXShowUI' sets the flag but the
    # kernel ignores it for NX, so the game still crashes (BEX / 0xc0000005)
    # when launched from Explorer. This is exactly what the System Properties
    # DEP tab writes, which is why it needs admin (the script self-elevated).
    Write-Step 'Applying DEP exclusion (fixes the startup crash)'
    $layers = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    if (-not (Test-Path $layers)) { New-Item -Path $layers -Force | Out-Null }
    $existing = (Get-ItemProperty -Path $layers -Name $exe -ErrorAction SilentlyContinue).$exe
    $tokens = @()
    if ($existing) { $tokens = @($existing -split '\s+' | Where-Object { $_ -and $_ -ne '~' }) }
    if ($tokens -notcontains 'DisableNXShowUI') { $tokens += 'DisableNXShowUI' }
    $value = (@('~') + $tokens) -join ' '
    New-ItemProperty -Path $layers -Name $exe -Value $value -PropertyType String -Force | Out-Null
    Write-Ok "HKLM Layers: $value"

    # --- 8. Clear stale crash-recovery marker ----------------------------
    $running = Join-Path $sysDir 'Running.ini'
    if (Test-Path $running) { Remove-Item $running -Force -ErrorAction SilentlyContinue }

    # --- Done ------------------------------------------------------------
    Write-Host "`nAll fixes applied." -ForegroundColor Green
    Write-Host "Launch the game from its normal shortcut or: $exe" -ForegroundColor Green
    Write-Host "A backup of the changed game files is in:`n  $backupDir" -ForegroundColor DarkGray
    Write-Host "Run Uninstall-HP1Fix.ps1 to revert." -ForegroundColor DarkGray
}
catch {
    Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally {
    Stop-Transcript | Out-Null
    if (-not $isAdmin) { } else { Write-Host "`nPress Enter to close..."; [void][Console]::ReadLine() }
}
