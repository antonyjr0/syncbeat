<#
Passive collection only. No intents, input, log clearing, settings, HCI or pcap.
Run persistently in a hidden PowerShell process; stop with -Mode Stop -SessionPath.
Raw diagnostics can contain private information: tools/ is excluded from Git.
#>
[CmdletBinding()]
param(
    [ValidateSet('Start','Stop','Status')][string]$Mode = 'Start',
    [string]$SessionPath,
    [string]$Serial,
    [string]$Adb = "$env:LOCALAPPDATA/Android/sdk/platform-tools/adb.exe"
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$captureRoot = Join-Path $root 'tools/zepp-transfer'
if ($Mode -ne 'Start') {
    if (-not $SessionPath) { throw 'Specify -SessionPath for Stop/Status.' }
    $session = (Resolve-Path -LiteralPath $SessionPath).Path
    if (-not $session.StartsWith(([IO.Path]::GetFullPath($captureRoot) + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) { throw 'Session must be inside tools/zepp-transfer/.' }
    if ($Mode -eq 'Stop') {
        [IO.File]::WriteAllText((Join-Path $session 'stop.request'), [DateTimeOffset]::UtcNow.ToString('o'))
        Write-Output 'Stop requested. Collector will close only its own workers.'
    } else {
        Get-Content -LiteralPath (Join-Path $session 'status.json')
    }
    return
}
if (-not (Test-Path -LiteralPath $Adb)) { throw 'ADB not found.' }
$devices = & $Adb devices
if ($LASTEXITCODE -ne 0) { throw 'ADB unavailable.' }
$authorized = @($devices | Where-Object { $_ -match '^\S+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
if (-not $Serial) {
    if ($authorized.Count -ne 1) { throw 'Connect one authorized phone or specify -Serial.' }
    $Serial = $authorized[0]
}
if ($Serial -notin $authorized) { throw 'Phone offline or unauthorized.' }
if ($Serial -notmatch '^[A-Za-z0-9_.:-]+$') { throw 'Unexpected device serial syntax.' }
if ($SessionPath) { throw 'Start creates a new session; do not reuse an old capture.' }
$session = Join-Path $captureRoot (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
New-Item -ItemType Directory -Path $session -Force | Out-Null
$stopFile = Join-Path $session 'stop.request'
$utf8 = [Text.UTF8Encoding]::new($false)
$timeline = Join-Path $session 'timeline.txt'
function Mark([string]$Message) {
    [IO.File]::AppendAllText($timeline, "$([DateTimeOffset]::UtcNow.ToString('o')) $Message`r`n", $utf8)
}
function Save-Status([string]$State) {
    $data = @{ state=$State; collectorPid=$PID; utc=[DateTimeOffset]::UtcNow.ToString('o'); session=$session
        streams=@($streams | ForEach-Object { @{pid=$_.Id; alive=(-not $_.HasExited)} })
        workers=@($jobs | ForEach-Object { @{name=$_.Name; state=[string]$_.State} }) }
    [IO.File]::WriteAllText((Join-Path $session 'status.json'), ($data | ConvertTo-Json -Depth 5), $utf8)
}
$streams = @()
$jobs = @()
Mark 'COLLECTOR_START passive; UTC host timestamps; device logcat uses epoch seconds'
# Kept local so the next turn can find and stop the active collector.
[IO.File]::WriteAllText((Join-Path $captureRoot 'latest-session.txt'), $session, $utf8)
try {
    $deviceInfo = Join-Path $session 'device-info.txt'
    [IO.File]::WriteAllText($deviceInfo, "Host UTC: $([DateTimeOffset]::UtcNow.ToString('o'))`r`n", $utf8)
    $infoCommands = @(
        @('shell','getprop','ro.product.model'), @('shell','getprop','ro.build.version.release'),
        @('shell','getprop','ro.build.version.sdk'), @('shell','date','+%s'),
        @('shell','dumpsys','package','com.huami.watch.hmwatchmanager'), @('logcat','-g')
    )
    foreach ($command in $infoCommands) {
        $before = [DateTimeOffset]::UtcNow.ToString('o')
        $result = & $Adb -s $Serial @command 2>&1 | Out-String
        [IO.File]::AppendAllText($deviceInfo, "BEGIN $before adb $($command -join ' ')`r`n$result`r`nEND $([DateTimeOffset]::UtcNow.ToString('o')) exit=$LASTEXITCODE`r`n", $utf8)
    }
    $streamSpecs = @(
        @{Name='logcat-raw'; Filters=@('*:V')},
        @{Name='activity-manager-events'; Filters=@('ActivityTaskManager:V','ActivityManager:V','DocumentsUI:V','DocumentsActivity:V','DocumentsProvider:V','MediaProvider:V','*:S')},
        @{Name='bluetooth-logcat'; Filters=@('BluetoothManagerService:V','BluetoothGatt:V','BluetoothSocket:V','bt_stack:V','bt_btif:V','bt_bta:V','*:S')},
        @{Name='network-logcat'; Filters=@('ConnectivityService:V','WifiService:V','WifiClientModeImpl:V','WifiP2pService:V','NetworkMonitor:V','*:S')}
    )
    foreach ($spec in $streamSpecs) {
        # Start at the newest entry without clearing or changing any device buffer.
        $arguments = @('-s',$Serial,'logcat','-b','main','-b','system','-b','events','-b','crash','-v','epoch','-T','1') + $spec.Filters
        $process = Start-Process -FilePath $Adb -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $session ($spec.Name+'.txt')) -RedirectStandardError (Join-Path $session ($spec.Name+'-stderr.txt'))
        $streams += $process
        Mark "STREAM_START name=$($spec.Name) pid=$($process.Id)"
    }
    $worker = {
        param($AdbPath, $Device, $Directory, $StopPath, $Kind, $Interval)
        $ErrorActionPreference = 'Stop'
        $encoding = [Text.UTF8Encoding]::new($false)
        $destination = Join-Path $Directory ($Kind+'.txt')
        $commands = @(switch ($Kind) {
            'activities' { ,@('shell','dumpsys','-t','5','activity','activities') }
            'services' { ,@('shell','dumpsys','-t','5','activity','services','com.huami.watch.hmwatchmanager') }
            'bluetooth-events' { ,@('shell','dumpsys','-t','5','bluetooth_manager') }
            'network-events' {
                ,@('shell','dumpsys','-t','5','connectivity')
                ,@('shell','dumpsys','-t','5','wifi')
                ,@('shell','ss','-tun')
                ,@('shell','ip','-s','link')
            }
        })
        while (-not (Test-Path -LiteralPath $StopPath)) {
            foreach ($command in $commands) {
                if (Test-Path -LiteralPath $StopPath) { break }
                $temporary = Join-Path $Directory ($Kind+'-current.stdout')
                $errors = Join-Path $Directory ($Kind+'-current.stderr')
                $process = $null
                $start = [DateTimeOffset]::UtcNow.ToString('o')
                [IO.File]::AppendAllText($destination, "`r`nBEGIN $start adb $($command -join ' ')`r`n", $encoding)
                try {
                    $process = Start-Process -FilePath $AdbPath -ArgumentList (@('-s',$Device)+$command) -WindowStyle Hidden -PassThru -RedirectStandardOutput $temporary -RedirectStandardError $errors
                    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
                    while (-not $process.WaitForExit(250)) {
                        if ((Test-Path -LiteralPath $StopPath) -or [DateTimeOffset]::UtcNow -gt $deadline) {
                            $process.Kill()
                            $process.WaitForExit()
                            [IO.File]::AppendAllText($destination, "COLLECTOR timeout_or_stop; only own adb reader stopped`r`n", $encoding)
                            break
                        }
                    }
                    foreach ($file in @($temporary,$errors)) {
                        if (Test-Path -LiteralPath $file) { [IO.File]::AppendAllText($destination, [IO.File]::ReadAllText($file), $encoding) }
                    }
                    [IO.File]::AppendAllText($destination, "`r`nEND $([DateTimeOffset]::UtcNow.ToString('o')) exit=$($process.ExitCode)`r`n", $encoding)
                } catch {
                    [IO.File]::AppendAllText($destination, "COLLECTOR_ERROR $($_.Exception.Message)`r`n", $encoding)
                } finally {
                    if ($process -and -not $process.HasExited) { $process.Kill() }
                    if ($process) { $process.Dispose() }
                }
            }
            for ($i=0; $i -lt $Interval; $i++) {
                if (Test-Path -LiteralPath $StopPath) { break }
                Start-Sleep -Seconds 1
            }
        }
    }
    foreach ($spec in @(@('activities',2),@('services',8),@('bluetooth-events',10),@('network-events',15))) {
        $jobs += Start-Job -Name $spec[0] -ScriptBlock $worker -ArgumentList $Adb,$Serial,$session,$stopFile,$spec[0],$spec[1]
    }
    Mark 'CAPTURE_ACTIVE; no UI operations sent; wait for stop.request'
    while (-not (Test-Path -LiteralPath $stopFile)) {
        Save-Status 'collecting'
        foreach ($stream in $streams) {
            if ($stream.HasExited) { Mark "WARNING stream_exit pid=$($stream.Id) code=$($stream.ExitCode)" }
        }
        foreach ($job in $jobs) {
            if ($job.State -eq 'Failed') { Mark "WARNING worker_failed name=$($job.Name) reason=$($job.ChildJobs[0].JobStateInfo.Reason)" }
        }
        Start-Sleep -Seconds 2
    }
} catch {
    Mark "COLLECTOR_ERROR $($_.Exception.Message)"
    throw
} finally {
    [IO.File]::WriteAllText($stopFile, [DateTimeOffset]::UtcNow.ToString('o'), $utf8)
    $jobs | Wait-Job -Timeout 15 | Out-Null
    foreach ($stream in $streams) {
        if (-not $stream.HasExited) { $stream.Kill(); $stream.WaitForExit() }
        $stream.Dispose()
    }
    foreach ($job in $jobs) {
        if ($job.State -eq 'Running') { Stop-Job $job }
        $job | Receive-Job 2>&1 | Out-File -LiteralPath (Join-Path $session 'collector-worker-errors.txt') -Append -Encoding utf8
        Remove-Job $job
    }
    # Preserve raw stream, then derive a local index only after collection ends.
    $raw = Join-Path $session 'logcat-raw.txt'
    if (Test-Path -LiteralPath $raw) {
        Select-String -LiteralPath $raw -Pattern 'huami|hmwatch|zepp|music|upload|transfer|DocumentsUI|DocumentsActivity|OPEN_DOCUMENT|GET_CONTENT|audio/mpeg|Bluetooth|Gatt|RFCOMM|WifiP2p' |
            ForEach-Object { $_.Line } | Out-File -LiteralPath (Join-Path $session 'logcat-filtered.txt') -Encoding utf8
    }
    Mark 'COLLECTOR_STOPPED; raw logs retained; no transfer completion inferred'
    # Process handles/jobs are closed; final state intentionally has no live workers.
    $streams = @(); $jobs = @()
    Save-Status 'stopped'
}
