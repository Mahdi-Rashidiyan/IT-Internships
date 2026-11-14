# IT-Internships
# JARVIS Legacy

A lightweight system and internet monitor for **Windows 7** and **Windows PowerShell 2.0**.

It was built for locked-down university computers: no admin rights, no Python, no IDE, no extra software. It is two plain text files that you can write and edit in Notepad.

## Features

- **Internet monitor:** pings your gateway and a public IP, then tells you what to do
- **Live network speed:** download and upload per second
- **System info:** OS, uptime, CPU, RAM (including each memory stick), GPU, disks, network adapters
- **Top 5 processes** by RAM usage
- **Colour warnings** when a disk is above 75% (yellow) or 90% (red) full
- **Outage log:** every status change is saved with a timestamp
- **Optional NVIDIA stats:** shown only if `nvidia-smi` exists, silently skipped otherwise
- **Read-only:** it never changes anything on the computer

## Requirements

- Windows 7 or newer
- Windows PowerShell 2.0 or newer (built into Windows 7)

Nothing else is needed.

## Files

| File | Purpose |
|---|---|
| `JARVIS-Legacy.ps1` | The monitor itself |
| `Start-JARVIS.bat` | Launcher that bypasses the Windows 7 script restriction |

Keep both files in the same folder.

## Usage

1. Download both files into one folder.
2. Double-click **`Start-JARVIS.bat`**.
3. Keys while running:
   - `Q` quits
   - `R` refreshes immediately

Tip: maximize the console window so the whole dashboard fits on screen.

### If the launcher is blocked

If group policy blocks the `.bat`, open PowerShell and paste the contents of `JARVIS-Legacy.ps1` directly into the window.

## How the internet status works

The script pings the gateway (`192.168.0.1`) and `8.8.8.8`. Each ping is tried twice before it counts as a failure.

| Gateway | 8.8.8.8 | Status | Advice |
|---|---|---|---|
| OK | OK | ONLINE (green) | Everything is working. |
| OK | fail | INTERNET DOWN (yellow) | Wait 2 to 5 minutes, it usually fixes itself. |
| fail | any | NETWORK DOWN (red) | Gateway not reachable: call IT. |

## Settings

Edit the block at the top of `JARVIS-Legacy.ps1`:

```powershell
$RefreshSeconds = 5
$GatewayIP      = "192.168.0.1"
$PingTarget     = "8.8.8.8"
$LogFile        = Join-Path $env:TEMP "jarvis-log.txt"
```

## Log file

Each time the status changes, a line is added to `%TEMP%\jarvis-log.txt`, for example:

```
2026-11-14 10:32:05  STATE: INTERNET DOWN  | gateway=1 ms | ping=no reply
```

Show this file to IT when reporting an outage.

## Saving the files in Notepad

- Set "Save as type" to **All Files** so Notepad does not add `.txt`
- Set Encoding to **ANSI** (do not use UTF-8 or Unicode)
- The files use only plain ASCII characters

## Known limitations

- If the network firewall blocks pings to `8.8.8.8`, the status will show INTERNET DOWN even when the internet works. Change `$PingTarget` to an address that answers pings.
- GPU load and temperature are only available when `nvidia-smi` is installed. Windows 7 has no built-in counter for them.
- Reported VRAM is capped at 4 GB because of a Windows 7 limitation.
- The first network speed reading shows "measuring..." until the second refresh.
- Network speed adds up all active adapters, so a VPN adapter can be counted twice.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Running scripts is disabled" | Start it with `Start-JARVIS.bat` instead of double-clicking the `.ps1` |
| Weird characters or errors on line 1 | Re-save the file with ANSI encoding |
| Some info shows `n/a` | The hardware does not report that value; this is normal |
| Window text is cut off | Maximize the console window |
