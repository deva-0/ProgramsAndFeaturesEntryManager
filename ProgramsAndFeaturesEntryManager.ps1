#requires -Version 5.1
<#
.SYNOPSIS
    GUI manager for entries displayed by Control Panel > Programs and Features.

.DESCRIPTION
    Removes selected uninstall registry keys after exporting each key to a .reg
    backup. This hides/removes the listing only; it does not uninstall software
    or delete application files.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    if (-not $PSCommandPath) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            'Save the script to a .ps1 file before running it.',
            'Programs and Features Entry Manager',
            'OK',
            'Error'
        ) | Out-Null
        exit 1
    }

    $hostExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    try {
        Start-Process -FilePath $hostExe -Verb RunAs -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ('"{0}"' -f $PSCommandPath)
        ) | Out-Null
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "Administrator access was not granted.`r`n`r`n$($_.Exception.Message)",
            'Programs and Features Entry Manager',
            'OK',
            'Error'
        ) | Out-Null
    }
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:AllEntries = @()
$script:BackupRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ProgramsAndFeaturesEntryBackups'

function ConvertTo-SafeFileName {
    param([Parameter(Mandatory)][string]$Name)

    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $safe = -join ($Name.ToCharArray() | ForEach-Object {
        if ($invalid -contains $_) { '_' } else { $_ }
    })
    $safe = $safe.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'UnnamedEntry' }
    if ($safe.Length -gt 80) { $safe = $safe.Substring(0, 80) }
    return $safe
}

function Get-RegistryValueOrDefault {
    param(
        [Parameter(Mandatory)]$RegistryItem,
        [Parameter(Mandatory)][string]$Name,
        $Default = ''
    )

    $property = $RegistryItem.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Get-ProgramsAndFeaturesEntries {
    $locations = @(
        [pscustomobject]@{
            ProviderPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
            NativePath   = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
            Scope        = 'All users'
            Architecture = '64-bit'
        },
        [pscustomobject]@{
            ProviderPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
            NativePath   = 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
            Scope        = 'All users'
            Architecture = '32-bit'
        },
        [pscustomobject]@{
            ProviderPath = 'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
            NativePath   = 'HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
            Scope        = 'Current user'
            Architecture = 'User'
        }
    )

    $results = foreach ($location in $locations) {
        if (-not (Test-Path -LiteralPath $location.ProviderPath)) { continue }

        foreach ($key in (Get-ChildItem -LiteralPath $location.ProviderPath -ErrorAction SilentlyContinue)) {
            try {
                $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                $displayName = [string](Get-RegistryValueOrDefault -RegistryItem $item -Name 'DisplayName')
                if ([string]::IsNullOrWhiteSpace($displayName)) { continue }

                [pscustomobject]@{
                    Name           = $displayName
                    Publisher      = [string](Get-RegistryValueOrDefault -RegistryItem $item -Name 'Publisher')
                    Version        = [string](Get-RegistryValueOrDefault -RegistryItem $item -Name 'DisplayVersion')
                    Installed      = [string](Get-RegistryValueOrDefault -RegistryItem $item -Name 'InstallDate')
                    Scope          = $location.Scope
                    Architecture   = $location.Architecture
                    SystemComponent = ([int](Get-RegistryValueOrDefault -RegistryItem $item -Name 'SystemComponent' -Default 0) -eq 1)
                    RegistryPath   = $key.PSPath
                    NativePath     = '{0}\{1}' -f $location.NativePath, $key.PSChildName
                    KeyName        = $key.PSChildName
                    UninstallString = [string](Get-RegistryValueOrDefault -RegistryItem $item -Name 'UninstallString')
                }
            }
            catch {
                # A key may disappear or become inaccessible while refreshing.
                continue
            }
        }
    }

    return @($results | Sort-Object Name, Version, Scope, Architecture)
}

function Export-RegistryEntry {
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)][string]$DestinationFolder
    )

    if (-not (Test-Path -LiteralPath $DestinationFolder)) {
        New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
    }

    $safeName = ConvertTo-SafeFileName -Name $Entry.Name
    $suffix = ConvertTo-SafeFileName -Name $Entry.KeyName
    if ($suffix.Length -gt 40) { $suffix = $suffix.Substring(0, 40) }
    $sourceTag = ConvertTo-SafeFileName -Name ("$($Entry.Scope)_$($Entry.Architecture)")
    $destination = Join-Path $DestinationFolder ("{0}__{1}__{2}.reg" -f $safeName, $sourceTag, $suffix)

    $process = Start-Process -FilePath 'reg.exe' -ArgumentList @(
        'export',
        ('"{0}"' -f $Entry.NativePath),
        ('"{0}"' -f $destination),
        '/y'
    ) -Wait -PassThru -WindowStyle Hidden

    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $destination)) {
        throw "Registry export failed for '$($Entry.Name)' (reg.exe exit code $($process.ExitCode))."
    }
    return $destination
}

$form = [System.Windows.Forms.Form]::new()
$form.Text = 'Programs and Features Entry Manager'
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = [Drawing.Size]::new(900, 560)
$form.Size = [Drawing.Size]::new(1120, 680)
$form.Font = [Drawing.Font]::new('Segoe UI', 9)
$form.AutoScaleMode = 'Dpi'

$header = [System.Windows.Forms.Label]::new()
$header.Text = 'Remove Programs and Features entries'
$header.Font = [Drawing.Font]::new('Segoe UI Semibold', 16)
$header.AutoSize = $true
$header.Location = [Drawing.Point]::new(16, 14)
$form.Controls.Add($header)

$warning = [System.Windows.Forms.Label]::new()
$warning.Text = 'This removes only the registry listing. It does not uninstall the application or delete its files.'
$warning.AutoSize = $true
$warning.ForeColor = [Drawing.Color]::DarkRed
$warning.Location = [Drawing.Point]::new(18, 48)
$form.Controls.Add($warning)

$searchLabel = [System.Windows.Forms.Label]::new()
$searchLabel.Text = 'Search:'
$searchLabel.AutoSize = $true
$searchLabel.Location = [Drawing.Point]::new(18, 82)
$form.Controls.Add($searchLabel)

$searchBox = [System.Windows.Forms.TextBox]::new()
$searchBox.Location = [Drawing.Point]::new(72, 78)
$searchBox.Width = 360
$searchBox.Anchor = 'Top,Left'
$form.Controls.Add($searchBox)

$showSystem = [System.Windows.Forms.CheckBox]::new()
$showSystem.Text = 'Show system components'
$showSystem.AutoSize = $true
$showSystem.Location = [Drawing.Point]::new(450, 80)
$form.Controls.Add($showSystem)

$refreshButton = [System.Windows.Forms.Button]::new()
$refreshButton.Text = 'Refresh'
$refreshButton.Size = [Drawing.Size]::new(90, 28)
$refreshButton.Location = [Drawing.Point]::new(660, 76)
$form.Controls.Add($refreshButton)

$grid = [System.Windows.Forms.DataGridView]::new()
$grid.Location = [Drawing.Point]::new(16, 116)
$grid.Size = [Drawing.Size]::new(1070, 445)
$grid.Anchor = 'Top,Bottom,Left,Right'
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false
$grid.AutoGenerateColumns = $false
$grid.MultiSelect = $true
$grid.SelectionMode = 'FullRowSelect'
$grid.RowHeadersVisible = $false
$grid.BackgroundColor = [Drawing.Color]::White
$grid.AutoSizeRowsMode = 'None'
$grid.ColumnHeadersHeightSizeMode = 'AutoSize'
$form.Controls.Add($grid)

$columns = @(
    @{ Name = 'Name';         Header = 'Name';         Width = 290 },
    @{ Name = 'Publisher';    Header = 'Publisher';    Width = 190 },
    @{ Name = 'Version';      Header = 'Version';      Width = 110 },
    @{ Name = 'Installed';    Header = 'Installed';    Width = 90 },
    @{ Name = 'Scope';        Header = 'Scope';        Width = 95 },
    @{ Name = 'Architecture'; Header = 'Type';         Width = 75 },
    @{ Name = 'KeyName';      Header = 'Registry key'; Width = 210 }
)
foreach ($definition in $columns) {
    $column = [System.Windows.Forms.DataGridViewTextBoxColumn]::new()
    $column.Name = $definition.Name
    $column.DataPropertyName = $definition.Name
    $column.HeaderText = $definition.Header
    $column.Width = $definition.Width
    if ($definition.Name -eq 'Name') { $column.AutoSizeMode = 'Fill' }
    $grid.Columns.Add($column) | Out-Null
}

$statusLabel = [System.Windows.Forms.Label]::new()
$statusLabel.Text = 'Loading entries...'
$statusLabel.AutoSize = $true
$statusLabel.Location = [Drawing.Point]::new(18, 578)
$statusLabel.Anchor = 'Bottom,Left'
$form.Controls.Add($statusLabel)

$openBackupsButton = [System.Windows.Forms.Button]::new()
$openBackupsButton.Text = 'Open backups'
$openBackupsButton.Size = [Drawing.Size]::new(120, 32)
$openBackupsButton.Location = [Drawing.Point]::new(820, 572)
$openBackupsButton.Anchor = 'Bottom,Right'
$form.Controls.Add($openBackupsButton)

$removeButton = [System.Windows.Forms.Button]::new()
$removeButton.Text = 'Back up and remove'
$removeButton.Size = [Drawing.Size]::new(145, 32)
$removeButton.Location = [Drawing.Point]::new(950, 572)
$removeButton.Anchor = 'Bottom,Right'
$removeButton.BackColor = [Drawing.Color]::FromArgb(190, 45, 45)
$removeButton.ForeColor = [Drawing.Color]::White
$removeButton.FlatStyle = 'Flat'
$form.Controls.Add($removeButton)

function Update-Grid {
    $query = $searchBox.Text.Trim()
    $filtered = @($script:AllEntries | Where-Object {
        ($showSystem.Checked -or -not $_.SystemComponent) -and
        ([string]::IsNullOrWhiteSpace($query) -or
            $_.Name -like "*$query*" -or
            $_.Publisher -like "*$query*" -or
            $_.Version -like "*$query*" -or
            $_.KeyName -like "*$query*")
    })

    $grid.DataSource = $null
    $grid.DataSource = [System.Collections.ArrayList]::new($filtered)
    $statusLabel.Text = '{0} entries shown ({1} total)' -f $filtered.Count, $script:AllEntries.Count
}

function Refresh-Entries {
    $form.UseWaitCursor = $true
    $refreshButton.Enabled = $false
    $removeButton.Enabled = $false
    try {
        $script:AllEntries = @(Get-ProgramsAndFeaturesEntries)
        Update-Grid
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Unable to read the uninstall registry entries.`r`n`r`n$($_.Exception.Message)",
            $form.Text,
            'OK',
            'Error'
        ) | Out-Null
    }
    finally {
        $form.UseWaitCursor = $false
        $refreshButton.Enabled = $true
        $removeButton.Enabled = $true
    }
}

$searchBox.Add_TextChanged({ Update-Grid })
$showSystem.Add_CheckedChanged({ Update-Grid })
$refreshButton.Add_Click({ Refresh-Entries })

$openBackupsButton.Add_Click({
    if (-not (Test-Path -LiteralPath $script:BackupRoot)) {
        New-Item -ItemType Directory -Path $script:BackupRoot -Force | Out-Null
    }
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $script:BackupRoot) | Out-Null
})

$removeButton.Add_Click({
    $selected = @($grid.SelectedRows | ForEach-Object { $_.DataBoundItem })
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            'Select one or more entries first.',
            $form.Text,
            'OK',
            'Information'
        ) | Out-Null
        return
    }

    $previewNames = @($selected | Select-Object -First 8 | ForEach-Object { [string]$_.Name })
    $preview = ($previewNames -join "`r`n  - ")
    if ($selected.Count -gt 8) { $preview += "`r`n  - ...and $($selected.Count - 8) more" }
    $message = @"
Remove $($selected.Count) selected Programs and Features entry/entries?

  - $preview

Each registry key will be exported first. This does NOT uninstall software.
"@
    $answer = [System.Windows.Forms.MessageBox]::Show(
        $message,
        'Confirm registry entry removal',
        'YesNo',
        'Warning',
        'Button2'
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $backupFolder = Join-Path $script:BackupRoot $timestamp
    $removed = [System.Collections.Generic.List[string]]::new()
    $failures = [System.Collections.Generic.List[string]]::new()

    $form.UseWaitCursor = $true
    $removeButton.Enabled = $false
    try {
        foreach ($entry in $selected) {
            try {
                Export-RegistryEntry -Entry $entry -DestinationFolder $backupFolder | Out-Null
                Remove-Item -LiteralPath $entry.RegistryPath -Recurse -Force -ErrorAction Stop
                $removed.Add($entry.Name)
            }
            catch {
                $failures.Add("$($entry.Name): $($_.Exception.Message)")
            }
        }
    }
    finally {
        $form.UseWaitCursor = $false
        $removeButton.Enabled = $true
        Refresh-Entries
    }

    $summary = "Removed: $($removed.Count)`r`nFailed: $($failures.Count)"
    if ($removed.Count -gt 0) { $summary += "`r`n`r`nBackups: $backupFolder" }
    if ($failures.Count -gt 0) { $summary += "`r`n`r`nErrors:`r`n" + ($failures -join "`r`n") }
    [System.Windows.Forms.MessageBox]::Show(
        $summary,
        $form.Text,
        'OK',
        $(if ($failures.Count -gt 0) { 'Warning' } else { 'Information' })
    ) | Out-Null
})

$form.Add_Shown({ Refresh-Entries })
[void]$form.ShowDialog()
