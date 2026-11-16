<#
Read-only Android IPC inventory. Does not launch components, grant permissions,
read app data, select files or start transfers. APKs stay in ignored tools/.
First run without -PackageName to list installed packages. Select the candidate
from the device, rerun, then verify its label in base-badging.txt (must be Zepp).
#>
[CmdletBinding()]
param(
    [string]$PackageName,
    [string]$Serial,
    [string]$SdkRoot = "$env:LOCALAPPDATA/Android/sdk",
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$adb = Join-Path $SdkRoot 'platform-tools/adb.exe'
if (-not (Test-Path -LiteralPath $adb)) { throw "ADB missing: $adb" }
$devices = & $adb devices
if ($LASTEXITCODE -ne 0) { throw 'adb devices failed' }
$connected = @($devices | Where-Object { $_ -match '^\S+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
if (-not $Serial) {
    if ($connected.Count -ne 1) { throw 'Connect and authorize exactly one phone, or specify -Serial.' }
    $Serial = $connected[0]
}
if ($Serial -notin $connected) { throw 'Selected device is offline or unauthorized.' }
function Invoke-Adb {
    param([string[]]$Arguments)
    $result = & $adb -s $Serial @Arguments
    if ($LASTEXITCODE -ne 0) { throw "ADB failed: $($Arguments -join ' ')" }
    return $result
}
if (-not $PackageName) {
    Invoke-Adb -Arguments @('shell', 'pm', 'list', 'packages', '-3')
    Write-Host 'Identify a candidate from this device list; rerun with -PackageName, then verify application-label in base-badging.txt.'
    return
}
if ($PackageName -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$') { throw 'Invalid package name.' }
$aapt = Get-ChildItem -LiteralPath (Join-Path $SdkRoot 'build-tools') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Join-Path $_.FullName 'aapt2.exe' } |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $aapt) { throw 'Install Android SDK Build Tools (aapt2).' }
$project = Split-Path $PSScriptRoot -Parent
$output = Join-Path $project ('tools/zepp-intents/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $output | Out-Null
$encoding = [System.Text.UTF8Encoding]::new($false)
function Save-Output {
    param([string]$Name, [object[]]$Lines)
    [IO.File]::WriteAllLines((Join-Path $output $Name), [string[]]$Lines, $encoding)
}
Save-Output 'environment.txt' @(
    "Captured: $([DateTimeOffset]::Now.ToString('o'))",
    "Package: $PackageName",
    "Model: $(Invoke-Adb -Arguments @('shell','getprop','ro.product.model'))",
    "Android: $(Invoke-Adb -Arguments @('shell','getprop','ro.build.version.release'))",
    "API: $(Invoke-Adb -Arguments @('shell','getprop','ro.build.version.sdk'))"
)
Save-Output 'package.txt' (Invoke-Adb -Arguments @('shell','dumpsys','package',$PackageName))
$paths = @(Invoke-Adb -Arguments @('shell','pm','path',$PackageName))
if (-not $paths.Count) { throw 'Package not found for the current user.' }
Save-Output 'paths.txt' $paths
foreach ($line in $paths) {
    $remote = $line -replace '^package:', ''
    if ($remote -notmatch '^/[A-Za-z0-9_./~+=-]+\.apk$') { throw "Unexpected APK path: $remote" }
    $name = [IO.Path]::GetFileNameWithoutExtension($remote)
    $local = Join-Path $output "$name.apk"
    Invoke-Adb -Arguments @('pull', $remote, $local) | Write-Host
    $badging = & $aapt dump badging $local
    if ($LASTEXITCODE -ne 0) { throw "aapt2 badging failed: $name" }
    Save-Output "$name-badging.txt" $badging
    $tree = & $aapt dump xmltree $local --file AndroidManifest.xml
    if ($LASTEXITCODE -ne 0) { throw "aapt2 xmltree failed: $name" }
    Save-Output "$name-manifest-tree.txt" $tree
    & $Python (Join-Path $PSScriptRoot 'zepp-manifest-inventory.py') (Join-Path $output "$name-manifest-tree.txt") (Join-Path $output "$name-inventory.json")
    if ($LASTEXITCODE -ne 0) { throw "Manifest inventory failed: $name" }
}
Save-Output 'launcher-resolution.txt' (Invoke-Adb -Arguments @('shell','cmd','package','resolve-activity','--brief','-a','android.intent.action.MAIN','-c','android.intent.category.LAUNCHER','-p',$PackageName))
# Resolution only: URI is a synthetic identifier; no file is opened or granted.
$queries = @(
    @{ Name = 'send-mp3'; Args = @('-a','android.intent.action.SEND','-t','audio/mpeg') },
    @{ Name = 'send-multiple-mp3'; Args = @('-a','android.intent.action.SEND_MULTIPLE','-t','audio/mpeg') },
    @{ Name = 'view-mp3'; Args = @('-a','android.intent.action.VIEW','-c','android.intent.category.DEFAULT','-d','content://media/external/downloads/1','-t','audio/mpeg') }
)
foreach ($query in $queries) {
    Save-Output ($query.Name + '.txt') (Invoke-Adb -Arguments (@('shell','cmd','package','query-activities','--brief') + $query.Args + @('-p',$PackageName)))
}
Write-Host "Saved metadata and APKs locally: $output"
Write-Host 'Verify the application label before attributing this inventory to Zepp. No upload test was performed.'
