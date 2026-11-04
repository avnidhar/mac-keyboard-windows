param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'Common.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('mac-keyboard-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
foreach ($file in Get-ChildItem -LiteralPath $repo -Filter '*.ps1' -Recurse) {
    $tokens=$null; $errors=$null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) "Syntax error in $($file.Name): $errors"
}
$runtime = Join-Path $temporary 'runtime with spaces'
$resolved = Resolve-KeyboardProfile (Join-Path $repo 'keyboard-profile.json') $runtime 'C:\Destination User\WindowsApps\wt.exe' 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$terminalHere = $resolved.remapShortcuts.global | Where-Object originalKeys -eq '17;16;88'
Assert ($terminalHere.runProgramArgs.EndsWith('"' + (Join-Path $runtime 'Open-TerminalHere.ps1') + '"')) 'Helper path was not quoted for spaces.'
Assert (($resolved | ConvertTo-Json -Depth 100 -Compress) -notmatch '\{\{') 'Template tokens remain.'
Assert (@($resolved.remapShortcuts.appSpecific | Where-Object { $_.targetApp -eq 'fl64.exe' -and $_.originalKeys -eq '163;37' -and $_.newRemapKeys -eq '164;37' }).Count -eq 1) 'The working FL Studio exception was lost.'
Assert (@($resolved.remapShortcuts.global | Where-Object { $_.originalKeys -in @('163;37','163;39','163;38','163;40') }).Count -eq 0) 'Removed Command-arrow overrides reappeared.'
$general = '{"startup":false,"enabled":{"FancyZones":false},"theme":"custom"}' | ConvertFrom-Json
$keyboard = '{"properties":{"activeConfiguration":{"value":"old"},"keyboardConfigurations":{"value":["old"]}},"custom":42}' | ConvertFrom-Json
$run = '{"properties":{"title_fontsize":27},"plugins":[{"Id":"third-party","Disabled":true,"path":"D:\\Machine Specific"}]}' | ConvertFrom-Json
$launcher = Read-Settings (Join-Path $repo 'launcher-settings.json')
$merged = Merge-PowerToysSettings $general $keyboard $run $launcher
Assert ($merged.General.enabled.FancyZones -eq $false -and $merged.General.theme -eq 'custom') 'Unrelated general settings changed.'
Assert ($merged.Keyboard.custom -eq 42 -and 'old' -in $merged.Keyboard.properties.keyboardConfigurations.value) 'Other keyboard profile/settings were discarded.'
Assert ($merged.Run.plugins[0].path -eq 'D:\Machine Specific' -and $merged.Run.plugins[0].Disabled -and $merged.Run.properties.title_fontsize -eq 27) 'Machine-specific plugin settings changed.'
Assert ($merged.Run.properties.open_powerlauncher.ctrl -and -not $merged.Run.properties.open_powerlauncher.alt) 'Run activation not restored.'
$fresh = Merge-PowerToysSettings ([pscustomobject]@{}) ([pscustomobject]@{}) ([pscustomobject]@{}) $launcher
Assert ($fresh.Keyboard.properties.activeConfiguration.value -eq 'default' -and $fresh.General.enabled.'Keyboard Manager') 'Missing settings were not initialized.'
$targets = Get-ManagedTargets (Join-Path $temporary 'Local') (Join-Path $temporary 'Startup')
Write-Settings $targets.General ([pscustomobject]@{ original='keep me' })
$original = [IO.File]::ReadAllBytes($targets.General)
$backup = Join-Path $temporary 'backup'
Save-SetupBackup $targets $backup
foreach ($label in $targets.Keys) {
    $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($targets[$label])) -Force
    [IO.File]::WriteAllText($targets[$label], 'changed')
}
Restore-SetupBackup $backup $targets
Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($targets.General)) -eq [Convert]::ToBase64String($original)) 'Rollback did not restore the original bytes.'
foreach ($label in $targets.Keys) {
    if ($label -ne 'General') { Assert (-not (Test-Path -LiteralPath $targets[$label])) 'Rollback left a newly created file.' }
}
$manifest = Read-Settings (Join-Path $backup 'manifest.json')
$manifest.files[0].target = Join-Path $temporary 'outside-managed-target.txt'
Write-Settings (Join-Path $backup 'manifest.json') $manifest
$rejected=$false
try { Restore-SetupBackup $backup $targets } catch { $rejected=$true }
Assert $rejected 'An unexpected rollback destination was accepted.'
Assert (-not (Test-Path -LiteralPath $manifest.files[0].target)) 'An unexpected rollback destination was modified.'
if (-not $SkipBuild) {
    Build-Helpers $repo (Join-Path $temporary 'compiled')
    Assert ((Get-Item -LiteralPath (Join-Path $temporary 'compiled\ExplorerRename.exe')).Length -gt 0) 'Explorer helper did not compile.'
    Assert ((Get-Item -LiteralPath (Join-Path $temporary 'compiled\MacKeyboardActions.exe')).Length -gt 0) 'Action helper did not compile.'
}
Write-Output 'PASS: syntax, portable paths, app exceptions, settings preservation, fresh defaults, exact rollback, target validation, and helper compilation.'
Write-Output "Isolated test files: $temporary"
