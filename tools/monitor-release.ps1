param(
    [int]$IntervalSeconds = 300,
    [string]$OutputDirectory = "output"
)

$ErrorActionPreference = "Stop"

$pidPath = Join-Path $OutputDirectory "pre-release.pid"
$buildLogPath = Join-Path $OutputDirectory "pre-release.stderr.log"
$monitorLogPath = Join-Path $OutputDirectory "release-monitor.log"

if ($IntervalSeconds -lt 60) {
    throw "Monitoring interval must be at least 60 seconds."
}

$buildPid = if (Test-Path -LiteralPath $pidPath) {
    [int](Get-Content -LiteralPath $pidPath)
} else {
    throw "Build PID file does not exist: $pidPath"
}

while ($true) {
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
    $running =
        $null -ne (Get-Process -Id $buildPid -ErrorAction SilentlyContinue)
    $step = if (Test-Path -LiteralPath $buildLogPath) {
        (
            Select-String -Path $buildLogPath -Pattern '^\#\d+ \[' |
                Select-Object -Last 1
        ).Line
    } else {
        ""
    }
    $logWriteTime = if (Test-Path -LiteralPath $buildLogPath) {
        (Get-Item -LiteralPath $buildLogPath).LastWriteTime.ToString(
            "yyyy-MM-ddTHH:mm:ssK"
        )
    } else {
        ""
    }

    [PSCustomObject]@{
        Timestamp = $timestamp
        Status = if ($running) { "RUNNING" } else { "FINISHED" }
        ProcessId = $buildPid
        BuildLogLastWrite = $logWriteTime
        Step = $step
    } | ConvertTo-Json -Compress |
        Add-Content -LiteralPath $monitorLogPath

    if (-not $running) {
        break
    }

    Start-Sleep -Seconds $IntervalSeconds
}
