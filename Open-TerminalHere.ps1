param([switch]$ResolveOnly)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TerminalHereContext {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hwnd, StringBuilder name, int count);
}
'@

try {
    $foreground = [TerminalHereContext]::GetForegroundWindow()
    $className = New-Object System.Text.StringBuilder 256
    $null = [TerminalHereContext]::GetClassName($foreground, $className, 256)
    $folder = $null
    if ($className.ToString() -in @('Progman', 'WorkerW')) {
        $folder = [Environment]::GetFolderPath('DesktopDirectory')
    }
    elseif ($className.ToString() -in @('CabinetWClass', 'ExploreWClass')) {
        $shell = New-Object -ComObject Shell.Application
        foreach ($window in @($shell.Windows())) {
            if ([long]$window.HWND -ne $foreground.ToInt64()) { continue }
            $document = $window.Document
            $selected = @($document.SelectedItems())
            # A single selected filesystem folder wins; otherwise use the open folder.
            if ($selected.Count -eq 1 -and $selected[0].IsFolder -and
                (Test-Path -LiteralPath $selected[0].Path -PathType Container)) {
                $folder = $selected[0].Path
            }
            else {
                $folder = $document.Folder.Self.Path
            }
            break
        }
    }
    if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
        throw 'Focus a File Explorer folder or the desktop, then press Command+Shift+X again. Virtual locations such as This PC do not have a terminal directory.'
    }
    if ($ResolveOnly) { Write-Output $folder; return }
    $terminal = (Get-Command wt.exe -ErrorAction Stop).Source
    # Forward slashes avoid trailing-backslash quotation issues at drive roots.
    # Start-Process passes a literal argument string; folder names are never shell code.
    $directoryArgument = $folder.Replace('\', '/')
    Start-Process -FilePath $terminal -ArgumentList ('-w new new-tab -d "' + $directoryArgument + '"')
}
catch {
    if ($ResolveOnly) { throw }
    $message = $_.Exception.Message
    $popup = New-Object -ComObject WScript.Shell
    $null = $popup.Popup($message, 5, 'Terminal in this folder', 48)
}
