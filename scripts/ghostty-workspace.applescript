-- Ghostty Workspace Launcher
-- Creates a split layout with Claude on left, dev processes on right
--
-- Arguments (passed via environment or command line):
--   PROJECT_PATH: Path to the project
--   COMMANDS: JSON array of commands to run in right panes

use AppleScript version "2.4"
use scripting additions

-- Configuration
property shellLoadDelay : 0.5
property splitDelay : 0.3
property keystrokeDelay : 0.05

on run argv
    set projectPath to system attribute "PROJECT_PATH"
    set claudeCmd to system attribute "CLAUDE_CMD"
    set processCommands to system attribute "PROCESS_COMMANDS"

    if projectPath is "" then
        set projectPath to "~"
    end if

    if claudeCmd is "" then
        set claudeCmd to "claude"
    end if

    -- Parse process commands (newline separated)
    set processList to paragraphs of processCommands
    set processCount to count of processList

    -- Activate or launch Ghostty
    tell application "Ghostty"
        activate
    end tell

    delay shellLoadDelay

    tell application "System Events"
        tell process "Ghostty"
            set frontmost to true

            -- Create new window with Cmd+N
            keystroke "n" using command down
            delay shellLoadDelay

            -- CD to project and run Claude in left pane
            my typeCommand("cd " & quoted form of projectPath & " && " & claudeCmd)
            delay 0.1
            keystroke return
            delay shellLoadDelay

            if processCount > 0 then
                -- Create first split to the right (Cmd+D)
                keystroke "d" using command down
                delay splitDelay

                -- Run first process
                set firstCmd to item 1 of processList
                my typeCommand(firstCmd)
                delay 0.1
                keystroke return

                -- For additional processes, split down in the right column
                repeat with i from 2 to processCount
                    delay splitDelay
                    -- Split down (Cmd+Shift+D)
                    keystroke "d" using {command down, shift down}
                    delay splitDelay

                    set processCmd to item i of processList
                    my typeCommand(processCmd)
                    delay 0.1
                    keystroke return
                end repeat

                -- Go back to the Claude pane (left)
                delay 0.2
                -- Navigate to leftmost pane
                repeat processCount times
                    keystroke "[" using command down
                    delay 0.1
                end repeat
            end if
        end tell
    end tell

    return "Workspace created with " & processCount & " dev processes"
end run

-- Helper to type a command character by character (more reliable than keystroke)
on typeCommand(cmd)
    tell application "System Events"
        -- Use clipboard for reliability with special characters
        set the clipboard to cmd
        delay 0.1
        keystroke "v" using command down
    end tell
end typeCommand
