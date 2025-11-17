# PvPLog

PvPLog is a comprehensive World of Warcraft addon for retail that tracks your arena and PvP matches with detailed combat logging, rating/MMR tracking, and statistics. It automatically captures all combat events, rating changes, and match metadata, then exports everything as JSON for analysis.

## Features

- **Arena Detection**: Automatically detects when you enter or leave an arena (or other instanced PvP zone).
- **Combat Log Tracking**: Captures all combat log events during matches (damage, healing, interrupts, and more).
- **Rating & MMR Tracking**: Records your arena rating and MMR at match start, end, and tracks any changes during the match.
- **Statistics**: Calculates real-time statistics including:
  - Total damage, healing, and interrupts
  - Damage/healing/interrupts broken down by player
  - Event counts by type
- **Match Metadata**: Records map, start/end timestamps, duration, and player rosters (allies and opponents).
- **Class & Specialization Detection**: Automatically detects and records class and specialization for all players (allies and opponents).
- **Database Management**: Comprehensive commands to manage your match database (delete, clear, search, stats, info).
- **Export Functionality**: Provides `/pvplogs` to list saved matches and `/pvpexport <id>` to export complete match data as JSON.
- **Auto Export**: Option to automatically show export dialog after each match is saved.
- **Combat Log Prompt**: Optionally prompts you to enable `/combatlog` for external log files, with an option to toggle automatic prompting.

## Installation

1. Download or clone this repository into your World of Warcraft addons directory:  
   `World of Warcraft/_retail_/Interface/AddOns/PvPLog`
2. Launch the game (or reload the UI) and make sure `PvPLog` is enabled on the AddOns selection screen.

The addon declares the `PvPLogDB` SavedVariables table where it stores persistent settings and match history.

## Usage

- **Entering an Arena**: When you enter an arena, the addon automatically starts recording:
  - All combat log events (damage, healing, interrupts, etc.)
  - Your current rating and MMR
  - Match metadata (map, players, timestamps)
  
  Optionally, you can enable `/combatlog` for external log files. The addon can auto-open chat with the command or show a prompt. The third button on the prompt toggles automatic behavior.

- **During the Match**: The addon continuously:
  - Captures all combat log events
  - Updates statistics in real-time
  - Monitors rating/MMR changes (checks every 5 seconds and on arena events)

- **Leaving the Match**: When you leave, the addon:
  - Finalizes the match data
  - Captures final rating/MMR values
  - Saves everything to `PvPLogDB.matches`
  - Displays a summary with event count and rating change

- **Viewing Matches**: 
  - Run `/pvplogs` to see a list of all saved matches with rating info and event counts
  - Use `/pvplogs export <id>` or `/pvpexport <id>` to open a copyable JSON dialog with complete match data
  - Use `/pvplogs info <id>` to see detailed match information including player classes and specializations

- **Database Management**:
  - `/pvplogs delete <id>` - Delete a specific match (with confirmation)
  - `/pvplogs clear` - Clear all matches (with confirmation)
  - `/pvplogs search <term>` - Search matches by map name or player name
  - `/pvplogs stats` - Show overall statistics (total matches, events, averages, rating changes)
  - `/pvplogs autoexport <on|off>` - Enable/disable automatic export dialog after matches

- **Auto Export**:
  - Enable with `/pvplogs autoexport on`
  - When enabled, the export dialog automatically appears after each match is saved
  - Allows you to quickly copy match data without manual commands

## Exported Data

The JSON export includes:
- **Match Info**: ID, map, mode, timestamps, duration, hash
- **Players**: Names, realms, GUIDs, class, classId, specialization, and specId for all participants (allies and opponents)
- **Rating/MMR**: Start/end values, bracket info (2v2/3v3), and history of changes during the match
- **Events**: Complete array of all combat log events with timestamps, sources, targets, spells, amounts, and event-specific details
- **Statistics**: Aggregated stats including total damage/healing/interrupts, per-player breakdowns, and event type counts

## Commands Reference

### Main Commands
- `/pvplogs` - List all saved matches
- `/pvplogs export <id>` - Export match as JSON (opens dialog)
- `/pvpexport <id>` - Same as above (shorthand)

### Database Management
- `/pvplogs delete <id>` - Delete a specific match
- `/pvplogs clear` - Delete all matches (with confirmation)
- `/pvplogs search <term>` - Search matches by map or player name
- `/pvplogs stats` - Show overall statistics
- `/pvplogs info <id>` - Show detailed match information

### Settings
- `/pvplogs autoexport <on|off>` - Toggle automatic export after matches

## Development Notes

- Core logic resides in `PvPLog.lua`.
- Event wiring is centralized so arena detection, combat log processing, rating tracking, saved-variable initialization, and logout handling all share the same dispatcher.
- The addon uses Blizzard-provided UI frames only; no external libraries are required.
- JSON serialization is handled by a custom implementation that properly handles nested arrays and objects.
- Combat log events are captured via `COMBAT_LOG_EVENT_UNFILTERED` and processed in real-time.
- Rating/MMR tracking uses `GetPersonalRatedInfo` and `GetBattlefieldTeamInfo` APIs, with periodic updates and event-driven snapshots.
- Class/spec detection uses `UnitClass`, `GetSpecializationInfo`, `GetArenaOpponentSpec`, and `GetInspectSpecialization` APIs.
- All timestamps use high-precision `GetTime()` for relative event timing.

