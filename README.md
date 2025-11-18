# PvPAnalytics

PvPAnalytics is a World of Warcraft addon for retail that tracks your arena and PvP matches with detailed combat logging, statistics, and player information. It automatically captures combat events, tracks statistics, and logs important match data for analysis.

## Features

- **Arena Detection**: Automatically detects when you enter or leave an arena (or other instanced PvP zone).
- **Combat Log Tracking**: Captures and logs combat events including damage, healing, interrupts, and critical hits.
- **Statistics Tracking**: Calculates real-time statistics including:
  - Total damage, healing, interrupts, and critical hits
  - Damage/healing/interrupts/crits broken down by player (GUID-based)
- **Match Metadata**: Records map, start/end timestamps, arena mode (2v2, 3v3, Solo Shuffle, 1v1), and player rosters.
- **Class & Specialization Detection**: Automatically detects and records class and specialization for all players (allies and opponents).
- **Faction Tracking**: Records faction (Alliance/Horde) for all players.
- **Text Logs**: Maintains a readable text log of important combat events during the match.

## Installation

1. Download or clone this repository into your World of Warcraft addons directory:  
   `World of Warcraft/_retail_/Interface/AddOns/PvPAnalytics`
2. Launch the game (or reload the UI) and make sure `PvPAnalytics` is enabled on the AddOns selection screen.

The addon declares the `PvPAnalyticsDB` SavedVariables table where it stores match history.

## Usage

- **Entering an Arena**: When you enter an arena, the addon automatically:
  - Detects the arena mode (2v2, 3v3, Solo Shuffle, or 1v1)
  - Collects all player information (allies and opponents) including class, spec, and faction
  - Starts tracking combat log events
  - Begins logging important events to a text log
  - Displays a confirmation message: `[PvPAnalytics] Arena match started - <zone> (<mode>)`

- **During the Match**: The addon continuously:
  - Captures combat log events (damage, healing, interrupts)
  - Updates statistics in real-time
  - Logs important events with timestamps
  - Tracks critical hits separately
  - Updates player information when arena opponent specializations become available

- **Leaving the Match**: When you leave, the addon:
  - Finalizes the match data
  - Saves everything to `PvPAnalyticsDB`
  - Displays a summary: `[PvPAnalytics] Match saved. Stats: X interrupts, Y crits`
  - Clears the current match data

- **Viewing Matches**: 
  - Run `/pvpdata` to see a list of all saved matches with statistics
  - Use `/pvpdata info <id>` to see detailed match information including players with class/spec and faction

## Commands Reference

- `/pvpdata` - List all saved matches with summary statistics
- `/pvpdata info <id>` - Show detailed match information including players, statistics, and logs

## Match Data Structure

Each saved match includes:

- **Match Info**: 
  - `StartTime` - Match start timestamp (YYYY-MM-DD HH:MM:SS)
  - `EndTime` - Match end timestamp
  - `Zone` - Arena map name
  - `Mode` - Arena mode (2v2, 3v3, Solo Shuffle, 1v1)
  - `Faction` - Your faction (Alliance/Horde)

- **Players**: Array of all participants with:
  - `name` - Player name
  - `realm` - Realm name (nil for opponents)
  - `guid` - Player GUID
  - `class` - Class name
  - `classId` - Class ID
  - `spec` - Specialization name
  - `specId` - Specialization ID
  - `faction` - Player faction
  - `isPlayer` - Boolean indicating if player is on your team (true) or enemy (false)

- **Statistics**: Aggregated stats:
  - `totalDamage` - Total damage dealt
  - `totalHealing` - Total healing done
  - `totalInterrupts` - Total interrupts
  - `totalCrits` - Total critical hits
  - `damageByPlayer` - Damage per player (GUID-indexed)
  - `healingByPlayer` - Healing per player (GUID-indexed)
  - `interruptsByPlayer` - Interrupts per player (GUID-indexed)
  - `critsByPlayer` - Critical hits per player (GUID-indexed)

- **Logs**: Array of text log entries with timestamps showing important events:
  - Damage events with critical hit indicators
  - Healing events with critical hit indicators
  - Interrupt events

## Development Notes

- Core logic resides in `PvPAnalytics.lua`.
- Event-driven architecture using WoW's event system.
- The addon uses Blizzard-provided APIs only; no external libraries are required.
- Combat log events are captured via `COMBAT_LOG_EVENT_UNFILTERED` and processed in real-time.
- Class/spec detection uses `UnitClass`, `GetSpecializationInfo`, `GetArenaOpponentSpec`, and `GetInspectSpecialization` APIs.
- Arena mode detection is based on party/raid size.
- Player information is refreshed when `ARENA_PREP_OPPONENT_SPECIALIZATIONS` or `ARENA_OPPONENT_UPDATE` events fire.

## Author

Rmpriest
