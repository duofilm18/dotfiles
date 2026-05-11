Add-Type -AssemblyName System.Web

$ErrorActionPreference = "Stop"
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::InvariantCulture

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:8976/")
$listener.Start()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cpuCounter = [System.Diagnostics.PerformanceCounter]::new("Processor", "% Processor Time", "_Total")
[void]$cpuCounter.NextValue()
$previousNetwork = $null
$previousSampleTime = Get-Date

function Format-JsonResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$Body
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.StatusCode = 200
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Write-TextResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [string]$ContentType,
        [byte[]]$Bytes
    )

    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.ContentLength64 = $Bytes.Length
    $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $Response.OutputStream.Close()
}

function Get-RamSnapshot {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $totalGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeGb = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $usedGb = [math]::Round($totalGb - $freeGb, 1)
    $usedPct = [int][math]::Round((($usedGb / $totalGb) * 100), 0)

    return @{
        total_gb = $totalGb
        used_gb = $usedGb
        used_pct = $usedPct
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
        received_bytes = $received
        sent_bytes = $sent
    }
}

function Get-StatsPayload {
    $cpu = [int][math]::Round($cpuCounter.NextValue(), 0)
    $ram = Get-RamSnapshot
    $currentNetwork = Get-NetworkSnapshot
    $now = Get-Date

    if ($null -eq $previousNetwork) {
        $script:previousNetwork = $currentNetwork
        $script:previousSampleTime = $now.AddSeconds(-1)
    }

    $elapsed = [math]::Max((New-TimeSpan -Start $previousSampleTime -End $now).TotalSeconds, 1)
    $downRate = [math]::Max(($currentNetwork.received_bytes - $previousNetwork.received_bytes) / $elapsed, 0)
    $upRate = [math]::Max(($currentNetwork.sent_bytes - $previousNetwork.sent_bytes) / $elapsed, 0)

    $script:previousNetwork = $currentNetwork
    $script:previousSampleTime = $now

    return @{
        cpu_pct = $cpu
        ram = $ram
        network = @{
            down_bps = [math]::Round($downRate, 2)
            up_bps = [math]::Round($upRate, 2)
        }
        ts = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    } | ConvertTo-Json -Depth 4 -Compress
}

function Get-StaticContentType {
    param([string]$Path)

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".html" { return "text/html; charset=utf-8" }
        ".css" { return "text/css; charset=utf-8" }
        ".js" { return "application/javascript; charset=utf-8" }
        ".json" { return "application/json; charset=utf-8" }
        default { return "application/octet-stream" }
    }
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $path = $request.Url.AbsolutePath

        if ($path -eq "/api/stats") {
            $body = Get-StatsPayload
            Format-JsonResponse -Response $response -Body $body
            continue
        }

        $relativePath = if ($path -eq "/") { "index.html" } else { $path.TrimStart("/") }
        $filePath = Join-Path $scriptDir $relativePath

        if (Test-Path $filePath -PathType Leaf) {
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $contentType = Get-StaticContentType -Path $filePath
            Write-TextResponse -Response $response -StatusCode 200 -ContentType $contentType -Bytes $bytes
            continue
        }

        $notFound = [System.Text.Encoding]::UTF8.GetBytes("Not found")
        Write-TextResponse -Response $response -StatusCode 404 -ContentType "text/plain; charset=utf-8" -Bytes $notFound
    }
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }

    $listener.Close()
    $cpuCounter.Dispose()
}
