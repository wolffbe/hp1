# Harry Potter and the Philosopher's Stone — Fix (Windows 10/11)

Gets the 2001 EA game **Harry Potter and the Philosopher's Stone**
(US title: *Sorcerer's Stone*, `HP.exe`, Unreal Engine 1) running on modern
**Windows 10 & 11**, where it otherwise **crashes on startup** — the game
window appears for a second and then it dies to desktop.

One PowerShell script does everything: it downloads the latest **dgVoodoo2**,
detects your display, and applies all the fixes.

🎮 **Game disc image (ISO):**
https://archive.org/details/harry-potter-and-the-philosophers-stone-windows-pc-uk-harry-potter-1-ps-ibm-pc

## Why it breaks on modern Windows

Two independent problems, both fixed here:

| Symptom | Cause | Fix |
|---|---|---|
| **Crash on launch** (`0xc0000005`, WER type `BEX`) right after the 3D init | **DEP** (Data Execution Prevention) kills this Unreal Engine 1 exe during Direct3D init. Reproduces *with or without* dgVoodoo. | A machine-wide (`HKLM`) **DEP exclusion** for `HP.exe`. |
| Black screen / "can't set display mode" / bad rendering | The 2001 **DirectDraw / Direct3D 8** path doesn't work on current GPUs. | **dgVoodoo2** wraps DirectDraw/D3D8 onto modern D3D11/12. |
| Wants the CD in the drive; won't start | **SafeDisc** copy protection — its driver (`secdrv.sys`) is disabled on modern Windows for security. | A **DRM-free `HP.exe`** for the copy you own (out of scope here — see [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Harry_Potter_and_the_Philosopher%27s_Stone)). |

## How to install

1. **Install the game.** Download the ISO from the link above, mount it
   (double-click the `.iso` on Windows 10/11), run `setup`, and install.
   When it asks for a **serial key**, use the one that came with your copy.

2. **Replace the executable.** The installed `HP.exe` is SafeDisc-protected,
   and SafeDisc cannot work on Windows 10/11 (its driver was removed for
   security) — the game will demand the disc and refuse to start. Obtaining a
   DRM-free `HP.exe` for the copy you own is up to you and out of scope here
   (see [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Harry_Potter_and_the_Philosopher%27s_Stone));
   copy it into the game's `System` folder, replacing the installed one.

3. **Run the fix.** Download this repo (green **Code → Download ZIP**, then
   extract), open **PowerShell** in the extracted folder and run:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass -Force
   .\scripts\Apply-HP1Fix.ps1
   ```

   It will ask for administrator rights (the game lives in Program Files),
   download the latest dgVoodoo2, and apply everything. When it finishes,
   launch the game from its normal desktop shortcut.

If the game isn't in a standard EA Games folder, point the script at it:

```powershell
.\scripts\Apply-HP1Fix.ps1 -GamePath 'D:\Games\Harry Potter TM'
```

## What the script changes

Inside the game's `System\` folder:

- Installs dgVoodoo2's 32-bit wrapper DLLs: `DDraw.dll`, `D3D8.dll`,
  `D3D9.dll`, `D3DImm.dll`, plus `dgVoodooCpl.exe`.
- Writes a tuned **`dgVoodoo.conf`**: fullscreen scaling on, **watermark off**.
- Sets the game to **1024×768** in `Default.ini` (its engine maximum — see
  below). dgVoodoo then scales that up to fill your screen.
- Moves aside any leftover **Wine / wined3d** wrapper DLLs (`ddfuk.dll`,
  `libwine.dll`, `wined3d.dll`) — if you previously tried wined3d, they
  conflict with dgVoodoo and cause a second Direct3D-init crash.

Machine-wide (no reboot):

- Adds `DisableNXShowUI` to `HP.exe` under
  **`HKLM`**`\…\AppCompatFlags\Layers` — this is the **DEP exclusion** that
  stops the crash. It must be in `HKLM` (machine-wide): a per-user `HKCU`
  entry sets the flag but DEP enforcement ignores it, so the game keeps
  crashing when launched from Explorer. This is the same thing the Windows
  *System Properties → Performance → DEP* exclusion list writes.

Before touching anything it copies the originals to a timestamped
`System\_HP1Fix_backup_*` folder, and it logs the whole run to
`%LOCALAPPDATA%\HP1Fix\`.

## Display / resolution

The script reads your monitor's resolution and picks the dgVoodoo scaling mode
automatically:

- **4:3 monitor** → `stretched` (fills the screen exactly).
- **16:9 / 16:10 / ultrawide** → `stretched_ar` (keeps the game's 4:3 shape
  with side bars, so nothing looks stretched).

Override it if you prefer, e.g. edge-to-edge on a widescreen:

```powershell
.\scripts\Apply-HP1Fix.ps1 -Scaling stretched
```

> **Why 1024×768?** This 2001 build's Direct3D driver **hard-caps at
> 1024×768** — every higher request (1280×1024, 1600×1200, 1920×1080…)
> clamps back down to it (`[optionsettings] MaxRes=1024` in the config
> reflects this). So the game renders at its 1024×768 maximum and dgVoodoo
> upscales it to your native resolution. True higher-res internal rendering
> would require replacing the engine's renderer, which this fix does not do.

## Requirements

- 64-bit Windows 10 or 11, administrator rights.
- PowerShell 5.1+ (built in) and an internet connection (to fetch dgVoodoo2).
- A legally-owned copy of the game, installed.

## Reverting

```powershell
.\scripts\Uninstall-HP1Fix.ps1
```

Restores the backed-up config, removes the dgVoodoo DLLs the fix added, and
removes the DEP token from `HP.exe`. (This returns the install to its original
state — which on modern Windows means it will crash again.)

## Offline install

Already have a dgVoodoo2 zip? Skip the download:

```powershell
.\scripts\Apply-HP1Fix.ps1 -DgVoodooZip 'C:\Downloads\dgVoodoo2_87_3.zip'
```

## Recommended additional fixes

Not part of this repo, but this is good additional work that pairs well with
the fix above and further improves the experience — apply it **after** the
base fix:

- **Movement & Camera Improvement** by AdamJD —
  [ModDB](https://www.moddb.com/games/harry-potter-and-the-sorcerers-stone/downloads/hp1-movement-and-camera-improvement).
  Smoother movement, a better camera, and improved climbing. (Bonus: hold
  **Space** at the start of a spell-learning cutscene to skip it.) Copy its
  packages into the game's `System` folder.

- **60 FPS Fix** by Chip-Biscuit —
  [GitHub](https://github.com/Chip-Biscuit/Harry-Potter-and-the-Philosopher-s-Stone-PC-FPS-Fix).
  Caps the game at 60 FPS to fix physics/animation glitches caused by modern
  hardware running the engine too fast. Drop `hp1-60FPSLauncher.exe` next to
  `HP.exe` and launch through it (the DEP exclusion still applies, since it
  runs `HP.exe`).

## Legal

This repository contains **scripts only**. It ships no game files, no dgVoodoo
binaries, and no cracks or serials. dgVoodoo2 is downloaded at runtime from its
official [GitHub releases](https://github.com/dege-diosg/dgVoodoo2). *Harry
Potter and the Philosopher's Stone* is © Electronic Arts / Warner Bros.
dgVoodoo2 is © Dege. Use only media you legally own.
