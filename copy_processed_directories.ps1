# --- Copy Processed Directories Script ---
# This script copies all directories that were processed by the archiving script
# including all their subfolders and files

param(
    [Parameter(Mandatory=$true)]
    [string]$LogFilePath,
    
    [Parameter(Mandatory=$true)]
    [string]$CopyDestinationPath,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# --- Configuration ---
$srcDir = "C:\temp\X"  # This should match the source directory from the main script

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

# --- Create destination directory ---
if (-not (Test-Path -Path $CopyDestinationPath -PathType Container)) {
    if (-not $WhatIf) {
        try {
            New-Item -Path $CopyDestinationPath -ItemType Directory -Force | Out-Null
            Write-Host "Created destination directory: $CopyDestinationPath"
        } catch {
            Write-Error "Failed to create destination directory: $CopyDestinationPath. Error: $_"
            exit 1
        }
    } else {
        Write-Host "Would create destination directory: $CopyDestinationPath"
    }
}

# --- Get all unique directories that were processed ---
$processedDirectories = @()
foreach ($entry in $logEntries) {
    $sourcePath = $entry.Source
    $directoryPath = Split-Path -Path $sourcePath -Parent
    
    # Add directory if not already in the list
    if ($processedDirectories -notcontains $directoryPath) {
        $processedDirectories += $directoryPath
    }
}

Write-Host "Found $($processedDirectories.Count) directories that were processed."

# --- Copy each processed directory ---
$successCount = 0
$errorCount = 0
$copyLog = [System.Collections.Generic.List[PSObject]]::new()

Write-Host "Starting copy process..."
if ($WhatIf) {
    Write-Host "*** WHAT-IF MODE: No directories will actually be copied ***"
}

foreach ($directoryPath in $processedDirectories) {
    try {
        # Calculate relative path from source directory
        $relativePath = $directoryPath.Substring($srcDir.Length).TrimStart('\')
        $destinationPath = Join-Path -Path $CopyDestinationPath -ChildPath $relativePath
        
        if ($WhatIf) {
            Write-Host "Would copy directory: $directoryPath -> $destinationPath"
        } else {
            Write-Host "Copying directory: $directoryPath -> $destinationPath"
            
            # Ensure destination directory exists
            if (-not (Test-Path -Path $destinationPath -PathType Container)) {
                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
            }
            
            # Copy the entire directory structure
            Copy-Item -Path $directoryPath -Destination $destinationPath -Recurse -Force -ErrorAction Stop
            
            # Count files in the directory
            $fileCount = 0
            try {
                $fileCount = (Get-ChildItem -Path $directoryPath -File -Recurse).Count
            } catch {
                $fileCount = 0
            }
            
            # Add entry to copy log
            $copyEntry = [PSCustomObject]@{
                SourceDirectory = $directoryPath
                DestinationDirectory = $destinationPath
                CopyDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                FilesInDirectory = $fileCount
            }
            $copyLog.Add($copyEntry)
        }
        $successCount++
    } catch {
        Write-Error "Failed to copy directory '$directoryPath'. Error: $_"
        $errorCount++
    }
}

# --- Create copy log ---
if (-not $WhatIf -and $copyLog.Count -gt 0) {
    $copyLogPath = Join-Path -Path (Split-Path -Path $LogFilePath -Parent) -ChildPath "copy_log_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
    Write-Host "Creating copy log at: $copyLogPath"
    $copyLog | Export-Csv -Path $copyLogPath -NoTypeInformation -Encoding UTF8
}

# --- Summary ---
Write-Host "`nCopy process completed:"
Write-Host "  Successfully copied: $successCount directories"
Write-Host "  Errors encountered: $errorCount directories"

if ($WhatIf) {
    Write-Host "`nTo perform the actual copy, run the script without the -WhatIf parameter."
} else {
    Write-Host "`nCopy completed successfully."
}
