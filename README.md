# Mac keyboard shortcuts on Windows

A personal Windows keyboard setup backed by PowerToys, with FL Studio exceptions and context-aware Enter-to-rename in File Explorer. Reference version: PowerToys 0.94.2, Windows, Windows PowerShell 5.1. The profile is captured from the working setup on 4 November 2026.

## Set up a new PC

Clone this repository or download and extract its ZIP. For example, with GitHub CLI:

```powershell
gh repo clone avnidhar/mac-keyboard-windows
cd mac-keyboard-windows
```

Open **Windows PowerShell** (`powershell.exe`, not PowerShell 7) in the project folder:

```powershell
.\Setup.ps1 -WhatIf
.\Setup.ps1 -InstallPrerequisites
```

`-InstallPrerequisites` installs missing PowerToys/Windows Terminal packages through `winget` and accepts their package/source agreements. Omit that switch if they are already installed. Installation may require the normal Windows installer prompt. If the `wt.exe` alias is unavailable afterward, launch Terminal once and rerun setup.

The script compiles both included C# helpers locally, stops PowerToys and the old Explorer rename helper, backs up affected files, applies the profile, enables Keyboard Manager/Run, and starts them. Existing **default** keyboard mappings are replaced; other named profiles and unrelated PowerToys/plugin settings are preserved. It installs two per-user sign-in shortcuts so PowerToys and the Explorer helper start automatically. `-NoStart` installs without launching them immediately.

If local script policy blocks execution, a process-only invocation is available; it does not change persistent execution policy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -InstallPrerequisites
```

Runtime files live in `%LOCALAPPDATA%\MacKeyboardWindows\runtime`, so moving/deleting the clone after installation does not break shortcuts. No admin privileges are needed for the keyboard setup itself. Tested with the reference configuration; future PowerToys schema changes may require updates. See [CHANGELOG.md](CHANGELOG.md) for deliberate deviations from macOS.

## Which physical keys to use

| Physical key | Role | PowerToys output |
| --- | --- | --- |
| Left Alt | Command (âŒ˜) | Right Ctrl |
| Left Windows | Another Command key | Right Ctrl |
| Right Alt | Option / normal Alt | Left Alt |
| Left Ctrl | Control | Left Ctrl |
| Right Ctrl | Control | Left Ctrl |

The separate left/right Ctrl outputs let Command and Control have different shortcuts. Use the keyboard's **Windows mode**; hardware Mac-mode swaps can change which codes reach PowerToys.

## Current shortcuts

| Shortcut | Result |
| --- | --- |
| âŒ˜ C / V / X / Z / A / S / F | Normal Windows copy/paste/cut/undo/select/save/find, subject to the app |
| âŒ˜ Space | PowerToys Run, a Spotlight-style launcher |
| âŒ˜ Tab / â‡§âŒ˜ Tab | Next/previous window through Alt+Tab / Alt+Shift+Tab |
| Option â† / â†’ | Move by word through Ctrl+Left / Right |
| Option Backspace | Delete previous word through Ctrl+Backspace |
| âŒ˜ Backspace | Delete to line start after releasing Command |
| âŒ˜ \` | Cycle eligible windows of the current application |
| âŒ˜ Q | Close the current window through Alt+F4 |
| âŒ˜ [ / ] | Back/forward through Alt+Left / Right |
| â‡§âŒ˜ 4 | Screenshot selection |
| â‡§âŒ˜ E | New Windows Terminal window |
| â‡§âŒ˜ X | Terminal in the selected/current Explorer folder, or Desktop |
| Control â† / â†’ | Previous/next virtual desktop |
| Control â†‘ | Task View |
| Control â†“ | Escape: dismiss Task View; also acts as Escape elsewhere |

Control+Space and Control+Shift+E/X also work because those shortcuts retain generic Ctrl triggers. Control+Tab keeps its native behavior. Global Command+arrow Home/End/document-boundary overrides were **removed at the user's request**. There are no global Command+arrow entries. The Windows app determines their normal Ctrl-arrow behavior. Shift+arrow selection variants were not added.

Alt+Tab switches individual windows, while macOS groups applications. Command+Q closes the active window and does not necessarily quit every window of an app. These are known differences.

### FL Studio

For `fl64.exe` only:

- **Left Command+â†/â†’ sends Alt+â†/â†’**, moving the selected mixer track. This is the fix confirmed working by the user.
- Command+â†‘/â†“ stays untouched, preserving the working piano-roll behavior.
- Right Alt+â†/â†’ has a normal Alt pass-through exception so global word-navigation rules do not replace it. Those pass-through rules alone did not fix the user's mixer use case.

### File Explorer

- With the file list focused, **Enter starts renaming** the selection.
- **âŒ˜ Enter opens** the selection by sending normal Enter.
- Enter in the rename field confirms the name. Address/search fields and other applications keep normal Enter.
- Bare Enter-to-rename targets Explorer folder windows, not the Desktop or Open/Save dialogs.

`ExplorerRename.exe` is a small background helper. It checks the focused UI element every 100 ms and changes physical Enter to F2 only inside Explorer's item list. It does not record keystrokes. PowerToys supplies the Explorer-only Command+Enter mapping, and the helper ignores that generated Enter. If focus cannot be identified safely, Enter passes through normally. Allow a brief moment after switching focus.

### Terminal in the current folder

The helper uses a single selected filesystem folder if present; otherwise it uses the open Explorer folder. Selecting a file uses its containing/current folder. With Desktop focused it resolves the actual Windows Desktop directory, including OneDrive redirection. Other apps or virtual locations such as This PC show a brief message rather than guessing a folder. It opens a new Terminal window with an explicit starting directory and the default profile. Shell startup scripts can override that directory. Check the active tab if you use Explorer tabs.

### Editing and same-app windows

Command+Backspace waits up to five seconds for modifiers to be released, then sends Shift+Home and Backspace. It cancels if focus changed. Smart Home, soft-wrapped lines, selections, and terminal input can behave differently across apps; test on scratch text.

Command+backtick cycles visible, titled, unowned, non-cloaked windows sharing an executable with the foreground app. It restores minimized targets and does nothing if only one eligible window exists. Utility, elevated, or separately hosted app windows may be excluded. It cycles windows, not tabs. Backtick uses virtual-key 192, normally above Tab on a US layout.

## Back up, update, or undo

Each setup run makes a timestamped backup under:

```text
%LOCALAPPDATA%\MacKeyboardWindows\backups
```

The backup includes the exact previous affected settings, managed helper files, and both sign-in shortcuts, including whether each file originally existed. Failed application attempts trigger automatic file rollback. To undo a completed install, use its printed backup path:

```powershell
.\Restore-Backup.ps1 -BackupPath "$env:LOCALAPPDATA\MacKeyboardWindows\backups\TIMESTAMP" -WhatIf
.\Restore-Backup.ps1 -BackupPath "$env:LOCALAPPDATA\MacKeyboardWindows\backups\TIMESTAMP"
```

Rollback stops the helpers/PowerToys, restores previous files and sign-in links, and restarts the prior setup when possible. Use `-NoStart` to leave it stopped. Prerequisite applications installed through winget are not uninstalled. Only backups from this installer on this machine are accepted. Backups stay local and are not uploaded to Git.

To update the project, pull the latest commit and rerun setup. Re-running creates a fresh backup before replacing the managed runtime files. Runtime sources are compiled from this repository; executable binaries are not committed.

## Check the setup

```powershell
.\tests\Verify.ps1
```

This runs in an isolated temporary folder, compiles the helpers, and checks portable path resolution, unrelated-setting preservation, new-settings defaults, exact rollback, and rejection of unexpected rollback targets. It does not modify the live keyboard setup or press keys.

Then physically check:

1. Scratch text: copy/paste, Option+Backspace, and Command+Backspace (release Command).
2. Several windows: Command+Tab/Shift+Tab; two windows of one app: Command+backtick.
3. Control+Up/Down and desktop switching; Command+Space and both terminal shortcuts.
4. In Explorer: select a disposable file, Enter, edit name, Enter to confirm; Command+Enter to open. Check address-bar Enter.
5. In FL Studio: selected mixer track plus Left Command+Left/Right; confirm Command+Up/Down in Piano Roll.

PowerToys and the Explorer helper must keep running. Normal-privilege remappings may not work in elevated applications or sign-in/password screens. Real hardware, Explorer tabs, keyboard modes/layouts, and app-specific behavior still need the manual checks above.

## Files

- `keyboard-profile.json`: exact mappings with machine-independent program placeholders.
- `launcher-settings.json`: only the Run activation/hook settings.
- `Setup.ps1`, `Common.ps1`, `Restore-Backup.ps1`: installation, backup, and rollback.
- `ExplorerRename.cs`: context-aware Explorer Enter helper.
- `MacKeyboardActions.cs`: line deletion and same-app window cycling.
- `Open-TerminalHere.ps1`: Explorer/Desktop terminal launcher.
- `tests/Verify.ps1`: isolated verification.

References: [PowerToys Keyboard Manager](https://learn.microsoft.com/windows/powertoys/keyboard-manager), [PowerToys Run](https://learn.microsoft.com/windows/powertoys/run), [Windows Terminal arguments](https://learn.microsoft.com/windows/terminal/command-line-arguments), [Mac keyboard shortcuts](https://support.apple.com/102650).
