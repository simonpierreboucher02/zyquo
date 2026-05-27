# AppleScript Tools

Zyquo includes three AppleScript tools for automating macOS applications.

## Tools

### applescript.run
Execute AppleScript code via osascript. Risk is classified per-script.
Use for any AppleScript that modifies state.

### applescript.query
Read-only AppleScript queries. Rejects mutating scripts.
Use for gathering information safely.

### applescript.info
Get reference docs for a macOS app before writing scripts.

## Risk Classification

| Level    | Triggers                                            |
|----------|-----------------------------------------------------|
| SAFE     | Property reads, count, exists, get                  |
| MODERATE | activate, open, make new, set, send, do javascript  |
| DANGEROUS| keystroke, click, key code, delete, empty trash      |
| CRITICAL | do shell script, sudo, shutdown, restart, launchctl  |

## Workflow

1. Call `applescript.info` with the target app name
2. Use `applescript.query` for read-only operations
3. Use `applescript.run` when mutations are needed
4. Always wrap in try/on error for robustness
