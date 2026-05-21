# Parse VS Code shared process logs for extension install/update history
param(
    [string[]]$LogPath,
    [string]$CheckExtension,  # e.g. "nrwl.angular-console"
    [string]$CheckVersion     # e.g. "18.95.0"
)

# Default paths for VS Code-based editors
$editorPaths = @{
    "VS Code"          = "$env:APPDATA\Code\logs"
    "VS Code Insiders" = "$env:APPDATA\Code - Insiders\logs"
    "Cursor"           = "$env:APPDATA\Cursor\logs"
    "VSCodium"         = "$env:APPDATA\VSCodium\logs"
    "Windsurf"         = "$env:APPDATA\Windsurf\logs"
}

if ($LogPath) {
    # Custom path provided - treat as single "Custom" source
    $editorPaths = @{ "Custom" = $LogPath }
}

function Get-AppName($filePath) {
    foreach ($entry in $editorPaths.GetEnumerator()) {
        if ($filePath.StartsWith($entry.Value, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $entry.Key
        }
    }
    return "Unknown"
}

# Find all sharedprocess.log files grouped by app
$logFiles = @()
$activeEditors = @()
foreach ($entry in $editorPaths.GetEnumerator()) {
    if (Test-Path $entry.Value) {
        $activeEditors += $entry.Key
        $files = if (Test-Path $entry.Value -PathType Leaf) {
            @(Get-Item $entry.Value)
        } else {
            Get-ChildItem -Path $entry.Value -Recurse -Filter "sharedprocess.log" -ErrorAction SilentlyContinue
        }
        $logFiles += $files
    }
}
$logFiles = $logFiles | Sort-Object LastWriteTime

if (-not $logFiles) {
    Write-Host "No sharedprocess.log files found in $LogPath" -ForegroundColor Red
    exit 1
}

Write-Host "Scanning $($logFiles.Count) log file(s) from: $($activeEditors -join ', ')...`n"

$installs = @()
$removals = @()

foreach ($logFile in $logFiles) {
    $app = Get-AppName $logFile.FullName
    $lines = Get-Content $logFile.FullName -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        # Match "Extension installed successfully: <id>"
        if ($line -match '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+) \[info\] Extension installed successfully: (\S+)') {
            $timestamp = $Matches[1]
            $extId = $Matches[2]
            $installs += [PSCustomObject]@{
                Timestamp = $timestamp
                Extension = $extId
                Action    = "Installed"
                Version   = ""
                App       = $app
            }
        }
        # Match "Extracted extension to .../<ext-id>-<version>: <ext-id>"
        elseif ($line -match '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+) \[info\] Extracted extension to .+/([^/]+): (\S+)') {
            $timestamp = $Matches[1]
            $folderName = [Uri]::UnescapeDataString($Matches[2])
            $extId = $Matches[3]
            $version = $folderName -replace "^$([regex]::Escape($extId))-", ""
            $installs += [PSCustomObject]@{
                Timestamp = $timestamp
                Extension = $extId
                Action    = "Extracted"
                Version   = $version
                App       = $app
            }
        }
        # Match "Marked extension as removed <ext-id>-<version>"
        elseif ($line -match '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+) \[info\] Marked extension as removed (\S+)') {
            $timestamp = $Matches[1]
            $folderName = $Matches[2]
            if ($folderName -match '^(.+?)-(\d+\..+)$') {
                $extId = $Matches[1]
                $version = $Matches[2]
            } else {
                $extId = $folderName
                $version = "?"
            }
            $removals += [PSCustomObject]@{
                Timestamp = $timestamp
                Extension = $extId
                Action    = "Removed"
                Version   = $version
                App       = $app
            }
        }
    }
}

# Combine and deduplicate - show installed versions grouped by extension
$allEvents = ($installs + $removals) | Sort-Object Timestamp

# If checking for a specific extension version
if ($CheckExtension -and $CheckVersion) {
    $checkResult = $allEvents | Where-Object { $_.Extension -eq $CheckExtension -and $_.Version -match "^$([regex]::Escape($CheckVersion))" }
}

# Group by app, then by extension
$groupedByApp = $allEvents | Group-Object App
foreach ($appGroup in $groupedByApp | Sort-Object Name) {
    Write-Host "=== $($appGroup.Name) ===" -ForegroundColor Cyan
    Write-Host ""

    $grouped = $appGroup.Group | Group-Object Extension
    foreach ($group in $grouped | Sort-Object Name) {
        $ext = $group.Name
        $events = $group.Group | Sort-Object Timestamp
        
        $versions = $events | Where-Object { $_.Version -and $_.Version -ne "" } | 
            Sort-Object Action, Version -Unique |
            Select-Object Timestamp, Action, Version
        
        if ($versions) {
            # Sort logically: removals by version ascending first, then installs by version ascending
            $removals_sorted = $versions | Where-Object { $_.Action -eq "Removed" } | Sort-Object { [version]($_.Version -replace '-.*$','') }
            $installs_sorted = $versions | Where-Object { $_.Action -ne "Removed" } | Sort-Object { [version]($_.Version -replace '-.*$','') }
            $sorted = @($removals_sorted) + @($installs_sorted)

            Write-Host "$ext" -ForegroundColor Yellow
            foreach ($v in $sorted) {
                $icon = if ($v.Action -eq "Removed") { "  [-]" } else { "  [+]" }
                $color = if ($v.Action -eq "Removed") { "DarkGray" } else { "Green" }
                Write-Host "$icon $($v.Version)  ($($v.Timestamp))" -ForegroundColor $color
            }
            Write-Host ""
        }
    }
}

Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Editors scanned: $($activeEditors -join ', ')"
$totalGrouped = ($installs + $removals) | Group-Object Extension
Write-Host "Extensions updated: $($totalGrouped.Count)"
Write-Host "Total install events: $($installs.Count)"
Write-Host "Total removal events: $($removals.Count)"

# Print version check result at the end
if ($CheckExtension -and $CheckVersion) {
    Write-Host ""
    if ($checkResult) {
        Write-Host "WARNING: $CheckExtension@$CheckVersion WAS installed on this machine!" -ForegroundColor Red
        Write-Host ""
        foreach ($f in $checkResult) {
            $icon = if ($f.Action -eq "Removed") { "[-]" } else { "[+]" }
            Write-Host "  $icon $($f.Action) at $($f.Timestamp)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "OK: $CheckExtension@$CheckVersion was NEVER installed (not found in any logs)" -ForegroundColor Green
        $related = $allEvents | Where-Object { $_.Extension -eq $CheckExtension -and $_.Version }
        if ($related) {
            Write-Host "  Versions seen in logs:" -ForegroundColor Cyan
            $related | Select-Object Version, Action -Unique | ForEach-Object {
                Write-Host "    $($_.Action): $($_.Version)"
            }
        }
    }
}
