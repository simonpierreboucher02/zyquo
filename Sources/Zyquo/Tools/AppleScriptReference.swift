import Foundation

// MARK: - AppleScript Reference

/// Embedded reference documentation for AppleScript automation of macOS apps.
///
/// Provides concise, actionable reference for the agent when writing
/// AppleScript. Each app section includes key properties, commands,
/// and ready-to-use script patterns.
enum AppleScriptReference {

    /// Returns reference info for a given application name.
    static func info(for app: String) -> String {
        switch app.lowercased() {
        case "safari":
            return safari
        case "music", "apple music":
            return music
        case "finder":
            return finder
        case "system events":
            return systemEvents
        case "terminal":
            return terminal
        case "mail":
            return mail
        case "calendar":
            return calendar
        case "contacts":
            return contacts
        case "messages":
            return messages
        case "notes":
            return notes
        case "keynote":
            return keynote
        case "pages":
            return pages
        case "numbers":
            return numbers
        default:
            return ""
        }
    }

    // MARK: - Safari

    static let safari = """
    # Safari AppleScript Reference

    ## Key Properties
    - `documents` / `windows` / `tabs` — navigation containers
    - `URL of document/tab` (r/w) — current URL
    - `name of document/tab` (r/o) — page title
    - `current tab of window` (r/w) — active tab
    - `source of document` (r/o) — HTML source

    ## Commands
    - `make new document with properties {URL:"..."}` — open URL in new window
    - `make new tab at end of tabs of window 1 with properties {URL:"..."}` — new tab
    - `set URL of document 1 to "..."` — navigate
    - `do JavaScript "..." in document 1` — execute JS, returns result
    - `go back document 1` / `go forward document 1` — history navigation
    - `reload document 1` — refresh page

    ## Patterns
    ```applescript
    -- Get current page title and URL
    tell application "Safari"
        set pageTitle to name of current tab of window 1
        set pageURL to URL of current tab of window 1
        return pageTitle & " — " & pageURL
    end tell

    -- Execute JavaScript
    tell application "Safari"
        set result to do JavaScript "document.title" in document 1
    end tell

    -- List all open tabs
    tell application "Safari"
        set tabList to {}
        repeat with w in windows
            repeat with t in tabs of w
                set end of tabList to (name of t) & " | " & (URL of t)
            end repeat
        end repeat
        return tabList as text
    end tell
    ```

    ## Limitations
    - No direct bookmark/history/cookie access
    - `do JavaScript` requires Accessibility permission
    - No download management API
    """

    // MARK: - Music

    static let music = """
    # Apple Music AppleScript Reference

    ## Key Properties
    - `player state` (r/o) — "playing", "paused", "stopped"
    - `sound volume` (r/w) — 0-100
    - `shuffle` (r/w) — boolean
    - `song repeat` (r/w) — off/one/all
    - `current track` (r/o) — reference to playing track
    - `player position` (r/w) — seconds into track

    ## Track Properties
    - `name`, `artist`, `album`, `genre` (r/o text)
    - `duration` (r/o real) — seconds
    - `loved` (r/w boolean), `rating` (r/w 0-100)
    - `artwork` (r/o)

    ## Commands
    - `play` / `pause` / `stop` / `playpause`
    - `next track` / `previous track` / `back track`
    - `make new user playlist with properties {name:"..."}`
    - `duplicate track to playlist`

    ## Patterns
    ```applescript
    -- Get current track info
    tell application "Music"
        if player state is playing then
            return name of current track & " by " & artist of current track
        end if
    end tell

    -- Control playback
    tell application "Music"
        set sound volume to 50
        play
    end tell

    -- Create playlist
    tell application "Music"
        set newPL to make new user playlist with properties {name:"My Playlist"}
    end tell
    ```
    """

    // MARK: - Finder

    static let finder = """
    # Finder AppleScript Reference

    ## Key Properties
    - `selection` (r/o) — currently selected items
    - `startup disk` (r/o) — boot volume
    - `desktop` (r/o) — desktop folder
    - `trash` (r/o) — trash container
    - `name`, `size`, `kind`, `creation date`, `modification date` of items

    ## Commands
    - `make new folder at ... with properties {name:"..."}` — create folder
    - `make file at ... with properties {name:"..."}` — create file
    - `make alias file to ... at ...` — create alias
    - `duplicate item to destination` — copy
    - `move item to destination` — move (within same volume)
    - `delete item` — move to trash
    - `empty trash` — permanently delete
    - `open item` / `open item using application` — open
    - `reveal item` — show in Finder
    - `select item` — select in window
    - `clean up window by name/size/modification date`
    - `sort items by property` — sorted references
    - `exists item` — check existence
    - `count items of container`

    ## Patterns
    ```applescript
    -- Create folder
    tell application "Finder"
        make new folder at desktop with properties {name:"New Folder"}
    end tell

    -- Get selected files
    tell application "Finder"
        set sel to selection
        repeat with item_ in sel
            log name of item_
        end repeat
    end tell

    -- Copy files
    tell application "Finder"
        duplicate file "Report.pdf" of desktop to folder "Backups" of startup disk
    end tell

    -- Search with Spotlight (via shell)
    set results to do shell script "mdfind 'kind:pdf name:report'"
    ```

    ## Limitations
    - Cross-volume `move` becomes copy (doesn't delete original)
    - No direct Spotlight/tag API; use `mdfind` via shell
    """

    // MARK: - System Events

    static let systemEvents = """
    # System Events AppleScript Reference

    ## Capabilities
    - GUI scripting (click, keystroke, menu access)
    - Process management
    - Login items
    - System preferences (appearance, dock)
    - Disk/folder/file operations via XML

    ## GUI Scripting (requires Accessibility permission)
    ```applescript
    tell application "System Events"
        tell process "AppName"
            click button "OK" of window 1
            click menu item "Save" of menu "File" of menu bar 1
            keystroke "hello"
            keystroke "c" using command down
            keystroke "v" using {command down, shift down}
            key code 126  -- arrow up
        end tell
    end tell
    ```

    ## Key Codes
    - 51: Delete, 53: Escape
    - 123/124/125/126: Left/Right/Down/Up arrows
    - 36: Return, 48: Tab

    ## Login Items
    ```applescript
    tell application "System Events"
        get properties of every login item
        make new login item with properties {path:"/Applications/App.app", hidden:false}
        delete login item "AppName"
    end tell
    ```

    ## System Preferences
    ```applescript
    tell application "System Events"
        tell appearance preferences
            set dark mode to not dark mode
        end tell
        tell dock preferences
            set properties to {autohide:true, dock size:0.5}
        end tell
    end tell
    ```

    ## Notifications
    ```applescript
    display notification "Message" with title "Title" subtitle "Sub" sound name "Hero"
    ```

    ## Limitations
    - GUI scripting is fragile — breaks on UI changes
    - Requires Accessibility permission in System Settings
    - Performance is slower than native API calls
    """

    // MARK: - Terminal

    static let terminal = """
    # Terminal AppleScript Reference

    ## Two Approaches
    1. `do shell script "..."` — background, no Terminal window, returns output
    2. `tell application "Terminal" to do script "..."` — visible Terminal window

    ## do shell script (preferred for automation)
    ```applescript
    set result to do shell script "ls -la ~/Documents"
    do shell script "command" with administrator privileges  -- sudo
    ```

    ## Terminal app control
    ```applescript
    tell application "Terminal"
        activate
        do script "echo hello"  -- new window
        do script "pwd" in window 1  -- existing window
        set custom title of window 1 to "My Terminal"
        set bounds of window 1 to {100, 100, 800, 600}
    end tell
    ```

    ## Key Notes
    - `do shell script` uses `/bin/sh`, not login shell — PATH may differ
    - Use `quoted form of` for paths with spaces
    - `do shell script` is synchronous; Terminal `do script` is async
    - Use full paths for commands not in default PATH
    """

    // MARK: - Mail

    static let mail = """
    # Mail AppleScript Reference

    ## Key Objects
    - `account` — mail accounts
    - `mailbox` — folders (INBOX, Sent, etc.)
    - `message` — individual emails
    - `outgoing message` — composing emails

    ## Message Properties
    - `subject`, `sender`, `content`, `html content`
    - `date received`, `read status` (r/w), `flagged` (r/w)
    - `recipients`, `attachments`

    ## Commands
    - `make new outgoing message` — compose
    - `send` — send a composed message
    - `reply` / `forward` — reply or forward
    - `move message to mailbox` — organize
    - `delete message` — trash
    - `save attachment in file` — save attachments

    ## Patterns
    ```applescript
    -- Send email
    tell application "Mail"
        set msg to make new outgoing message with properties {subject:"Test", content:"Hello!", visible:true}
        tell msg
            make new recipient with properties {address:"user@example.com"}
            -- send
        end tell
    end tell

    -- Read unread messages
    tell application "Mail"
        set inbox to mailbox "INBOX" of account "MyAccount"
        set unread to (every message of inbox whose read status is false)
        repeat with m in unread
            log subject of m & " from " & sender of m
        end repeat
    end tell

    -- Save attachments
    tell application "Mail"
        set msg to first message of mailbox "INBOX" of account "MyAccount"
        repeat with att in attachments of msg
            save att in file ((path to desktop as text) & name of att)
        end repeat
    end tell
    ```

    ## Mail Rules
    ```applescript
    using terms from application "Mail"
        on perform mail action with messages theMessages for rule theRule
            repeat with m in theMessages
                -- process each message
            end repeat
        end perform mail action
    end using terms from
    ```
    """

    // MARK: - Calendar

    static let calendar = """
    # Calendar AppleScript Reference

    ## Key Objects
    - `calendar` — named calendars
    - `event` — calendar events
    - `alarm` — event reminders (display/sound/mail/open file)

    ## Event Properties
    - `summary` (r/w) — title
    - `description` (r/w) — notes
    - `start date` / `end date` (r/w)
    - `all day event` (r/w boolean)
    - `location`, `url` (r/w)
    - `recurrence` (r/w) — iCalendar format (e.g., "FREQ=WEEKLY;BYDAY=MO")
    - `attendees`, `alarms`

    ## Patterns
    ```applescript
    -- Create event
    tell application "Calendar"
        tell calendar "Work"
            set startDate to (current date) + (1 * days)
            set hours of startDate to 9
            set minutes of startDate to 0
            make new event with properties {summary:"Meeting", start date:startDate, end date:startDate + (1 * hours)}
        end tell
    end tell

    -- Add alarm
    tell application "Calendar"
        tell calendar "Work"
            set evt to first event whose summary is "Meeting"
            tell evt
                make new sound alarm with properties {trigger interval:-(15 * minutes), sound name:"Glass"}
            end tell
        end tell
    end tell

    -- List today's events
    tell application "Calendar"
        set today to current date
        set hours of today to 0
        set minutes of today to 0
        set tomorrow to today + (1 * days)
        repeat with cal in every calendar
            set evts to (every event of cal whose start date ≥ today and start date < tomorrow)
            repeat with e in evts
                log summary of e & " at " & time string of start date of e
            end repeat
        end repeat
    end tell
    ```
    """

    // MARK: - Contacts

    static let contacts = """
    # Contacts AppleScript Reference

    ## Key Objects
    - `person` — individual contacts
    - `group` — contact groups
    - `email`, `phone`, `address`, `url` — nested elements of person

    ## Person Properties
    - `first name`, `last name`, `organization`, `job title`
    - `note`, `birth date`, `home page`
    - `company` (boolean) — is this a company contact?

    ## Nested Elements (each has `label` and `value`)
    - `emails` — email addresses
    - `phones` — phone numbers
    - `addresses` — postal addresses (street, city, state, zip, country)
    - `urls` — web URLs

    ## Patterns
    ```applescript
    -- Create contact
    tell application "Contacts"
        set p to make new person with properties {first name:"Alice", last name:"Smith"}
        make new email at end of emails of p with properties {label:"Work", value:"alice@co.com"}
        make new phone at end of phones of p with properties {label:"Mobile", value:"555-1234"}
        save
    end tell

    -- Search contacts
    tell application "Contacts"
        set results to (every person whose last name is "Smith")
        repeat with p in results
            log name of p
        end repeat
    end tell

    -- Add to group
    tell application "Contacts"
        set p to first person whose first name is "Alice"
        set g to first group whose name is "Friends"
        add p to g
        save
    end tell
    ```
    """

    // MARK: - Messages

    static let messages = """
    # Messages AppleScript Reference

    ## Key Objects
    - `service` — iMessage, SMS
    - `chat` — conversations
    - `buddy` — contacts by handle
    - `message` — individual messages

    ## Commands
    - `send "text" to buddy/chat` — send a message
    - `send file to buddy/chat` — send attachment

    ## Patterns
    ```applescript
    -- Send iMessage
    tell application "Messages"
        set targetBuddy to buddy "+1234567890" of service "iMessage"
        send "Hello from AppleScript!" to targetBuddy
    end tell

    -- Send to group chat
    tell application "Messages"
        set targetChat to first chat whose name is "Group Name"
        send "Group message" to targetChat
    end tell

    -- List recent chats
    tell application "Messages"
        repeat with c in every chat
            log name of c
        end repeat
    end tell
    ```

    ## Limitations
    - Requires Messages to be configured and signed in
    - SMS requires iPhone Continuity setup
    - No direct access to message history reading (privacy)
    """

    // MARK: - Notes

    static let notes = """
    # Notes AppleScript Reference

    ## Key Objects
    - `account` — note accounts (iCloud, On My Mac)
    - `folder` — note folders
    - `note` — individual notes

    ## Note Properties
    - `name` (r/o) — title
    - `body` (r/w) — HTML content
    - `creation date`, `modification date` (r/o)

    ## Patterns
    ```applescript
    -- Create note
    tell application "Notes"
        make new note at folder "Notes" of default account with properties {name:"My Note", body:"<p>Content here</p>"}
    end tell

    -- Read notes
    tell application "Notes"
        repeat with n in every note
            log name of n
        end repeat
    end tell

    -- Modify note
    tell application "Notes"
        set n to note "My Note"
        set body of n to "<h1>Updated</h1><p>New content</p>"
    end tell

    -- Create folder
    tell application "Notes"
        make new folder at default account with properties {name:"New Folder"}
    end tell

    -- Move note
    tell application "Notes"
        set n to note "My Note"
        move n to folder "Archive" of default account
    end tell
    ```

    ## Limitations
    - Body uses HTML but not all HTML features supported
    - Checklists require UI scripting to create
    - No direct search-by-content command
    """

    // MARK: - Keynote

    static let keynote = """
    # Keynote AppleScript Reference

    ## Key Objects
    - `document` — presentations
    - `slide` — individual slides
    - `text item` — text boxes
    - `master slide` — slide layouts

    ## Document Commands
    - `make new document with properties {document theme:theme "Name"}`
    - `start document from slide` — begin slideshow
    - `stop document` — end slideshow
    - `show next` / `show previous` — advance slides
    - `export document to file as PDF/Microsoft PowerPoint`

    ## Slide Properties
    - `base slide` — master slide layout
    - `default title item`, `default body item` — text placeholders

    ## Patterns
    ```applescript
    tell application "Keynote"
        set doc to make new document with properties {document theme:theme "Black", width:1920, height:1080}
        tell doc
            tell first slide
                set base slide to master slide "Title & Subtitle"
                set object text of default title item to "My Presentation"
            end tell
            set s to make new slide with properties {base slide:master slide "Title & Bullets"}
            tell s
                set object text of default title item to "Key Points"
                set object text of default body item to "• Point 1" & return & "• Point 2"
            end tell
        end tell
    end tell
    ```
    """

    // MARK: - Pages

    static let pages = """
    # Pages AppleScript Reference

    ## Key Objects
    - `document` — Pages documents
    - `body text` — main text content
    - `section` / `page` — document structure
    - `text item`, `image` — floating elements

    ## Document Properties
    - `document body` (boolean) — word processing (true) vs page layout (false)

    ## Commands
    - `make new document`
    - `export to file as PDF/Microsoft Word`
    - `save in file`

    ## Patterns
    ```applescript
    -- Create and write
    tell application "Pages"
        set doc to make new document
        tell body text of doc
            set font to "Helvetica"
            set size to 14
        end tell
    end tell

    -- Export to PDF
    tell application "Pages"
        export front document to file "Macintosh HD:Users:user:Desktop:doc.pdf" as PDF
    end tell

    -- Insert image
    tell application "Pages"
        tell front document
            make new image with properties {file:"Macintosh HD:path:to:image.png", position:{100, 100}}
        end tell
    end tell
    ```
    """

    // MARK: - Numbers

    static let numbers = """
    # Numbers AppleScript Reference

    ## Key Objects
    - `document` — spreadsheet documents
    - `sheet` — worksheets (tabs)
    - `table` — data tables
    - `cell`, `row`, `column`, `range` — table elements

    ## Cell Properties
    - `value` (r/w) — any type
    - `formula` (r/w) — Numbers formula string
    - `formatted value` (r/o) — display string
    - `background color`, `font name`, `font size`, `text color` (r/w)

    ## Patterns
    ```applescript
    -- Read/write cells
    tell application "Numbers"
        tell front document's active sheet's table 1
            set value of cell "A1" to "Hello"
            set value of cell "B1" to 42
            set formula of cell "C1" to "=A1&B1"
            return value of cell "A1"
        end tell
    end tell

    -- Set range values
    tell application "Numbers"
        tell front document's active sheet's table 1
            set value of range "A1:B2" to {{1, 2}, {3, 4}}
        end tell
    end tell

    -- Create sheet and table
    tell application "Numbers"
        tell front document
            make new sheet with properties {name:"Data"}
            tell active sheet
                make new table with properties {name:"Results", row count:10, column count:5}
            end tell
        end tell
    end tell

    -- Export to CSV
    tell application "Numbers"
        export front document to file "Macintosh HD:Users:user:Desktop:data.csv" as CSV
    end tell
    ```
    """

    // MARK: - General Tips

    /// General AppleScript tips and security notes.
    static let generalTips = """
    # General AppleScript Tips

    ## Security & Permissions (macOS Sonoma+)
    - Accessibility: Required for System Events UI scripting
      → System Settings > Privacy & Security > Accessibility
    - Automation: Required to control other apps
      → System Settings > Privacy & Security > Automation
    - Full Disk Access: Required for protected folders
      → System Settings > Privacy & Security > Full Disk Access

    ## Best Practices
    - Use `try...on error` for error handling
    - Use `delay` between UI scripting actions
    - Use `quoted form of` for shell paths with spaces
    - Prefer `id` over `name` for stable references
    - Use `do shell script` over Terminal app for background tasks
    - Always `save` after modifying Contacts/Calendar

    ## Common Patterns
    ```applescript
    -- Error handling
    try
        tell application "SomeApp"
            -- risky operation
        end tell
    on error errMsg number errNum
        display dialog "Error: " & errMsg
    end try

    -- Wait for condition
    repeat until condition
        delay 0.5
    end repeat

    -- Run shell command
    set result to do shell script "command" & quoted form of somePath
    ```
    """
}
