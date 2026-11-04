[CmdletBinding(SupportsShouldProcess=$true)]
param([Parameter(Mandatory=$true)][string]$BackupPath, [switch]$NoStart)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$backup = (Resolve-Path -LiteralPath $BackupPath).Path
$backupRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'MacKeyboardWindows\backups')) + [IO.Path]::DirectorySeparatorChar
if (-not $backup.StartsWith($backupRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Choose a backup made by Setup.ps1 under LOCALAPPDATA\MacKeyboardWindows\backups.' }
$targets = Get-ManagedTargets $env:LOCALAPPDATA ([Environment]::GetFolderPath('Startup'))
$powerToys = Find-PowerToys
if (-not $PSCmdlet.ShouldProcess($backup, 'Restore the saved settings, runtime files, and sign-in shortcuts')) { return }
Stop-KeyboardSetupProcesses
Restore-SetupBackup $backup $targets
if (-not $NoStart) {
    if ($powerToys) { Start-Process -FilePath $powerToys -WindowStyle Hidden }
    Start-HelperFromShortcut $targets.Startup
}
Write-Output 'Previous settings and sign-in shortcuts restored.'
