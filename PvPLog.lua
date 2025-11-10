-- PvPLog.lua
-- Minimal addon: mark arena match start/end, suggest enabling /combatlog, save minimal metadata
-- SavedVariables: PvPLogDB

local addonName = ...
local PvPLog = CreateFrame("Frame", "PvPLogFrame")

-- SavedVariables container name: PvPLogDB (declared automatically by WoW when file is loaded)
-- Structure: PvPLogDB = { settings = { autoEnablePrompt = true }, matches = { { id=..., hash=..., map=..., mode=..., startedAt=..., endedAt=..., players = {...} }, ... } }

-- Helper: ensure DB
local function InitDB()
    if not PvPLogDB then
        PvPLogDB = {}
    end
    if not PvPLogDB.settings then
        PvPLogDB.settings = { autoEnablePrompt = false } -- default: don't auto-enable prompts
    end
    if not PvPLogDB.matches then
        PvPLogDB.matches = {}
    end
end

-- Utility: simple hashing for uniqueness (xor + tostring)
local function simpleHash(str)
    -- fallback simple hash (not cryptographic) to detect duplicates
    local h = 2166136261
    for i = 1, #str do
        h = (h ~ string.byte(str, i)) * 16777619
        -- keep it in 32-bit range
        h = h & 0xFFFFFFFF
    end
    return string.format("%08x", h)
end

-- State
local inArena = false
local recording = false
local currentMatch = nil

-- UI: popup frame (simple)
local function ShowPromptEnableCombatLog()
    if StaticPopupDialogs["PVPLOG_ENABLE_COMBATLOG"] == nil then
        StaticPopupDialogs["PVPLOG_ENABLE_COMBATLOG"] = {
            text = "PvPLog: You have entered an arena. To record the full combat log, please enable combat logging. Click 'Open Chat' to put the command in chat and press Enter to enable. Enable automatic prompts for future arenas?",
            button1 = "Open Chat",
            button2 = "Cancel",
            button3 = "Toggle Auto",
            OnAccept = function()
                -- open chat with command prefilled; user must press Enter
                ChatFrame_OpenChat("/combatlog")
            end,
            OnAlt = function()
                -- toggle auto setting
                PvPLogDB.settings.autoEnablePrompt = not PvPLogDB.settings.autoEnablePrompt
                local enabled = PvPLogDB.settings.autoEnablePrompt and "enabled" or "disabled"
                print("PvPLog: Auto prompt " .. enabled)
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show("PVPLOG_ENABLE_COMBATLOG")
end

-- Create export popup dialog on demand (copyable textbox)
local function ShowExportDialog(text)
    if not PvPLogExportFrame then
        local f = CreateFrame("Frame", "PvPLogExportFrame", UIParent, "DialogBoxFrame")
        f:SetSize(600, 300)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -12)
        f.title:SetText("PvPLog: Export match JSON (copy manually)")

        f.edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.edit:SetMultiLine(true)
        f.edit:SetSize(560, 200)
        f.edit:SetPoint("TOP", 0, -40)
        f.edit:SetAutoFocus(true)
        f.edit:HighlightText()
        f:Hide()
        PvPLogExportFrame = f
    end

    PvPLogExportFrame.edit:SetText(text)
    PvPLogExportFrame:Show()
    PvPLogExportFrame.edit:SetFocus(true)
    PvPLogExportFrame.edit:HighlightText()
end

-- Helpers to collect players: gather party/raid and opponents if available
local function CollectPlayers()
    local players = {}
    -- add local player
    local pname = UnitName("player")
    local realm = GetRealmName()
    table.insert(players, { name = pname, realm = realm, role = nil, guid = UnitGUID("player") })

    -- party members (arena usually is party-based)
    local num = GetNumGroupMembers()
    if num and num > 0 then
        -- iterate party (for arena 3v3, party1..party2)
        local unitPrefix = IsInRaid() and "raid" or "party"
        for i = 1, num - 1 do
            local unit = unitPrefix .. i
            if UnitExists(unit) then
                local name = UnitName(unit)
                local guid = UnitGUID(unit)
                table.insert(players, { name = name, realm = realm, role = nil, guid = guid })
            end
        end
    end

    -- Opponents: attempt to read arena opponents if available
    -- GetNumArenaOpponents exists in many clients; guard with pcall
    local ok, arenaCount = pcall(GetNumArenaOpponents)
    if ok and arenaCount and arenaCount > 0 then
        for i = 1, arenaCount do
            local unit = "arena" .. i
            if UnitExists(unit) then
                local name = UnitName(unit)
                local guid = UnitGUID(unit)
                table.insert(players, { name = name, realm = nil, role = nil, guid = guid })
            end
        end
    end

    return players
end

-- Compute match unique hash from metadata
local function ComputeMatchHash(map, mode, startedAt, players)
    local s = map .. "|" .. tostring(mode) .. "|" .. tostring(startedAt)
    for _, p in ipairs(players) do
        s = s .. "|" .. tostring(p.name) .. ":" .. tostring(p.guid or "")
    end
    return simpleHash(s)
end

-- When entering arena: show prompt or auto prompt
local function OnEnterArena()
    -- if already recording, skip
    if inArena then return end
    inArena = true

    -- collect context
    local map = GetZoneText() or "Unknown"
    local mode = "Arena"
    local players = CollectPlayers()
    local startedAt = time()

    -- If auto prompt is enabled, open chat with command
    if PvPLogDB.settings.autoEnablePrompt then
        ChatFrame_OpenChat("/combatlog")
    else
        -- show manual prompt
        ShowPromptEnableCombatLog()
    end

    -- prepare currentMatch skeleton to be completed at exit
    currentMatch = {
        id = nil, -- set when persisted
        map = map,
        mode = mode,
        startedAt = startedAt,
        endedAt = nil,
        players = players,
        matchHash = nil
    }
    print("PvPLog: Detected arena entry on " .. tostring(map) .. ". You can enable combatlog to record details.")
end

-- When leaving arena: finalize match
local function OnLeaveArena()
    if not inArena then return end
    inArena = false

    if not currentMatch then
        return
    end

    currentMatch.endedAt = time()
    currentMatch.duration = currentMatch.endedAt - currentMatch.startedAt
    currentMatch.matchHash = ComputeMatchHash(currentMatch.map, currentMatch.mode, currentMatch.startedAt, currentMatch.players)

    -- Check duplicates
    local duplicate = nil
    for _, m in ipairs(PvPLogDB.matches) do
        if m.matchHash == currentMatch.matchHash then
            duplicate = m
            break
        end
    end

    if duplicate then
        print("PvPLog: Match already exists in DB (duplicate detected).")
        -- Optionally merge missing players if any
        -- For simplicity: do nothing, but we could add missing MatchResults on server side
    else
        -- assign id (incremental)
        local newId = (#PvPLogDB.matches) + 1
        currentMatch.id = newId
        table.insert(PvPLogDB.matches, currentMatch)
        print("PvPLog: Saved match #" .. tostring(newId) .. " (" .. tostring(currentMatch.duration) .. " sec). Use /pvplogs to list or /pvpexport " .. tostring(newId) .. " to copy JSON.")
    end

    -- clear current
    currentMatch = nil
end

-- Event handling: monitor instance type transitions
PvPLog:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        -- check instance type
        local inInstance, instanceType = IsInInstance()
        if inInstance and (instanceType == "arena" or instanceType == "pvp") then
            OnEnterArena()
        else
            -- leaving arena
            if inArena then
                OnLeaveArena()
            end
        end
    elseif event == "PLAYER_LOGOUT" then
        -- ensure we save end if user logs out in arena
        if inArena then
            OnLeaveArena()
        end
    end
end)

-- Register events
PvPLog:RegisterEvent("PLAYER_ENTERING_WORLD")
PvPLog:RegisterEvent("ZONE_CHANGED_NEW_AREA")
PvPLog:RegisterEvent("PLAYER_LOGOUT")

-- Slash commands
SLASH_PVPLOG1 = "/pvplogs"
SlashCmdList["PVPLOG"] = function(msg)
    msg = msg and msg:trim() or ""
    if msg == "" then
        -- list matches
        if not PvPLogDB or #PvPLogDB.matches == 0 then
            print("PvPLog: No matches saved.")
            return
        end
        print("PvPLog: Saved matches:")
        for _, m in ipairs(PvPLogDB.matches) do
            print(string.format("  id=%d  map=%s  mode=%s  start=%s  dur=%ds  hash=%s",
                m.id, tostring(m.map), tostring(m.mode),
                date("%Y-%m-%d %H:%M:%S", m.startedAt), m.duration or 0, m.matchHash or ""))
        end
        print("Use /pvpexport <id> to show JSON for a match.")
    else
        -- try to export single
        local cmd, arg = msg:match("^(%S+)%s*(.-)$")
        if cmd == "export" and arg ~= "" then
            local id = tonumber(arg)
            if not id then
                print("PvPLog: invalid id")
                return
            end
            local found = nil
            for _, m in ipairs(PvPLogDB.matches) do
                if m.id == id then found = m; break end
            end
            if not found then
                print("PvPLog: match not found")
                return
            end
            local ok, json = pcall(function() return LibSerialize and LibSerialize:Serialize(found) end)
            -- We don't rely on LibSerialize. Build a simple JSON manually.
            local export = {}
            export.id = found.id
            export.map = found.map
            export.mode = found.mode
            export.startedAt = found.startedAt
            export.endedAt = found.endedAt
            export.duration = found.duration
            export.matchHash = found.matchHash
            export.players = found.players
            -- convert to JSON (simple)
            local function simple_serialize_table(t)
                local s = "{"
                local first = true
                for k, v in pairs(t) do
                    if not first then s = s .. "," end
                    first = false
                    local key = tostring(k)
                    if type(v) == "table" then
                        s = s .. '"'..key..'":'..simple_serialize_table(v)
                    elseif type(v) == "string" then
                        s = s .. '"'..key..'":"'..v..'"'
                    else
                        s = s .. '"'..key..'":'..tostring(v)
                    end
                end
                s = s .. "}"
                return s
            end
            -- build players array
            local playersJson = "["
            for i,p in ipairs(found.players) do
                if i>1 then playersJson = playersJson .. "," end
                playersJson = playersJson .. string.format('{"name":"%s","realm":"%s","guid":"%s"}',
                    tostring(p.name or ""), tostring(p.realm or ""), tostring(p.guid or ""))
            end
            playersJson = playersJson .. "]"

            local jsonText = string.format('{"id":%d,"map":"%s","mode":"%s","startedAt":%d,"endedAt":%d,"duration":%d,"matchHash":"%s","players":%s}',
                export.id, tostring(export.map or ""), tostring(export.mode or ""), export.startedAt or 0, export.endedAt or 0, export.duration or 0, tostring(export.matchHash or ""), playersJson)

            ShowExportDialog(jsonText)
        else
            print("PvPLog: unknown command. Usage: /pvplogs or /pvplogs export <id>")
        end
    end
end

SLASH_PVPEXPORT1 = "/pvpexport"
SlashCmdList["PVPEXPORT"] = function(msg)
    local id = tonumber(msg)
    if not id then
        print("PvPLog: usage /pvpexport <id>")
        return
    end
    for _, m in ipairs(PvPLogDB.matches) do
        if m.id == id then
            local jsonText = string.format('{"id":%d,"map":"%s","mode":"%s","startedAt":%d,"endedAt":%d,"duration":%d,"matchHash":"%s","players":%s}',
                m.id, tostring(m.map or ""), tostring(m.mode or ""), m.startedAt or 0, m.endedAt or 0, m.duration or 0, tostring(m.matchHash or ""), "[]")
            ShowExportDialog(jsonText)
            return
        end
    end
    print("PvPLog: match not found")
end

-- Ensure DB init on addon loaded
PvPLog:RegisterEvent("ADDON_LOADED")
PvPLog:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == "PvPLog" then
        InitDB()
        print("PvPLog loaded. Use /pvplogs to list saved matches. Settings: autoEnablePrompt =", tostring(PvPLogDB.settings.autoEnablePrompt))
        -- check if already in arena at load
        local inInstance, instanceType = IsInInstance()
        if inInstance and (instanceType == "arena" or instanceType == "pvp") then
            OnEnterArena()
        end
    end
end)
