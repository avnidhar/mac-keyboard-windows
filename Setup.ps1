[CmdletBinding(SupportsShouldProcess=$true)]
param([switch]$InstallPrerequisites, [switch]$NoStart)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Run this with Windows PowerShell 5.1 (powershell.exe), not PowerShell 7.' }
. (Join-Path $PSScriptRoot 'Common.ps1')

$localRoot = $env:LOCALAPPDATA
$managedRoot = Join-Path $localRoot 'MacKeyboardWindows'
$runtime = Join-Path $managedRoot 'runtime'
$startup = [Environment]::GetFolderPath('Startup')
$targets = Get-ManagedTargets $localRoot $startup
$null = Read-Settings (Join-Path $PSScriptRoot 'keyboard-profile.json')
$launcher = Read-Settings (Join-Path $PSScriptRoot 'launcher-settings.json')
foreach ($file in @('MacKeyboardActions.cs','ExplorerRename.cs','Open-TerminalHere.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file))) { throw "Missing source file: $file" }
}
if (-not $PSCmdlet.ShouldProcess('Current Windows user', 'Compile helpers, back up settings, install Mac keyboard profile and sign-in shortcuts')) { return }

$powerToys = Find-PowerToys
$terminal = Get-Command wt.exe -ErrorAction SilentlyContinue
if (-not $powerToys -or -not $terminal) {
    if (-not $InstallPrerequisites) { throw 'Install PowerToys and Windows Terminal, or rerun with -InstallPrerequisites.' }
    $winget = Get-Command winget.exe -ErrorAction Stop
    if (-not $powerToys) {
        & $winget.Source install --exact --id Microsoft.PowerToys --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -ne 0) { throw 'PowerToys installation did not complete. Install it manually and rerun.' }
    }
    if (-not $terminal) {
        & $winget.Source install --exact --id Microsoft.WindowsTerminal --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -ne 0) { throw 'Windows Terminal installation did not complete. Install it manually and rerun.' }
    }
    $powerToys = Find-PowerToys
    $terminal = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (-not $powerToys -or -not $terminal) { throw 'Start PowerToys once, verify the wt.exe alias is enabled, and rerun setup.' }
}
$profile = Resolve-KeyboardProfile (Join-Path $PSScriptRoot 'keyboard-profile.json') $runtime $terminal.Source (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$staging = Join-Path $managedRoot ('build-' + $stamp)
# Compile before stopping working applications or changing settings.
Build-Helpers $PSScriptRoot $staging
$backup = Join-Path $managedRoot ('backups\' + $stamp)
$backedUp = $false
try {
    Stop-KeyboardSetupProcesses
    Save-SetupBackup $targets $backup
    $backedUp = $true
    $merged = Merge-PowerToysSettings (Read-Settings $targets.General) (Read-Settings $targets.Keyboard) (Read-Settings $targets.Run) $launcher
    $null = New-Item -ItemType Directory -Path $runtime -Force
    foreach ($file in @('MacKeyboardActions.cs','ExplorerRename.cs','Open-TerminalHere.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $runtime $file) -Force
    }
    foreach ($file in @('MacKeyboardActions.exe','ExplorerRename.exe')) {
        Copy-Item -LiteralPath (Join-Path $staging $file) -Destination (Join-Path $runtime $file) -Force
    }
    Write-Settings $targets.Profile $profile
    Write-Settings $targets.Keyboard $merged.Keyboard
    Write-Settings $targets.Run $merged.Run
    Write-Settings $targets.General $merged.General
    $null = New-Item -ItemType Directory -Path $startup -Force
    $shell = New-Object -ComObject WScript.Shell
    $renameLink = $shell.CreateShortcut($targets.Startup)
    $renameLink.TargetPath = Join-Path $runtime 'ExplorerRename.exe'
    $renameLink.WorkingDirectory = $runtime
    $renameLink.WindowStyle = 7
    $renameLink.Description = 'Mac keyboard: context-aware Enter to rename in Explorer.'
    $renameLink.Save()
    $ptLink = $shell.CreateShortcut($targets.StartupPowerToys)
    $ptLink.TargetPath = $powerToys
    $ptLink.WindowStyle = 7
    $ptLink.Save()
    if (-not $NoStart) {
        Start-Process -FilePath $powerToys -WindowStyle Hidden
        Start-Process -FilePath (Join-Path $runtime 'ExplorerRename.exe') -WindowStyle Hidden
    }
} catch {
    $failure = $_
    if ($backedUp) {
        try { Stop-KeyboardSetupProcesses; Restore-SetupBackup $backup $targets }
        catch { Write-Warning "Automatic rollback failed. Keep backup $backup and run Restore-Backup.ps1." }
    }
    if (-not $NoStart) {
        if ($powerToys) { Start-Process -FilePath $powerToys -WindowStyle Hidden }
        Start-HelperFromShortcut $targets.Startup
    }
    throw $failure
}
Write-Output "Installed. Backup: $backup"
Write-Output "Runtime: $runtime"
Write-Output 'Test the shortcuts in README.md. Keep the backup to undo this installation.'
