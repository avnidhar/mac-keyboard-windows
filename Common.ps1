Set-StrictMode -Version 2

function Set-Field($Object, [string]$Name, $Value) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}
function Get-Field($Object, [string]$Name, $Default = $null) {
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}
function Read-Settings([string]$Path, [string]$DefaultJson = '{}') {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    return $DefaultJson | ConvertFrom-Json
}
function Write-Settings([string]$Path, $Value) {
    $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($Path)) -Force
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
}
function Resolve-KeyboardProfile([string]$ProfilePath, [string]$RuntimeDirectory, [string]$TerminalPath, [string]$PowerShellPath) {
    $profile = Read-Settings $ProfilePath
    foreach ($entry in $profile.remapShortcuts.global) {
        if ($entry.operationType -ne 1) { continue }
        switch ($entry.runProgramFilePath) {
            '{{TERMINAL}}' { $entry.runProgramFilePath = $TerminalPath }
            '{{POWERSHELL}}' {
                $entry.runProgramFilePath = $PowerShellPath
                $entry.runProgramArgs = '-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $RuntimeDirectory 'Open-TerminalHere.ps1') + '"'
            }
            '{{ACTIONS}}' { $entry.runProgramFilePath = Join-Path $RuntimeDirectory 'MacKeyboardActions.exe' }
            default { throw "Unknown program target in profile: $($entry.originalKeys)" }
        }
    }
    if (($profile | ConvertTo-Json -Depth 100 -Compress) -match '\{\{') { throw 'Unresolved profile placeholder.' }
    return $profile
}
function Merge-PowerToysSettings($General, $Keyboard, $Run, $Launcher) {
    $enabled = Get-Field $General 'enabled' ([pscustomobject]@{})
    Set-Field $enabled 'Keyboard Manager' $true
    Set-Field $enabled 'PowerToys Run' $true
    Set-Field $General 'enabled' $enabled
    Set-Field $General 'startup' $true
    $properties = Get-Field $Keyboard 'properties' ([pscustomobject]@{})
    Set-Field $properties 'activeConfiguration' ([pscustomobject]@{value='default'})
    $configurations = Get-Field $properties 'keyboardConfigurations' ([pscustomobject]@{value=@()})
    $names = @(Get-Field $configurations 'value' @())
    if ('default' -notin $names) { $names += 'default' }
    Set-Field $configurations 'value' $names
    Set-Field $properties 'keyboardConfigurations' $configurations
    Set-Field $Keyboard 'properties' $properties
    if ($null -eq (Get-Field $Keyboard 'name')) { Set-Field $Keyboard 'name' 'Keyboard Manager' }
    if ($null -eq (Get-Field $Keyboard 'version')) { Set-Field $Keyboard 'version' '1' }
    $runProperties = Get-Field $Run 'properties' ([pscustomobject]@{})
    Set-Field $runProperties 'open_powerlauncher' $Launcher.activationShortcut
    Set-Field $runProperties 'use_centralized_keyboard_hook' $Launcher.useCentralizedKeyboardHook
    Set-Field $Run 'properties' $runProperties
    return [pscustomobject]@{ General=$General; Keyboard=$Keyboard; Run=$Run }
}
function Get-ManagedTargets([string]$LocalRoot, [string]$StartupRoot) {
    $pt = Join-Path $LocalRoot 'Microsoft\PowerToys'
    $runtime = Join-Path $LocalRoot 'MacKeyboardWindows\runtime'
    $targets = [ordered]@{
        General=(Join-Path $pt 'settings.json')
        Keyboard=(Join-Path $pt 'Keyboard Manager\settings.json')
        Profile=(Join-Path $pt 'Keyboard Manager\default.json')
        Run=(Join-Path $pt 'PowerToys Run\settings.json')
        Startup=(Join-Path $StartupRoot 'Mac Keyboard - Explorer Rename.lnk')
        StartupPowerToys=(Join-Path $StartupRoot 'Mac Keyboard - PowerToys.lnk')
    }
    foreach ($file in @('MacKeyboardActions.cs','MacKeyboardActions.exe','ExplorerRename.cs','ExplorerRename.exe','Open-TerminalHere.ps1')) {
        $targets['Runtime-' + $file] = Join-Path $runtime $file
    }
    return $targets
}
function Save-SetupBackup($Targets, [string]$BackupDirectory) {
    $null = New-Item -ItemType Directory -Path $BackupDirectory -Force
    $files = @()
    foreach ($label in $Targets.Keys) {
        $exists = Test-Path -LiteralPath $Targets[$label] -PathType Leaf
        $backupName = $label + '.bak'
        if ($exists) { Copy-Item -LiteralPath $Targets[$label] -Destination (Join-Path $BackupDirectory $backupName) }
        $files += [pscustomobject]@{label=$label;target=$Targets[$label];existed=$exists;backup=$backupName}
    }
    Write-Settings (Join-Path $BackupDirectory 'manifest.json') ([pscustomobject]@{version=1;created=(Get-Date -Format o);files=$files})
}
function Restore-SetupBackup([string]$BackupDirectory, $AllowedTargets) {
    $manifest = Read-Settings (Join-Path $BackupDirectory 'manifest.json')
    if ($manifest.version -ne 1 -or @($manifest.files).Count -ne $AllowedTargets.Count) { throw 'Unrecognized backup manifest.' }
    $seen = @{}
    # Validate everything before touching any destination.
    foreach ($file in $manifest.files) {
        if (-not $AllowedTargets.Contains($file.label) -or $seen.ContainsKey($file.label)) { throw 'Unexpected or duplicate backup target.' }
        if ([IO.Path]::GetFullPath($file.target) -ine [IO.Path]::GetFullPath($AllowedTargets[$file.label])) { throw 'Backup target does not match this machine.' }
        if ($file.backup -ne ($file.label + '.bak')) { throw 'Unexpected backup filename.' }
        if ($file.existed -and -not (Test-Path -LiteralPath (Join-Path $BackupDirectory $file.backup) -PathType Leaf)) { throw 'A backup file is missing.' }
        $seen[$file.label] = $true
    }
    foreach ($file in $manifest.files) {
        if ($file.existed) {
            $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($file.target)) -Force
            Copy-Item -LiteralPath (Join-Path $BackupDirectory $file.backup) -Destination $file.target -Force
        } elseif (Test-Path -LiteralPath $file.target -PathType Leaf) {
            Remove-Item -LiteralPath $file.target
        }
    }
}
function Build-Helpers([string]$SourceDirectory, [string]$OutputDirectory) {
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
    if (-not (Test-Path -LiteralPath $framework)) { $framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319' }
    $wpf = Join-Path $framework 'WPF'
    Add-Type -TypeDefinition (Get-Content -LiteralPath (Join-Path $SourceDirectory 'MacKeyboardActions.cs') -Raw) -Language CSharp -OutputAssembly (Join-Path $OutputDirectory 'MacKeyboardActions.exe') -OutputType WindowsApplication
    Add-Type -TypeDefinition (Get-Content -LiteralPath (Join-Path $SourceDirectory 'ExplorerRename.cs') -Raw) -Language CSharp -OutputAssembly (Join-Path $OutputDirectory 'ExplorerRename.exe') -OutputType WindowsApplication -ReferencedAssemblies @('System.Windows.Forms',(Join-Path $wpf 'UIAutomationClient.dll'),(Join-Path $wpf 'UIAutomationTypes.dll'),(Join-Path $wpf 'WindowsBase.dll'))
}
function Find-PowerToys {
    $process = Get-Process -Name PowerToys -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($process -and $process.Path) { return $process.Path }
    foreach ($candidate in @((Join-Path $env:ProgramFiles 'PowerToys\PowerToys.exe'),(Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.exe'))) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}
function Stop-KeyboardSetupProcesses {
    Get-Process -Name 'PowerToys','PowerToys.*','ExplorerRename','MacKeyboardActions' -ErrorAction SilentlyContinue | Stop-Process -Force
}
function Start-HelperFromShortcut([string]$ShortcutPath) {
    if (Test-Path -LiteralPath $ShortcutPath -PathType Leaf) {
        $shell = New-Object -ComObject WScript.Shell
        $target = $shell.CreateShortcut($ShortcutPath).TargetPath
        if (Test-Path -LiteralPath $target -PathType Leaf) { Start-Process -FilePath $target -WindowStyle Hidden }
    }
}
