# AppleScript Automation Guide for Zyquo Agent

You have access to AppleScript tools for automating macOS applications.

## Available Tools

### `applescript.run` (MODERATE risk)
Execute any AppleScript code. Risk is assessed per-script:
- SAFE: read-only property access
- MODERATE: app control, navigation, playback
- DANGEROUS: UI scripting (keystroke, click), file mutations
- CRITICAL: `do shell script`, `sudo`, shutdown/restart

### `applescript.query` (SAFE risk)
Read-only AppleScript queries. Rejects scripts with mutating operations.
Use for gathering information without side effects.

### `applescript.info` (SAFE risk)
Get reference documentation for a specific macOS app before writing scripts.

## Supported Applications

| Application     | Key Capabilities                                          |
|----------------|----------------------------------------------------------|
| Safari         | URL navigation, tab management, JavaScript execution      |
| Music          | Playback control, track info, playlists, volume           |
| Finder         | File operations, folders, selection, trash, reveal        |
| System Events  | GUI scripting, keyboard/mouse, login items, dark mode     |
| Terminal       | Shell commands, window management                         |
| Mail           | Send/read email, attachments, rules, mailbox management   |
| Calendar       | Events, alarms, recurring events, calendars               |
| Contacts       | Create/read/modify contacts, groups, search               |
| Messages       | Send iMessage/SMS, read chats                             |
| Notes          | Create/read/modify notes, folders, HTML content           |
| Keynote        | Create presentations, slides, export                      |
| Pages          | Document creation, text formatting, export                |
| Numbers        | Spreadsheet operations, cells, formulas, export           |

## Security Requirements (macOS Sonoma+)

Scripts that interact with other apps require user-granted permissions:
- **Accessibility**: System Settings > Privacy & Security > Accessibility
- **Automation**: System Settings > Privacy & Security > Automation
- **Full Disk Access**: For protected folders

## Best Practices

1. Use `applescript.info` first to check available commands
2. Use `applescript.query` for read-only operations (no approval needed)
3. Use `try...on error` blocks for robustness
4. Use `delay` between UI scripting steps
5. Use `quoted form of` for shell paths with spaces
6. Always call `save` after modifying Contacts or Calendar
7. Prefer `do shell script` over Terminal app for background tasks
8. Use `id` instead of `name` for stable object references

## Common Patterns

### Get system info
```applescript
set userName to do shell script "whoami"
set macModel to do shell script "sysctl -n hw.model"
```

### Check if app is running
```applescript
tell application "System Events"
    set isRunning to (name of processes) contains "Safari"
end tell
```

### Display notification
```applescript
display notification "Task complete" with title "Zyquo" sound name "Glass"
```

### Toggle dark mode
```applescript
tell application "System Events"
    tell appearance preferences
        set dark mode to not dark mode
    end tell
end tell
```
