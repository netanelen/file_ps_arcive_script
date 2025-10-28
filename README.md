# File Archiving and Rollback System

A PowerShell-based file archiving system that moves old files to an archive folder while providing a complete rollback mechanism.

## Overview

This system consists of three main components:
1. **Main Archiving Script** (`file_ps_old_script-v6.ps1`) - Archives files older than 1 year
2. **Rollback Script** (`rollback_script.ps1`) - Restores files from archive back to original locations
3. **Copy Processed Directories Script** (`copy_processed_directories.ps1`) - Copies all processed directories including subfolders

## Features

### Archiving Features
- ✅ Archives files older than 1 year to an `old` subfolder
- ✅ Skips entire directories if ANY file was modified within the last year
- ✅ Preserves folder structure in the archive
- ✅ Creates detailed CSV log with file information
- ✅ Includes Date Modified column for manual verification

### Rollback Features
- ✅ Complete rollback mechanism based on CSV log files
- ✅ What-if mode to preview rollback operations
- ✅ Safety checks to prevent data loss
- ✅ Detailed rollback logging
- ✅ Error handling and reporting

### Copy Features
- ✅ Copy all processed directories including subfolders
- ✅ Preserve complete directory structure
- ✅ What-if mode to preview copy operations
- ✅ Detailed copy logging with file counts
- ✅ Error handling and reporting

## Configuration

### Main Script Configuration
Edit the following variables in `file_ps_old_script-v6.ps1`:

```powershell
# Define the main directory you want to clean up
$srcDir = "C:\temp\X"

# Define the name of the subfolder for archived files
$archiveFolderName = "old"
```

## Usage

### 1. Running the Archiving Script

```powershell
# Run the main archiving script
.\file_ps_old_script-v6.ps1
```

**What it does:**
- Scans the source directory for files older than 1 year
- Skips directories containing any recently modified files
- Moves old files to the `old` subfolder while preserving structure
- Creates a CSV log file with details of all moved files

**Output:**
- Creates `archive_log_YYYY-MM-DD.csv` in the source directory
- Log includes: Source, Destination, MoveDate, DateModified

### 2. Rollback Operations

#### Option A: Using the Built-in Function

```powershell
# Load the script first
. .\file_ps_old_script-v6.ps1

# Preview what would be restored (recommended first)
Invoke-Rollback -LogFilePath "C:\temp\X\archive_log_2024-01-15.csv" -WhatIf

# Actually perform the rollback
Invoke-Rollback -LogFilePath "C:\temp\X\archive_log_2024-01-15.csv"
```

#### Option B: Using the Separate Rollback Script

```powershell
# Preview what would be restored (recommended first)
.\rollback_script.ps1 -LogFilePath "C:\temp\X\archive_log_2024-01-15.csv" -WhatIf

# Actually perform the rollback
.\rollback_script.ps1 -LogFilePath "C:\temp\X\archive_log_2024-01-15.csv"
```

### 3. Copy Processed Directories

#### Option A: Using the Built-in Function

```powershell
# Load the script first
. .\file_ps_old_script-v6.ps1

# Preview what would be copied (recommended first)
Copy-ProcessedDirectories -LogFilePath "C:\temp\X\archive_log_2024-01-15.csv" -CopyDestinationPath "C:\Backup\ProcessedDirectories" -WhatIf

# Actually copy the directories
Copy-ProcessedDirectories -LogFilePath "C:\temp\X\archive_log_2024-01-15.csv" -CopyDestinationPath "C:\Backup\ProcessedDirectories"
```

#### Option B: Using the Separate Copy Script

```powershell
# Preview what would be copied (recommended first)
.\copy_processed_directories.ps1 -LogFilePath "C:\temp\X\archive_log_2024-01-15.csv" -CopyDestinationPath "C:\Backup\ProcessedDirectories" -WhatIf

# Actually copy the directories
.\copy_processed_directories.ps1 -LogFilePath "C:\temp\X\archive_log_2024-01-15.csv" -CopyDestinationPath "C:\Backup\ProcessedDirectories"
```

## File Structure

```
YourSourceDirectory/
├── file1.txt                    # Files older than 1 year
├── subfolder1/
│   ├── file2.txt               # Files older than 1 year
│   └── recent_file.txt         # Recent file (keeps entire folder)
├── subfolder2/
│   └── old_file.txt            # Files older than 1 year
└── old/                        # Archive folder (created by script)
    ├── file1.txt
    ├── subfolder1/
    │   └── file2.txt
    └── subfolder2/
        └── old_file.txt
```

## Log Files

### Archive Log (`archive_log_YYYY-MM-DD.csv`)
Contains information about each file that was moved:
- **Source**: Original file path
- **Destination**: Archive file path
- **MoveDate**: When the file was moved
- **DateModified**: Original file modification date

### Rollback Log (`rollback_log_YYYY-MM-DD_HH-mm-ss.csv`)
Created when performing rollback operations:
- **OriginalSource**: Where the file was restored to
- **ArchivedPath**: Where the file was restored from
- **RestoreDate**: When the rollback occurred
- **OriginalMoveDate**: When the file was originally archived
- **OriginalDateModified**: Original file modification date

### Copy Log (`copy_log_YYYY-MM-DD_HH-mm-ss.csv`)
Created when copying processed directories:
- **SourceDirectory**: Original directory path
- **DestinationDirectory**: Where the directory was copied to
- **CopyDate**: When the copy operation occurred
- **FilesInDirectory**: Number of files in the copied directory

## Safety Features

### Archiving Safety
- **Directory Skip Logic**: If ANY file in a directory was modified within the last year, the entire directory is skipped
- **Structure Preservation**: Folder structure is maintained in the archive
- **Detailed Logging**: Every operation is logged for audit purposes

### Rollback Safety
- **What-If Mode**: Preview operations before executing
- **File Existence Checks**: Verifies archived files exist before attempting restore
- **Conflict Prevention**: Won't overwrite existing files at original locations
- **Directory Recreation**: Automatically recreates missing directories
- **Comprehensive Logging**: Tracks all rollback operations

## Error Handling

The scripts include comprehensive error handling:
- Missing directories are created automatically
- File operation errors are logged and reported
- Scripts continue processing even if individual files fail
- Detailed error messages help with troubleshooting

## Integration with Job Control

The rollback functionality can be easily integrated with job control systems:

```powershell
# Example job control integration
$logFile = "C:\temp\X\archive_log_2024-01-15.csv"

# Check if rollback is needed (customize condition as needed)
if ($rollbackNeeded) {
    .\rollback_script.ps1 -LogFilePath $logFile
}
```

## Requirements

- PowerShell 5.1 or later
- Appropriate file system permissions for source and destination directories
- Sufficient disk space for archive operations

## Troubleshooting

### Common Issues

1. **"Source directory not found"**
   - Verify the `$srcDir` path is correct
   - Ensure the directory exists and is accessible

2. **"Access denied" errors**
   - Run PowerShell as Administrator
   - Check file/folder permissions

3. **"Log file is missing required column"**
   - Ensure you're using a log file created by this version of the script
   - Check that the CSV file wasn't corrupted

4. **Rollback fails for some files**
   - Check if archived files still exist
   - Verify no files exist at original locations
   - Review error messages for specific issues

### Log Analysis

Use the CSV log files to:
- Verify only old files were processed
- Track file movement history
- Plan rollback operations
- Audit system behavior

## Version History

- **v6**: Added Date Modified column and comprehensive rollback mechanism
- Previous versions: Basic archiving functionality

## Support

For issues or questions:
1. Check the log files for detailed error information
2. Use What-If mode to preview operations
3. Verify file permissions and paths
4. Review the troubleshooting section above
# file_ps_arcive_script
