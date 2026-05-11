Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class NativeWindow {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int X,
        int Y,
        int cx,
        int cy,
        uint uFlags
    );
}
"@

[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $scriptDir "settings.txt"
$runBatPath = Join-Path $scriptDir "run-widget.bat"

function Get-StartupShortcutPath {
    $startupDir = [Environment]::GetFolderPath("Startup")
    return Join-Path $startupDir "System Usage Widget.lnk"
}

function Test-StartupShortcut {
    return Test-Path (Get-StartupShortcutPath)
}

function Enable-StartupShortcut {
    param(
        [string]$TargetPath,
        [string]$WorkingDirectory
    )

    $shortcutPath = Get-StartupShortcutPath
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,44"
    $shortcut.Save()
}

function Disable-StartupShortcut {
    $shortcutPath = Get-StartupShortcutPath
    if (Test-Path $shortcutPath) {
        Remove-Item $shortcutPath -Force
    }
}

function Get-StartupMenuLabel {
    if (Test-StartupShortcut) {
        return "Disable startup"
    }

    return "Enable startup"
}

function Get-WidgetSettings {
    param(
        [string]$Path
    )

    $settings = @{
        download_mbps = 500.0
        upload_mbps = 500.0
    }

    if (-not (Test-Path $Path)) {
        return $settings
    }

    foreach ($line in Get-Content -Path $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed -split "=", 2
        if ($parts.Count -ne 2) {
            continue
        }

        $key = $parts[0].Trim().ToLowerInvariant()
        $value = $parts[1].Trim()
        $parsed = 0.0

        if ([double]::TryParse($value, [ref]$parsed) -and $parsed -gt 0) {
            if ($key -in @("download_mbps", "upload_mbps")) {
                $settings[$key] = $parsed
            }
        }
    }

    return $settings
}

function Set-AlwaysOnTop {
    param(
        [System.Windows.Forms.Form]$Form
    )

    $HWND_TOPMOST = [IntPtr]::new(-1)
    $SWP_NOSIZE = 0x0001
    $SWP_NOMOVE = 0x0002
    $SWP_NOACTIVATE = 0x0010
    $SWP_SHOWWINDOW = 0x0040
    $flags = $SWP_NOSIZE -bor $SWP_NOMOVE -bor $SWP_NOACTIVATE -bor $SWP_SHOWWINDOW

    $Form.TopMost = $true
    [void][NativeWindow]::SetWindowPos($Form.Handle, $HWND_TOPMOST, 0, 0, 0, 0, $flags)
}

function Format-Rate {
    param(
        [double]$BytesPerSecond
    )

    if ($BytesPerSecond -lt 1KB) {
        return ("{0:N0} B/s" -f $BytesPerSecond)
    }
    if ($BytesPerSecond -lt 1MB) {
        return ("{0:N1} KB/s" -f ($BytesPerSecond / 1KB))
    }
    if ($BytesPerSecond -lt 1GB) {
        return ("{0:N1} MB/s" -f ($BytesPerSecond / 1MB))
    }

    return ("{0:N2} GB/s" -f ($BytesPerSecond / 1GB))
}

function Format-RateWithUsage {
    param(
        [double]$BytesPerSecond,
        [double]$LimitMbps
    )

    $baseText = Format-Rate -BytesPerSecond $BytesPerSecond
    if ($LimitMbps -le 0) {
        return $baseText
    }

    $currentMbps = ($BytesPerSecond * 8) / 1MB
    $usagePct = [int][math]::Round(($currentMbps / $LimitMbps) * 100, 0)
    return ("{0} ({1}%)" -f $baseText, [math]::Max($usagePct, 0))
}

function Get-RamSnapshot {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $totalGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeGb = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $usedGb = [math]::Round($totalGb - $freeGb, 1)
    $usedPct = [int][math]::Round((($usedGb / $totalGb) * 100), 0)

    return @{
        TotalGb = $totalGb
        UsedGb = $usedGb
        UsedPct = $usedPct
    }
}

function Get-NetworkSnapshot {
    $adapters = Get-NetAdapter | Where-Object {
        $_.Status -eq "Up" -and $_.HardwareInterface
    }

    $received = 0.0
    $sent = 0.0

    foreach ($adapter in $adapters) {
        $stats = Get-NetAdapterStatistics -Name $adapter.Name
        $received += [double]$stats.ReceivedBytes
        $sent += [double]$stats.SentBytes
    }

    return @{
        ReceivedBytes = $received
        SentBytes = $sent
    }
}

function Update-TrayText {
    param(
        [System.Windows.Forms.NotifyIcon]$NotifyIcon,
        [int]$CpuUsage,
        [int]$RamUsage,
        [string]$DownText,
        [string]$UpText
    )

    $text = "CPU ${CpuUsage}% | RAM ${RamUsage}% | D $DownText | U $UpText"
    if ($text.Length -gt 63) {
        $text = $text.Substring(0, 63)
    }
    $NotifyIcon.Text = $text
}

$settings = Get-WidgetSettings -Path $settingsPath
if (Test-Path $runBatPath) {
    Enable-StartupShortcut -TargetPath $runBatPath -WorkingDirectory $scriptDir
}
$cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total")
[void]$cpuCounter.NextValue()

$script:previousNetwork = Get-NetworkSnapshot
$script:previousSampleTime = Get-Date
$script:isTrayMode = $false

$form = New-Object System.Windows.Forms.Form
$form.Text = "System Usage"
$form.Width = 250
$form.Height = 160
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 28, 34)
$form.Opacity = 0.94

$workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(
    ($workingArea.Right - $form.Width - 18),
    ($workingArea.Bottom - $form.Height - 18)
)

$header = New-Object System.Windows.Forms.Label
$header.Text = "SYSTEM USAGE"
$header.ForeColor = [System.Drawing.Color]::FromArgb(220, 225, 232)
$header.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11, [System.Drawing.FontStyle]::Bold)
$header.Location = New-Object System.Drawing.Point(14, 10)
$header.AutoSize = $true
$form.Controls.Add($header)

$subHeader = New-Object System.Windows.Forms.Label
$subHeader.Text = ("Plan {0}/{1} Mbps" -f [int]$settings.download_mbps, [int]$settings.upload_mbps)
$subHeader.ForeColor = [System.Drawing.Color]::FromArgb(140, 150, 162)
$subHeader.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$subHeader.Location = New-Object System.Drawing.Point(14, 31)
$subHeader.AutoSize = $true
$form.Controls.Add($subHeader)

$labels = @{}
$rows = @(
    @{ Name = "CPU"; Y = 58; Color = [System.Drawing.Color]::FromArgb(255, 184, 108) },
    @{ Name = "RAM"; Y = 82; Color = [System.Drawing.Color]::FromArgb(80, 250, 123) },
    @{ Name = "DOWN"; Y = 106; Color = [System.Drawing.Color]::FromArgb(139, 233, 253) },
    @{ Name = "UP"; Y = 130; Color = [System.Drawing.Color]::FromArgb(255, 121, 198) }
)

foreach ($row in $rows) {
    $nameLabel = New-Object System.Windows.Forms.Label
    $nameLabel.Text = $row.Name
    $nameLabel.ForeColor = $row.Color
    $nameLabel.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $nameLabel.Location = New-Object System.Drawing.Point(14, $row.Y)
    $nameLabel.AutoSize = $true
    $form.Controls.Add($nameLabel)

    $valueLabel = New-Object System.Windows.Forms.Label
    $valueLabel.Text = "--"
    $valueLabel.ForeColor = [System.Drawing.Color]::FromArgb(235, 239, 244)
    $valueLabel.Font = New-Object System.Drawing.Font("Consolas", 10)
    $valueLabel.Location = New-Object System.Drawing.Point(78, $row.Y)
    $valueLabel.AutoSize = $true
    $form.Controls.Add($valueLabel)

    $labels[$row.Name] = $valueLabel
}

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
$notifyIcon.Visible = $true
$notifyIcon.Text = "System Usage"

$startupLabel = Get-StartupMenuLabel
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$showItem = $trayMenu.Items.Add("Show widget")
$showItem.add_Click({
    $script:isTrayMode = $false
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    Set-AlwaysOnTop -Form $form
})
$startupItem = $trayMenu.Items.Add($startupLabel)
$startupMenuItem = $null
$updateStartupMenuLabels = {
    $label = Get-StartupMenuLabel
    $startupItem.Text = $label
    if ($startupMenuItem -ne $null) {
        $startupMenuItem.Text = $label
    }
}
$startupItem.add_Click({
    if (Test-StartupShortcut) {
        Disable-StartupShortcut
    } else {
        Enable-StartupShortcut -TargetPath $runBatPath -WorkingDirectory $scriptDir
    }

    & $updateStartupMenuLabels
})
$openFolderTrayItem = $trayMenu.Items.Add("Open widget folder")
$openFolderTrayItem.add_Click({
    Start-Process explorer.exe $scriptDir
})
$null = $trayMenu.Items.Add("-")
$trayExitItem = $trayMenu.Items.Add("Exit")
$trayExitItem.add_Click({
    $timer.Stop()
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    $cpuCounter.Dispose()
    $form.Close()
})
$notifyIcon.ContextMenuStrip = $trayMenu
$notifyIcon.add_DoubleClick({
    $script:isTrayMode = $false
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    Set-AlwaysOnTop -Form $form
})

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$trayItem = $menu.Items.Add("Hide to tray")
$trayItem.add_Click({
    $script:isTrayMode = $true
    $form.Hide()
})
$startupMenuItem = $menu.Items.Add($startupLabel)
$startupMenuItem.add_Click({
    if (Test-StartupShortcut) {
        Disable-StartupShortcut
    } else {
        Enable-StartupShortcut -TargetPath $runBatPath -WorkingDirectory $scriptDir
    }

    & $updateStartupMenuLabels
})
$openFolderItem = $menu.Items.Add("Open widget folder")
$openFolderItem.add_Click({
    Start-Process explorer.exe $scriptDir
})
$null = $menu.Items.Add("-")
$exitItem = $menu.Items.Add("Exit")
$exitItem.add_Click({
    $timer.Stop()
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    $cpuCounter.Dispose()
    $form.Close()
})
$form.ContextMenuStrip = $menu

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    try {
        if (-not $script:isTrayMode) {
            Set-AlwaysOnTop -Form $form
        }

        $cpuUsage = [int][math]::Round($cpuCounter.NextValue(), 0)
        $ram = Get-RamSnapshot
        $currentNetwork = Get-NetworkSnapshot
        $now = Get-Date
        $elapsed = [math]::Max((New-TimeSpan -Start $script:previousSampleTime -End $now).TotalSeconds, 1)

        $downRate = ($currentNetwork.ReceivedBytes - $script:previousNetwork.ReceivedBytes) / $elapsed
        $upRate = ($currentNetwork.SentBytes - $script:previousNetwork.SentBytes) / $elapsed

        $downText = Format-RateWithUsage -BytesPerSecond ([math]::Max($downRate, 0)) -LimitMbps $settings.download_mbps
        $upText = Format-RateWithUsage -BytesPerSecond ([math]::Max($upRate, 0)) -LimitMbps $settings.upload_mbps

        $labels["CPU"].Text = ("{0,3}%" -f $cpuUsage)
        $labels["RAM"].Text = ("{0,4}%  ({1:N1}/{2:N1} GB)" -f $ram.UsedPct, $ram.UsedGb, $ram.TotalGb)
        $labels["DOWN"].Text = $downText
        $labels["UP"].Text = $upText

        Update-TrayText -NotifyIcon $notifyIcon -CpuUsage $cpuUsage -RamUsage $ram.UsedPct -DownText $downText -UpText $upText

        $script:previousNetwork = $currentNetwork
        $script:previousSampleTime = $now
    }
    catch {
        $labels["CPU"].Text = "ERR"
        $labels["RAM"].Text = "ERR"
        $labels["DOWN"].Text = "ERR"
        $labels["UP"].Text = "ERR"
        $notifyIcon.Text = "System Usage"
    }
})

$form.Add_Shown({
    Set-AlwaysOnTop -Form $form
    $timer.Start()
})

$form.Add_Activated({
    if (-not $script:isTrayMode) {
        Set-AlwaysOnTop -Form $form
    }
})

$form.Add_FormClosed({
    $timer.Stop()
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    $cpuCounter.Dispose()
})

[System.Windows.Forms.Application]::Run($form)
