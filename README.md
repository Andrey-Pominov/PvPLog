# PvPLog

PvPLog is a lightweight World of Warcraft addon that helps you keep a local history of your arena and PvP matches. It focuses on reminding you to enable the combat log, capturing essential match metadata, and letting you export that metadata as JSON for external review or analysis.

## Features

- Detects when you enter or leave an arena (or other instanced PvP zone).
- Prompts you to enable `/combatlog`, with an option to toggle automatic prompting.
- Records match metadata including map, start/end timestamps, duration, and player rosters.
- Provides `/pvplogs` to list saved matches in the chat frame.
- Provides `/pvpexport <id>` to open a copyable JSON payload for any recorded match.

## Installation

1. Download or clone this repository into your World of Warcraft addons directory:  
   `World of Warcraft/_retail_/Interface/AddOns/PvPLog`
2. Launch the game (or reload the UI) and make sure `PvPLog` is enabled on the AddOns selection screen.

The addon declares the `PvPLogDB` SavedVariables table where it stores persistent settings and match history.

## Usage

- Enter an arena match: the addon either auto-opens chat with `/combatlog` ready to confirm or shows a prompt asking you to enable it. The third button on the prompt toggles the automatic behavior.
- Leave the match: metadata (map, start/end timestamps, duration, participants) is saved to `PvPLogDB.matches`.
- Run `/pvplogs` to see a summary of recorded matches. Use `/pvplogs export <id>` or `/pvpexport <id>` to open a copyable JSON snippet in a dialog box.

## Development Notes

- Core logic resides in `PvPLog.lua`.
- Event wiring is centralised so arena detection, saved-variable initialization, and logout handling all share the same dispatcher.
- The addon uses Blizzard-provided UI frames only; no external libraries are required. If `LibSerialize` is present it can assist, but the addon generates its own JSON payloads as a fallback.

