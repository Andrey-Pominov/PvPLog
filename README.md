# PvPAnalytics

PvPAnalytics is a World of Warcraft addon for retail that tracks your arena and PvP matches with detailed combat logging, statistics, and player information. It automatically captures combat events, tracks statistics, and logs important match data for analysis. Inspired by Details! and ArenaAnalytics, it provides comprehensive player profiles, win/loss tracking, and web export capabilities.

## Features

- **Arena Detection**: Automatically detects when you enter or leave an arena (or other instanced PvP zone).
- **Arena Mode Detection**: Automatically identifies arena mode (2v2, 3v3, Solo Shuffle, 1v1) based on group size and difficulty.
- **Combat Log Tracking**: Captures and logs combat events including damage, healing, interrupts, and critical hits.
- **Statistics Tracking**: Calculates real-time statistics including:
  - Total damage, healing, interrupts, and critical hits
  - Damage/healing/interrupts/crits broken down by player (GUID-based)
  - CC chains, trinket usage, and big button (cooldown/racial) usage
- **Win/Loss Tracking**: Automatically calculates match outcomes based on death counts and updates player statistics.
- **Match Ratings**: Calculates performance ratings for each match using an Elo-like system based on win/loss and performance metrics.
- **Player Profiles**: Tracks detailed statistics for all players including:
  - Matches played, wins, losses, and win rate (K/D ratio)
  - Total damage and healing across all matches
  - Average performance metrics
- **User Profile**: Maintains comprehensive statistics for your main character:
  - Total matches, wins, losses, and win percentage
  - Average damage, healing, and interrupts per match
  - Favorite maps (most played arenas)
  - Performance trends (last 10 matches)
- **CC Chain Detection**: Automatically detects when multiple crowd control effects are applied to the same target in quick succession (within 5 seconds).
- **Trinket Tracking**: Monitors PvP trinket usage and detects when trinkets are used to break crowd control effects.
- **Big Button Tracking**: Tracks major offensive/defensive cooldowns and racial abilities (e.g., Avenging Wrath, Combustion, Will of the Forsaken).
- **Match Metadata**: Records map, start/end timestamps, arena mode (2v2, 3v3, Solo Shuffle, 1v1), duration, winner, and player rosters.
- **Class & Specialization Detection**: Automatically detects and records class and specialization for all players (allies and opponents).
- **Faction Tracking**: Records faction (Alliance/Horde) for all players.
- **Text Logs**: Maintains a readable text log of important combat events during the match.
- **Web Export**: Export match data as JSON for integration with your personal website or analytics dashboard.

## Installation

1. Download or clone this repository into your World of Warcraft addons directory:  
   `World of Warcraft/_retail_/Interface/AddOns/PvPAnalytics`
2. Launch the game (or reload the UI) and make sure `PvPAnalytics` is enabled on the AddOns selection screen.

The addon declares the `PvPAnalyticsDB` SavedVariables table where it stores match history, player profiles, and user statistics.

## Usage

- **Entering an Arena**: When you enter an arena, the addon automatically:
  - Detects the arena mode (2v2, 3v3, Solo Shuffle, or 1v1)
  - Collects all player information (allies and opponents) including class, spec, and faction
  - Initializes player profiles for team members
  - Starts tracking combat log events
  - Begins logging important events to a text log
  - Displays a confirmation message: `[PvPAnalytics] Match Started: <zone> (<mode>)`

- **During the Match**: The addon continuously:
  - Captures combat log events (damage, healing, interrupts)
  - Updates statistics in real-time
  - Logs important events with timestamps
  - Tracks critical hits separately
  - Detects CC chains when multiple crowd control effects are applied in sequence
  - Monitors trinket usage and whether it breaks active CC
  - Tracks major cooldowns and racial abilities (big buttons)
  - Updates player information when arena opponent specializations become available

- **Leaving the Match**: When you leave, the addon:
  - Calculates win/loss based on death counts
  - Updates your user profile and player statistics
  - Calculates match rating based on performance
  - Finalizes the match data
  - Saves everything to `PvPAnalyticsDB`
  - Displays a summary: `[PvPAnalytics] Match Ended: WIN/LOSS | Rating: <rating> | Duration: <seconds>s`
  - Clears the current match data

- **Viewing Matches**: 
  - Run `/pvpdata` to see a list of all saved matches with statistics and player count
  - Use `/pvpdata profile` to view your personal statistics and performance metrics
  - Use `/pvpdata export <matchId>` to export a specific match as JSON for your website
  - Use `/pvpdata clear` to clear all stored data

## Commands Reference

- `/pvpdata` - List all saved matches with summary statistics and player count
- `/pvpdata profile` - Show your personal statistics including win rate, average damage/healing, and performance trends
- `/pvpdata export <matchId>` - Export a specific match as JSON for website integration (copy the output and upload to your site)
- `/pvpdata clear` - Clear all stored matches and player data

## Match Data Structure

Each saved match includes:

- **Match Info**: 
  - `id` - Unique match identifier (timestamp-based)
  - `date` - Match start timestamp (YYYY-MM-DD HH:MM:SS)
  - `endTime` - Match end timestamp
  - `map` - Arena map name
  - `mode` - Arena mode (2v2, 3v3, Solo Shuffle, 1v1, unknown)
  - `duration` - Match duration in seconds
  - `winner` - Match outcome ("your_team" or "opponents")
  - `yourTeamSize` - Number of players on your team

- **Players**: GUID-indexed table of all participants with:
  - `name` - Player name
  - `class` - Class name
  - `spec` - Specialization name
  - `faction` - Player faction (Alliance/Horde)
  - `isAlly` - Boolean indicating if player is on your team (true) or enemy (false)
  - `damageShare` - Player's damage contribution percentage
  - `ccUptime` - Crowd control uptime tracking

- **Opponents**: Separate table for enemy team tracking (similar structure to players)

- **Statistics**: Aggregated stats:
  - `damage` - Damage per player (GUID-indexed)
  - `healing` - Healing per player (GUID-indexed)
  - `absorbs` - Absorbs per player (GUID-indexed)
  - `interrupts` - Interrupts per player (GUID-indexed)
  - `ccChains` - CC chains initiated per player (GUID-indexed)
  - `trinketUsage` - Trinket uses per player (GUID-indexed)
  - `bigButtonUsage` - Big button (cooldown/racial) uses per player (GUID-indexed)
  - `deaths` - Death count per player (GUID-indexed)
  - `teamDamageShare` - Total team damage for percentage calculations
  - `matchRating` - Calculated performance rating for the match

- **Events**: Array of event entries with timestamps showing important combat events:
  - Damage and healing events
  - Interrupt events
  - Death events (with destGUID for win/loss calculation)
  - CC events (stuns, silences, incapacitates, etc.) with APPLIED/REMOVED status
  - CC_CHAIN events showing sequences of crowd control applied to targets
  - TRINKET events showing trinket usage and whether CC was broken
  - BIG_BUTTON events showing major cooldown and racial ability usage (categorized as OFFENSIVE/DEFENSIVE/RACIAL)
  - DEFENSIVE and BURST events for major defensive and offensive cooldowns

## Database Structure (PvPAnalyticsDB)

The addon maintains a comprehensive database structure:

- **matches**: Array of all saved match data
- **players**: GUID-indexed table of player profiles with:
  - `name`, `class`, `classId`, `specId`, `faction`
  - `matchesPlayed`, `wins`, `losses`, `kdratio`
  - `totalDamage`, `totalHealing`, `interruptsPerMatch`
- **userProfile**: Your main character's aggregated statistics:
  - `guid`, `name`, `realm`, `faction`
  - `totalMatches`, `totalWins`, `totalLosses`
  - `avgDamage`, `avgHealing`, `avgInterrupts`
  - `favoriteMaps` - Map play count
  - `performanceTrends` - Last 10 matches with ratings
- **settings**: User preferences:
  - `trackCCChains` - Enable/disable CC chain tracking
  - `trackTrinkets` - Enable/disable trinket tracking
  - `exportFormat` - Export format (currently "json")

## Web Integration

The addon supports exporting match data as JSON for integration with your personal website:

1. Use `/pvpdata export <matchId>` in-game to get JSON output
2. Copy the JSON from the chat window
3. Save it as a `.json` file or upload directly to your website
4. Parse the JSON in your web application (JavaScript, Python, PHP, etc.) to create visualizations, charts, or analytics dashboards

Example use cases:
- Create win/loss charts using Chart.js or D3.js
- Build a match history viewer
- Analyze performance trends over time
- Share match data with teammates
- Build leaderboards or statistics pages

## Development Notes

- Core logic resides in `PvPAnalytics.lua` with combat log processing in `CombatLog.lua` and spell definitions in `Constants.lua`.
- Event-driven architecture using WoW's event system.
- The addon uses Blizzard-provided APIs only; no external libraries are required.
- Combat log events are captured via `COMBAT_LOG_EVENT_UNFILTERED` and processed in real-time with error handling.
- CC chain detection uses a 5-second time window to identify consecutive crowd control applications on the same target.
- Trinket tracking monitors `SPELL_CAST_SUCCESS` events for PvP trinket spell IDs and checks for active CC debuffs.
- Big button tracking captures major cooldowns (BURST/DEFENSIVE) and racial abilities via `SPELL_CAST_SUCCESS` events.
- Class/spec detection uses `UnitClass`, `GetSpecializationInfo`, `GetArenaOpponentSpec`, and `GetInspectSpecialization` APIs.
- Arena mode detection is based on party/raid size and instance difficulty.
- Win/loss calculation is based on death counts (more opponent deaths = win).
- Match ratings use a simple Elo-like system based on win/loss and performance metrics.
- Player information is refreshed when `ARENA_PREP_OPPONENT_SPECIALIZATIONS` or `ARENA_OPPONENT_UPDATE` events fire.
- JSON export uses a custom serialization function that handles tables, arrays, strings, numbers, and booleans.

## Author

Rmpriest
