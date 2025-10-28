# --- Rollback Script ---
# This script restores files from the archive back to their original locations
# based on a CSV log file created by the main archiving script

param(
    [Parameter(Mandatory=$true)]
    [string]$LogFilePath,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# --- Configuration ---
$archiveFolderName = "old"

# --- Validation ---
if (-not (Test-Path -Path $LogFilePath -PathType Leaf)) {
    Write-Error "Log file not found: $LogFilePath"
    exit 1
}

# Check if the log file is a CSV
if (-not $LogFilePath.EndsWith('.csv')) {
    Write-Error "Log file must be a CSV file: $LogFilePath"
    exit 1
}

# --- Read the log file ---
try {
    $logEntries = Import-Csv -Path $LogFilePath -Encoding UTF8
    Write-Host "Found $($logEntries.Count) entries in the log file."
} catch {
    Write-Error "Failed to read log file: $_"
    exit 1
}

# --- Validate log entries ---
$requiredColumns = @('Source', 'Destination', 'MoveDate', 'DateModified')
$firstEntry = $logEntries | Select-Object -First 1
foreach ($column in $requiredColumns) {
    if (-not ($firstEntry.PSObject.Properties.Name -contains $column)) {
        Write-Error "Log file is missing required column: $column"
        exit 1
    }
}

# --- Rollback Process ---
$successCount = 0
$errorCount = 0
$rollbackLog = [System.Collections.Generic.List[PSObject]]::new()

Write-Host "Starting rollback process..."
if ($WhatIf) {
    Write-Host "*** WHAT-IF MODE: No files will actually be moved ***"
}

foreach ($entry in $logEntries) {
    $sourcePath = $entry.Source
    $destinationPath = $entry.Destination
    
    # Check if the archived file still exists
    if (-not (Test-Path -Path $destinationPath -PathType Leaf)) {
        Write-Warning "Archived file not found: $destinationPath"
        $errorCount++
        continue
    }
    
    # Check if the original location already has a file
    if (Test-Path -Path $sourcePath -PathType Leaf) {
        Write-Warning "File already exists at original location: $sourcePath"
        $errorCount++
        continue
    }
    
    # Ensure the destination directory exists
    $destinationDir = Split-Path -Path $sourcePath -Parent
    if (-not (Test-Path -Path $destinationDir -PathType Container)) {
        if (-not $WhatIf) {
            try {
                New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
                Write-Host "Created directory: $destinationDir"
            } catch {
                Write-Error "Failed to create directory: $destinationDir. Error: $_"
                $errorCount++
                continue
            }
        } else {
            Write-Host "Would create directory: $destinationDir"
        }
    }
    
    # Move the file back
    try {
        if ($WhatIf) {
            Write-Host "Would restore: $destinationPath -> $sourcePath"
        } else {
            Write-Host "Restoring: $destinationPath -> $sourcePath"
            Move-Item -Path $destinationPath -Destination $sourcePath -Force -ErrorAction Stop
            
            # Add entry to rollback log
            $rollbackEntry = [PSCustomObject]@{
                OriginalSource = $sourcePath
                ArchivedPath = $destinationPath
                RestoreDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                OriginalMoveDate = $entry.MoveDate
                OriginalDateModified = $entry.DateModified
            }
            $rollbackLog.Add($rollbackEntry)
        }
        $successCount++
    } catch {
        Write-Error "Failed to restore file '$($entry.Source)'. Error: $_"
        $errorCount++
    }
}

# --- Create rollback log ---
if (-not $WhatIf -and $rollbackLog.Count -gt 0) {
    $rollbackLogPath = Join-Path -Path (Split-Path -Path $LogFilePath -Parent) -ChildPath "rollback_log_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
    Write-Host "Creating rollback log at: $rollbackLogPath"
    $rollbackLog | Export-Csv -Path $rollbackLogPath -NoTypeInformation -Encoding UTF8
}

# --- Summary ---
Write-Host "`nRollback process completed:"
Write-Host "  Successfully restored: $successCount files"
Write-Host "  Errors encountered: $errorCount files"

if ($WhatIf) {
    Write-Host "`nTo perform the actual rollback, run the script without the -WhatIf parameter."
} else {
    Write-Host "`nRollback completed successfully."
}
