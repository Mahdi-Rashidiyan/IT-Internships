# JARVIS Legacy v2 - Windows 7 / Windows PowerShell 2.0
# Read-only system + internet monitor. No admin rights, no extra software.
# Run with:  Start-JARVIS.bat   (or: powershell -ExecutionPolicy Bypass -File JARVIS-Legacy.ps1)

$ErrorActionPreference = "SilentlyContinue"

# ---------------- SETTINGS (edit these) ----------------
$RefreshSeconds = 5
$GatewayIP      = "192.168.0.1"
$PingTarget     = "8.8.8.8"
$LogFile        = Join-Path $env:TEMP "jarvis-log.txt"
# -------------------------------------------------------

$script:LastRx = 0.0
$script:LastTx = 0.0
$script:LastTime = $null
$script:LastState = ""

try {
    $Host.UI.RawUI.WindowTitle = "JARVIS LEGACY | System + Internet Monitor"
    $Host.UI.RawUI.BackgroundColor = "Black"
    $Host.UI.RawUI.ForegroundColor = "Green"
    $raw = $Host.UI.RawUI
    $buf = $raw.BufferSize
    if ($buf.Height -lt 300) { $raw.BufferSize = New-Object System.Management.Automation.Host.Size($buf.Width, 300) }
    $ws = $raw.WindowSize
    $h = [math]::Min(58, $raw.MaxPhysicalWindowSize.Height)
    $raw.WindowSize = New-Object System.Management.Automation.Host.Size($ws.Width, $h)
} catch {}

function Get-WmiSafe {
    param([string]$Class, [string]$Namespace = "root\cimv2")
    try { return @(Get-WmiObject -Class $Class -Namespace $Namespace -ErrorAction Stop) }
    catch { return @() }
}

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N1} MB" -f ($Bytes / 1MB)) }
    return ("{0:N0} KB" -f ($Bytes / 1KB))
}

function Write-Line {
    param([string]$Label, [string]$Value, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host ("{0,-19}" -f $Label) -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Get-OrNA {
    param($Value)
    if ($Value -eq $null) { return "n/a" }
    $s = [string]$Value
    if ($s.Trim().Length -eq 0) { return "n/a" }
    return $s
}

function New-Result {
    param([bool]$Ok, [string]$Text)
    return (New-Object PSObject -Property @{ Ok = $Ok; Text = $Text })
}

function Write-Log {
    param([string]$Text)
    try { Add-Content -Path $LogFile -Value ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + "  " + $Text) } catch {}
}

# ---------------- INTERNET CHECKS ----------------
function Get-PingResult {
    param([string]$Address)
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            $r = @(Get-WmiObject -Class Win32_PingStatus -Filter ("Address='" + $Address + "' AND Timeout=1500") -ErrorAction Stop)[0]
            if ($r -ne $null -and $r.StatusCode -eq 0) { return (New-Result $true ([string]$r.ResponseTime + " ms")) }
        } catch {}
    }
    return (New-Result $false "no reply")
}

function Get-InternetStatus {
    $gwr = Get-PingResult $GatewayIP
    $ping = Get-PingResult $PingTarget

    if ($gwr.Ok -and $ping.Ok) {
        $state = "ONLINE"; $color = "Green"; $advice = "Everything is working."
    } elseif ($gwr.Ok) {
        $state = "INTERNET DOWN"; $color = "Yellow"
        $advice = "Be patient: wait 2 to 5 minutes, it usually fixes itself."
    } else {
        $state = "NETWORK DOWN"; $color = "Red"
        $advice = "Gateway not reachable: please call IT."
    }

    return (New-Object PSObject -Property @{
        Gw = $gwr; Ping = $ping; State = $state; Color = $color; Advice = $advice
    })
}

function Get-NetSpeed {
    $rx = 0.0; $tx = 0.0
    try {
        foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ($nic.OperationalStatus -ne "Up") { continue }
            $t = [string]$nic.NetworkInterfaceType
            if ($t -eq "Loopback" -or $t -eq "Tunnel") { continue }
            $s = $nic.GetIPv4Statistics()
            $rx += [double]$s.BytesReceived
            $tx += [double]$s.BytesSent
        }
    } catch {}
    $now = Get-Date
    $result = $null
    if ($script:LastTime -ne $null) {
        $secs = ($now - $script:LastTime).TotalSeconds
        if ($secs -gt 0) {
            $d = ($rx - $script:LastRx) / $secs
            $u = ($tx - $script:LastTx) / $secs
            if ($d -lt 0) { $d = 0 }
            if ($u -lt 0) { $u = 0 }
            $result = New-Object PSObject -Property @{ Down = $d; Up = $u }
        }
    }
    $script:LastRx = $rx
    $script:LastTx = $tx
    $script:LastTime = $now
    return $result
}

# ---------------- NVIDIA (optional, silently skipped) ----------------
function Get-NvidiaInfo {
    $exe = $null
    try {
        $cmd = Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue
        if ($cmd -ne $null) { $exe = [string]$cmd.Definition }
    } catch {}
    if (-not $exe) {
        $paths = @("C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe", "C:\Windows\System32\nvidia-smi.exe")
        foreach ($p in $paths) { if (Test-Path $p) { $exe = $p; break } }
    }
    if ($exe) {
        try {
            $out = & $exe --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>$null
            if ($LASTEXITCODE -eq 0 -and $out) { return (([string](@($out)[0])) -replace '\s*,\s*', ' | ') }
        } catch {}
    }
    return $null
}

# ---------------- DASHBOARD ----------------
function Show-Dashboard {
    # Slow checks run BEFORE clearing, so the screen never goes blank while waiting.
    $net = Get-InternetStatus
    $speed = Get-NetSpeed
    $nv = Get-NvidiaInfo

    if ($net.State -ne $script:LastState) {
        Write-Log ("STATE: " + $net.State + "  | gateway=" + $net.Gw.Text + " | ping=" + $net.Ping.Text)
        $script:LastState = $net.State
    }

    $now = Get-Date
    $os = @(Get-WmiSafe "Win32_OperatingSystem")[0]
    $cs = @(Get-WmiSafe "Win32_ComputerSystem")[0]
    $cpu = @(Get-WmiSafe "Win32_Processor")[0]
    $gpus = @(Get-WmiSafe "Win32_VideoController")
    $ramModules = @(Get-WmiSafe "Win32_PhysicalMemory")
    $disks = @(Get-WmiSafe "Win32_LogicalDisk" | Where-Object { $_.DriveType -eq 3 })
    $adapters = @(Get-WmiSafe "Win32_NetworkAdapterConfiguration" | Where-Object { $_.IPEnabled -eq $true })

    Clear-Host
    Write-Host "==============================================================" -ForegroundColor Green
    Write-Host "                 J A R V I S   L E G A C Y                    " -ForegroundColor Cyan
    Write-Host "              SYSTEM + INTERNET MONITOR  |  WIN 7            " -ForegroundColor DarkCyan
    Write-Host "==============================================================" -ForegroundColor Green
    Write-Host ("  {0}     Host: {1}     User: {2}" -f $now.ToString("yyyy-MM-dd HH:mm:ss"), $env:COMPUTERNAME, $env:USERNAME) -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------------------" -ForegroundColor DarkGreen

    Write-Host " [ INTERNET ]" -ForegroundColor Yellow
    Write-Line "Status" $net.State $net.Color
    Write-Line ("Gateway " + $GatewayIP) $net.Gw.Text
    Write-Line ("Ping " + $PingTarget) $net.Ping.Text
    Write-Line "Advice" $net.Advice $net.Color
    if ($speed -ne $null) {
        Write-Line "Download" ((Format-Bytes $speed.Down) + "/s") Cyan
        Write-Line "Upload" ((Format-Bytes $speed.Up) + "/s") Cyan
    } else {
        Write-Line "Speed" "measuring..." DarkGray
    }

    Write-Host "`n [ SYSTEM ]" -ForegroundColor Yellow
    if ($os) {
        Write-Line "Operating system" ((Get-OrNA $os.Caption) + " (Build " + (Get-OrNA $os.BuildNumber) + ")")
        try {
            $up = $now - $os.ConvertToDateTime($os.LastBootUpTime)
            Write-Line "Uptime" ("{0}d {1}h {2}m" -f $up.Days, $up.Hours, $up.Minutes)
        } catch {}
    }
    if ($cs) { Write-Line "Manufacturer" ((Get-OrNA $cs.Manufacturer) + " " + (Get-OrNA $cs.Model)) }
    if ($cpu) {
        Write-Line "Processor" (Get-OrNA $cpu.Name)
        Write-Line "CPU cores / threads" ((Get-OrNA $cpu.NumberOfCores) + " / " + (Get-OrNA $cpu.NumberOfLogicalProcessors))
        Write-Line "CPU max clock" ((Get-OrNA $cpu.MaxClockSpeed) + " MHz")
        $load = "n/a"
        if ($cpu.LoadPercentage -ne $null) { $load = [string]$cpu.LoadPercentage + "%" }
        Write-Line "CPU load" $load Cyan
    }

    Write-Host "`n [ MEMORY ]" -ForegroundColor Yellow
    if ($os) {
        $total = [double]$os.TotalVisibleMemorySize * 1KB
        $free = [double]$os.FreePhysicalMemory * 1KB
        $used = $total - $free
        $pct = 0
        if ($total -gt 0) { $pct = [math]::Round(($used / $total) * 100, 1) }
        Write-Line "RAM in use" ((Format-Bytes $used) + " / " + (Format-Bytes $total) + "  (" + $pct + "%)") Cyan
        Write-Line "RAM available" (Format-Bytes $free)
    }
    $i = 0
    foreach ($m in $ramModules) {
        $i++
        Write-Line ("DIMM " + $i) ((Format-Bytes ([double]$m.Capacity)) + " | " + (Get-OrNA $m.Speed) + " MHz | " + (Get-OrNA $m.Manufacturer))
    }

    Write-Host "`n [ GRAPHICS ]" -ForegroundColor Yellow
    if ($gpus.Count -gt 0) {
        foreach ($g in $gpus) {
            Write-Line "GPU" (Get-OrNA $g.Name) Cyan
            if ($g.AdapterRAM) { Write-Line "Reported VRAM" (Format-Bytes ([double]$g.AdapterRAM)) }
            Write-Line "Driver version" (Get-OrNA $g.DriverVersion)
        }
    } else { Write-Line "GPU" "No WMI graphics adapter found" Red }
    if ($nv) { Write-Line "NVIDIA telemetry" $nv DarkCyan }

    Write-Host "`n [ STORAGE ]" -ForegroundColor Yellow
    foreach ($d in $disks) {
        $size = [double]$d.Size
        $dfree = [double]$d.FreeSpace
        if ($size -gt 0) {
            $usedPct = [math]::Round((($size - $dfree) / $size) * 100, 1)
            $color = "Gray"
            if ($usedPct -ge 90) { $color = "Red" } elseif ($usedPct -ge 75) { $color = "Yellow" }
            Write-Line ($d.DeviceID + " " + $d.VolumeName) ((Format-Bytes ($size - $dfree)) + " used / " + (Format-Bytes $size) + " | " + $usedPct + "%") $color
        }
    }

    Write-Host "`n [ NETWORK ADAPTERS ]" -ForegroundColor Yellow
    if ($adapters.Count -eq 0) { Write-Line "Adapters" "No active IP configuration found" DarkYellow }
    foreach ($a in $adapters) {
        Write-Line "Adapter" (Get-OrNA $a.Description)
        if ($a.IPAddress) { Write-Line "IP address" ([string]::Join(", ", $a.IPAddress)) }
        if ($a.DNSServerSearchOrder) { Write-Line "DNS servers" ([string]::Join(", ", $a.DNSServerSearchOrder)) }
    }

    Write-Host "`n [ TOP 5 PROCESSES BY RAM ]" -ForegroundColor Yellow
    Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5 | ForEach-Object {
        Write-Line ($_.ProcessName + " (" + $_.Id + ")") (Format-Bytes ([double]$_.WorkingSet))
    }

    Write-Host "--------------------------------------------------------------" -ForegroundColor DarkGreen
    Write-Host (" Refresh: " + $RefreshSeconds + "s  |  Q = quit, R = refresh now") -ForegroundColor Green
    Write-Host (" Log: " + $LogFile) -ForegroundColor DarkGray
}

# ---------------- MAIN LOOP ----------------
Write-Host "Starting JARVIS Legacy..." -ForegroundColor Cyan
Start-Sleep -Seconds 1
$keysOk = $true
while ($true) {
    Show-Dashboard
    $ticks = $RefreshSeconds * 4
    for ($i = 0; $i -lt $ticks; $i++) {
        $pressed = $null
        if ($keysOk) {
            try { if ([Console]::KeyAvailable) { $pressed = [Console]::ReadKey($true) } }
            catch { $keysOk = $false }
        }
        if ($pressed -ne $null) {
            if ($pressed.Key -eq "Q") {
                Clear-Host
                Write-Host "JARVIS Legacy shut down. Goodbye." -ForegroundColor Cyan
                exit
            }
            if ($pressed.Key -eq "R") { break }
        }
        Start-Sleep -Milliseconds 250
    }
}