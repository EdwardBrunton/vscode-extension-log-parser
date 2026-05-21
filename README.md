# VS Code Extension Log Parser

Parses VS Code shared process logs to show extension install/update/removal history. Useful for auditing which extension versions were installed on your machine — particularly for investigating supply chain attacks like the [Nx Console compromise (May 2026)](https://www.stepsecurity.io/blog/nx-console-vs-code-extension-compromised).

## Supported Editors

- VS Code
- VS Code Insiders
- Cursor
- VSCodium
- Windsurf

## Usage

```powershell
# Show full extension update history across all detected editors
.\Parse-VSCodeExtensionLog.ps1

# Check if a specific version was ever installed
.\Parse-VSCodeExtensionLog.ps1 -CheckExtension "nrwl.angular-console" -CheckVersion "18.95.0"

# Scan a specific log file or directory
.\Parse-VSCodeExtensionLog.ps1 -LogPath "C:\Users\me\AppData\Roaming\Code\logs\20260519T154502\sharedprocess.log"
```

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-LogPath` | Path to a specific log file or directory. If omitted, scans all detected editors automatically. |
| `-CheckExtension` | Extension ID to check (e.g. `nrwl.angular-console`). Used with `-CheckVersion`. |
| `-CheckVersion` | Version to search for (e.g. `18.95.0`). Reports whether it was ever installed. |

## Output

Results are grouped by editor, showing removed versions (ascending) followed by installed versions:

```
=== VS Code ===

nrwl.angular-console
  [-] 18.92.0   (2026-05-19 15:46:42.729)
  [+] 18.100.0  (2026-05-19 15:46:41.579)

=== Summary ===
Editors scanned: VS Code
Extensions updated: 26
Total install events: 85
Total removal events: 54

OK: nrwl.angular-console@18.95.0 was NEVER installed (not found in any logs)
```

## How It Works

The script parses `sharedprocess.log` files that VS Code writes during extension operations. It extracts three types of events:

- **Extracted** — extension version was downloaded and unpacked (`[+]`)
- **Installed** — extension was registered in `extensions.json`
- **Removed** — old version was marked for cleanup (`[-]`)

Duplicate removal entries (caused by multiple profiles or restarts) are deduplicated.
