# Programs and Features Entry Manager

A PowerShell GUI for removing unwanted entries from:

`Control Panel > Programs > Programs and Features`

The application reads Windows uninstall registry locations, displays their entries in a searchable table, and lets you back up and remove selected listings.

> \[!WARNING]
> This tool removes only the registry entry displayed by Programs and Features. It does \*\*not\*\* uninstall software, stop services, remove drivers, or delete application files.

## Requirements

* Windows 11
* Windows PowerShell 5.1 or PowerShell 7
* Administrator access
* The included `ProgramsAndFeaturesEntryManager.ps1` script

No third-party modules are required.

## Features

* Graphical Windows Forms interface
* Search by program name, publisher, version, or registry-key name
* Multi-select removal
* Reads entries from:

  * 64-bit machine-wide uninstall registry
  * 32-bit machine-wide uninstall registry
  * Current-user uninstall registry
* Hides system components by default
* Exports every selected registry key before attempting removal
* Stops removal of an individual entry if its backup fails
* Refreshes the list after changes
* Provides quick access to the backup directory

## Running the application

Place `README.md` and `ProgramsAndFeaturesEntryManager.ps1` in the same folder. Open PowerShell in that folder and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\\ProgramsAndFeaturesEntryManager.ps1
```

The script requests administrator elevation automatically. Approve the Windows User Account Control prompt to continue.

If you use PowerShell 7, you can instead run:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\\ProgramsAndFeaturesEntryManager.ps1
```

The `-ExecutionPolicy Bypass` setting applies only to this PowerShell process; it does not permanently change the system execution policy.

## Removing an entry

1. Start the application and approve elevation.
2. Use the search field to locate the unwanted listing.
3. Select one or more rows. Hold `Ctrl` to select separate rows or `Shift` to select a range.
4. Select **Back up and remove**.
5. Carefully review the confirmation dialog.
6. Select **Yes** to export and remove the selected registry entries.

Only select an entry when you are certain it is obsolete. If the application is still installed, use its normal uninstaller whenever possible.

## Backups

Backups are saved as `.reg` files under:

```text
%USERPROFILE%\\Documents\\ProgramsAndFeaturesEntryBackups\\yyyy-MM-dd\_HH-mm-ss\\
```

Each removal operation receives its own timestamped folder. Select **Open backups** in the application to open the main backup directory.

## Restoring a removed entry

To restore an entry:

1. Open the appropriate timestamped backup folder.
2. Identify the `.reg` file for the removed entry.
3. Double-click the file, or right-click it and select **Merge**.
4. Approve the Registry Editor and UAC prompts.
5. Reopen Programs and Features or select **Refresh** in the application.

You can also import a backup from an elevated Command Prompt:

```cmd
reg.exe import "C:\\path\\to\\backup.reg"
```

Registry imports are not an uninstaller and do not restore deleted application files.

## System components

Entries whose uninstall key contains `SystemComponent=1` are hidden by default. Enable **Show system components** only when necessary. Removing system-component entries can hide Windows components, drivers, runtimes, or supporting packages from management tools.

## Troubleshooting

### The script opens in a text editor

Run it from PowerShell using the command shown in [Running the application](#running-the-application). Double-clicking `.ps1` files does not normally execute them.

### Windows says script execution is disabled

Use the provided command with `-ExecutionPolicy Bypass`. Make sure the complete command is entered on one line.

### An entry cannot be removed

* Confirm that administrator elevation was approved.
* Check whether security software is protecting the registry key.
* Select **Refresh** in case another process already changed the entry.
* Review the error shown at the end of the operation.

### An entry returns later

Windows Installer, an application updater, repair task, or device-management system may recreate its uninstall registration. Uninstall or repair the underlying software instead of repeatedly deleting its listing.

### The program remains installed

This is expected. The application removes only the Programs and Features listing. Use the program's official uninstaller, its installer package, Windows Settings, or your organization's software-management system to remove the actual software.

## Registry locations used

```text
HKEY\_LOCAL\_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall
HKEY\_LOCAL\_MACHINE\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall
HKEY\_CURRENT\_USER\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall
```

## Safety notes

* Keep the generated `.reg` backups until you have confirmed the result.
* Prefer the software's normal uninstall process when it is available.
* Do not remove entries merely because you do not recognize their names.
* Exercise particular caution with drivers, security software, runtimes, and Windows components.
* Registry changes affect Programs and Features immediately, although the window may need to be refreshed or reopened.

