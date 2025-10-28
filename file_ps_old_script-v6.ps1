# --- Configuration ---

# Define the main directory you want to clean up
$srcDir = "C:\temp\X"

# Define the name of the subfolder for archived files
$archiveFolderName = "old"
$archiveDir = Join-Path -Path $srcDir -ChildPath $archiveFolderName

# --- FIX: Ensure the source directory path ends with a backslash for consistent path manipulation ---
if (-not $srcDir.EndsWith('\')) {
    $srcDir += '\'
}

# Define the name for the log file that will be created
$logFileName = "archive_log_$(Get-Date -Format 'yyyy-MM-dd').csv"
$logFilePath = Join-Path -Path $srcDir -ChildPath $logFileName

# --- Log Preparation ---

# Create an empty list to store data for the CSV log file
$logEntries = [System.Collections.Generic.List[PSObject]]::new()

# --- Script Execution ---

# 1. Check if the source directory exists.
if (-not (Test-Path -Path $srcDir -PathType Container)) {
    Write-Error "Source directory not found: $srcDir"
    return
}

# 2. Ensure the 'old' archive directory exists.
if (-not (Test-Path -Path $archiveDir)) {
    Write-Host "Creating archive directory at: $archiveDir"
    New-Item -Path $archiveDir -ItemType Directory | Out-Null
}

# 3. Define the cutoff date.
$thresholdDate = (Get-Date).AddYears(-1)
Write-Host "Files modified before $($thresholdDate.ToString('yyyy-MM-dd')) will be considered for archiving."
Write-Host "Folders containing files modified after this date will be skipped entirely."

# 4. Group all files by their parent directory
$allFilesGroupedByDirectory = Get-ChildItem -Path $srcDir -File -Recurse -Exclude $archiveFolderName | Group-Object -Property Directory

# Check if any files were found at all
if ($null -eq $allFilesGroupedByDirectory) {
    Write-Host "No files found in the source directory."
} else {
    # 5. Loop through each directory group
    foreach ($directoryGroup in $allFilesGroupedByDirectory) {
        $currentDirectoryPath = $directoryGroup.Name
        $filesInDirectory = $directoryGroup.Group

        # Check if ANY file in this directory is RECENT (newer than the threshold)
        $hasRecentFiles = $filesInDirectory | Where-Object { $_.LastWriteTime -ge $thresholdDate }

        if ($hasRecentFiles) {
            # If recent files exist, skip this entire directory
            Write-Host "--> Skipping directory '$currentDirectoryPath' because it contains recently modified files."
            continue # Move to the next directory group
        } else {
            # If we are here, it means ALL files in this directory are old and can be archived
            Write-Host "--> Processing directory '$currentDirectoryPath'. All files are older than one year."

            # Loop through each old file in this specific directory and archive it
            foreach ($file in $filesInDirectory) {
                try {
                    # Build the destination path while preserving the folder structure
                    $relativePath = $file.FullName.Substring($srcDir.Length)
                    $destinationPath = Join-Path -Path $archiveDir -ChildPath $relativePath
                    $destinationFolder = Split-Path -Path $destinationPath -Parent

                    if (-not (Test-Path -Path $destinationFolder)) {
                        New-Item -Path $destinationFolder -ItemType Directory -Force | Out-Null
                    }

                    Write-Host "    Archiving: $($file.FullName)"
                    Move-Item -Path $file.FullName -Destination $destinationPath -Force -ErrorAction Stop

                    # Add entry to the log
                    $logObject = [PSCustomObject]@{
                        Source      = $file.FullName
                        Destination = $destinationPath
                        MoveDate    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                        DateModified = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                    }
                    $logEntries.Add($logObject)
                }
                catch {
                    Write-Warning "Could not move file '$($file.Name)'. Error: $_"
                }
            }
        }
    }
}

# 6. Save the log to a CSV file at the end.
if ($logEntries.Count -gt 0) {
    Write-Host "Creating log file at: $logFilePath"
    $logEntries | Export-Csv -Path $logFilePath -NoTypeInformation -Encoding UTF8
} else {
    Write-Host "Script finished. No files were moved, so no log file was created."
}

Write-Host "File archiving script has finished."

# --- Rollback Function ---
function Invoke-Rollback {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogFilePath,
        
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf
    )
    
    # Check if the log file exists
    if (-not (Test-Path -Path $LogFilePath -PathType Leaf)) {
        Write-Error "Log file not found: $LogFilePath"
        return
    }
    
    # Read the log file
    try {
        $logEntries = Import-Csv -Path $LogFilePath -Encoding UTF8
        Write-Host "Found $($logEntries.Count) entries in the log file."
    } catch {
        Write-Error "Failed to read log file: $_"
        return
    }
    
    # Validate log entries
    $requiredColumns = @('Source', 'Destination', 'MoveDate', 'DateModified')
    $firstEntry = $logEntries | Select-Object -First 1
    foreach ($column in $requiredColumns) {
        if (-not ($firstEntry.PSObject.Properties.Name -contains $column)) {
            Write-Error "Log file is missing required column: $column"
            return
        }
    }
    
    # Rollback Process
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
    
    # Create rollback log
    if (-not $WhatIf -and $rollbackLog.Count -gt 0) {
        $rollbackLogPath = Join-Path -Path (Split-Path -Path $LogFilePath -Parent) -ChildPath "rollback_log_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
        Write-Host "Creating rollback log at: $rollbackLogPath"
        $rollbackLog | Export-Csv -Path $rollbackLogPath -NoTypeInformation -Encoding UTF8
    }
    
    # Summary
    Write-Host "`nRollback process completed:"
    Write-Host "  Successfully restored: $successCount files"
    Write-Host "  Errors encountered: $errorCount files"
    
    if ($WhatIf) {
        Write-Host "`nTo perform the actual rollback, run: Invoke-Rollback -LogFilePath '$LogFilePath'"
    } else {
        Write-Host "`nRollback completed successfully."
    }
}

# --- Copy Processed Directories Function ---
function Copy-ProcessedDirectories {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogFilePath,
        
        [Parameter(Mandatory=$true)]
        [string]$CopyDestinationPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf
    )
    
    # Check if the log file exists
    if (-not (Test-Path -Path $LogFilePath -PathType Leaf)) {
        Write-Error "Log file not found: $LogFilePath"
        return
    }
    
    # Read the log file
    try {
        $logEntries = Import-Csv -Path $LogFilePath -Encoding UTF8
        Write-Host "Found $($logEntries.Count) entries in the log file."
    } catch {
        Write-Error "Failed to read log file: $_"
        return
    }
    
    # Create destination directory if it doesn't exist
    if (-not (Test-Path -Path $CopyDestinationPath -PathType Container)) {
        if (-not $WhatIf) {
            try {
                New-Item -Path $CopyDestinationPath -ItemType Directory -Force | Out-Null
                Write-Host "Created destination directory: $CopyDestinationPath"
            } catch {
                Write-Error "Failed to create destination directory: $CopyDestinationPath. Error: $_"
                return
            }
        } else {
            Write-Host "Would create destination directory: $CopyDestinationPath"
        }
    }
    
    # Get all unique directories that were processed
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
    
    # Copy each processed directory
    $successCount = 0
    $errorCount = 0
    $copyLog = [System.Collections.Generic.List[PSObject]]::new()
    
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
                
                # Add entry to copy log
                $copyEntry = [PSCustomObject]@{
                    SourceDirectory = $directoryPath
                    DestinationDirectory = $destinationPath
                    CopyDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    FilesInDirectory = (Get-ChildItem -Path $directoryPath -File -Recurse).Count
                }
                $copyLog.Add($copyEntry)
            }
            $successCount++
        } catch {
            Write-Error "Failed to copy directory '$directoryPath'. Error: $_"
            $errorCount++
        }
    }
    
    # Create copy log
    if (-not $WhatIf -and $copyLog.Count -gt 0) {
        $copyLogPath = Join-Path -Path (Split-Path -Path $LogFilePath -Parent) -ChildPath "copy_log_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
        Write-Host "Creating copy log at: $copyLogPath"
        $copyLog | Export-Csv -Path $copyLogPath -NoTypeInformation -Encoding UTF8
    }
    
    # Summary
    Write-Host "`nCopy process completed:"
    Write-Host "  Successfully copied: $successCount directories"
    Write-Host "  Errors encountered: $errorCount directories"
    
    if ($WhatIf) {
        Write-Host "`nTo perform the actual copy, run: Copy-ProcessedDirectories -LogFilePath '$LogFilePath' -CopyDestinationPath '$CopyDestinationPath'"
    } else {
        Write-Host "`nCopy completed successfully."
    }
}

# --- Usage Examples ---
Write-Host "`n--- Usage Examples ---"
Write-Host "To perform a rollback (what-if mode first):"
Write-Host "  Invoke-Rollback -LogFilePath '$logFilePath' -WhatIf"
Write-Host "To perform actual rollback:"
Write-Host "  Invoke-Rollback -LogFilePath '$logFilePath'"
Write-Host "`nTo copy all processed directories (what-if mode first):"
Write-Host "  Copy-ProcessedDirectories -LogFilePath '$logFilePath' -CopyDestinationPath 'C:\Backup\ProcessedDirectories' -WhatIf"
Write-Host "To actually copy processed directories:"
Write-Host "  Copy-ProcessedDirectories -LogFilePath '$logFilePath' -CopyDestinationPath 'C:\Backup\ProcessedDirectories'"
Write-Host "`nOr use the separate rollback script:"
Write-Host "  .\rollback_script.ps1 -LogFilePath '$logFilePath' -WhatIf"
Write-Host "  .\rollback_script.ps1 -LogFilePath '$logFilePath'"
