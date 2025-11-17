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
local ratingUpdateTimer = nil
local lastRatingSnapshot = nil
local matchStartTime = nil

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
        f:SetSize(800, 600)
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
        f.edit:SetSize(760, 500)
        f.edit:SetPoint("TOP", 0, -40)
        f.edit:SetAutoFocus(true)
        f.edit:HighlightText()
        f.edit:SetFontObject("ChatFontNormal")
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

-- Rating/MMR Tracking Functions
local function GetArenaRatingInfo()
    -- GetPersonalRatedInfo(bracketIndex) - 1=2v2, 2=3v3, 3=RBG
    -- Returns: rating, seasonBest, weeklyBest, seasonPlayed, seasonWon, weeklyPlayed, weeklyWon, cap
    local rating2v2 = 0
    local rating3v3 = 0
    local ok2v2, rating2v2_result = pcall(function()
        local r = GetPersonalRatedInfo(1)
        return r
    end)
    if ok2v2 and rating2v2_result then
        rating2v2 = rating2v2_result
    end
    local ok3v3, rating3v3_result = pcall(function()
        local r = GetPersonalRatedInfo(2)
        return r
    end)
    if ok3v3 and rating3v3_result then
        rating3v3 = rating3v3_result
    end
    -- Determine which bracket we're in based on party size
    local numMembers = GetNumGroupMembers()
    local bracketIndex = (numMembers and numMembers >= 3) and 2 or 1
    local currentRating = (bracketIndex == 2) and rating3v3 or rating2v2
    return currentRating, bracketIndex, rating2v2, rating3v3
end

local function GetArenaMMRInfo()
    -- GetBattlefieldTeamInfo(teamIndex) - 0=player team, 1=enemy team
    -- Returns: teamName, oldTeamRating, newTeamRating, teamRating
    local playerMMR = nil
    local enemyMMR = nil
    local ok1, teamName1, oldRating1, newRating1, teamRating1 = pcall(GetBattlefieldTeamInfo, 0)
    if ok1 and teamRating1 then
        playerMMR = teamRating1
    end
    local ok2, teamName2, oldRating2, newRating2, teamRating2 = pcall(GetBattlefieldTeamInfo, 1)
    if ok2 and teamRating2 then
        enemyMMR = teamRating2
    end
    return playerMMR, enemyMMR
end

local function UpdateRatingSnapshot()
    if not currentMatch or not inArena then
        return
    end
    
    local rating, bracketIndex, rating2v2, rating3v3 = GetArenaRatingInfo()
    local playerMMR, enemyMMR = GetArenaMMRInfo()
    
    -- Set initial values if not set
    if not currentMatch.ratingStart then
        currentMatch.ratingStart = rating
        currentMatch.mmrStart = playerMMR
        currentMatch.bracketIndex = bracketIndex
        currentMatch.rating2v2Start = rating2v2
        currentMatch.rating3v3Start = rating3v3
    end
    
    -- Always update end values
    currentMatch.ratingEnd = rating
    currentMatch.mmrEnd = playerMMR
    currentMatch.rating2v2End = rating2v2
    currentMatch.rating3v3End = rating3v3
    
    -- Check if rating changed since last snapshot
    local changed = false
    if not lastRatingSnapshot then
        changed = true
    elseif lastRatingSnapshot.rating ~= rating or lastRatingSnapshot.mmr ~= playerMMR then
        changed = true
    end
    
    if changed then
        local relativeTime = matchStartTime and (GetTime() - matchStartTime) or 0
        table.insert(currentMatch.ratingHistory, {
            timestamp = relativeTime,
            rating = rating,
            mmr = playerMMR,
            rating2v2 = rating2v2,
            rating3v3 = rating3v3
        })
        lastRatingSnapshot = {
            rating = rating,
            mmr = playerMMR
        }
    end
end

-- Combat Log Event Processing
local function ProcessCombatLogEvent()
    if not inArena or not currentMatch then
        return
    end
    
    local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID, destName, destFlags, destRaidFlags,
          spellId, spellName, spellSchool,
          amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand = CombatLogGetCurrentEventInfo()
    
    -- Calculate relative time since match start (high precision)
    local relativeTime = matchStartTime and (GetTime() - matchStartTime) or 0
    
    -- Create event record
    local eventRecord = {
        timestamp = relativeTime,
        eventType = subevent,
        sourceGUID = sourceGUID or "",
        sourceName = sourceName or "",
        destGUID = destGUID or "",
        destName = destName or "",
        spellId = spellId or 0,
        spellName = spellName or "",
        amount = amount or 0
    }
    
    -- Add additional fields based on event type
    if subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "RANGE_DAMAGE" or subevent == "SWING_DAMAGE" then
        eventRecord.overkill = overkill or 0
        eventRecord.school = school or 0
        eventRecord.resisted = resisted or 0
        eventRecord.blocked = blocked or 0
        eventRecord.absorbed = absorbed or 0
        eventRecord.critical = critical or false
        eventRecord.glancing = glancing or false
        eventRecord.crushing = crushing or false
    elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        eventRecord.overheal = overkill or 0 -- overkill field is used for overheal in heal events
        eventRecord.critical = critical or false
    elseif subevent == "SPELL_INTERRUPT" then
        eventRecord.extraSpellId = spellId or 0
        eventRecord.extraSpellName = spellName or ""
    end
    
    -- Store event
    table.insert(currentMatch.events, eventRecord)
    
    -- Update statistics
    local stats = currentMatch.statistics
    
    -- Count events by type
    stats.eventsByType[subevent] = (stats.eventsByType[subevent] or 0) + 1
    
    -- Track damage
    if subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "RANGE_DAMAGE" or subevent == "SWING_DAMAGE" then
        local dmg = amount or 0
        stats.totalDamage = stats.totalDamage + dmg
        if sourceGUID then
            stats.damageByPlayer[sourceGUID] = (stats.damageByPlayer[sourceGUID] or 0) + dmg
        end
    end
    
    -- Track healing
    if subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        local heal = amount or 0
        stats.totalHealing = stats.totalHealing + heal
        if sourceGUID then
            stats.healingByPlayer[sourceGUID] = (stats.healingByPlayer[sourceGUID] or 0) + heal
        end
    end
    
    -- Track interrupts
    if subevent == "SPELL_INTERRUPT" then
        stats.totalInterrupts = stats.totalInterrupts + 1
        if sourceGUID then
            stats.interruptsByPlayer[sourceGUID] = (stats.interruptsByPlayer[sourceGUID] or 0) + 1
        end
    end
end

-- Rating update timer callback
local function OnRatingUpdateTimer()
    if inArena and currentMatch then
        UpdateRatingSnapshot()
    else
        -- Stop timer if not in arena
        if ratingUpdateTimer then
            ratingUpdateTimer:Cancel()
            ratingUpdateTimer = nil
        end
    end
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
    matchStartTime = GetTime() -- High precision time for relative event timestamps

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
        matchHash = nil,
        -- Rating/MMR tracking
        ratingStart = nil,
        ratingEnd = nil,
        mmrStart = nil,
        mmrEnd = nil,
        bracketIndex = nil,
        rating2v2Start = nil,
        rating2v2End = nil,
        rating3v3Start = nil,
        rating3v3End = nil,
        ratingHistory = {},
        -- Combat log events
        events = {},
        -- Statistics
        statistics = {
            totalDamage = 0,
            totalHealing = 0,
            totalInterrupts = 0,
            damageByPlayer = {},
            healingByPlayer = {},
            interruptsByPlayer = {},
            eventsByType = {}
        }
    }
    
    -- Initialize rating snapshot
    lastRatingSnapshot = nil
    UpdateRatingSnapshot()
    
    -- Start periodic rating updates (every 5 seconds)
    if ratingUpdateTimer then
        ratingUpdateTimer:Cancel()
    end
    ratingUpdateTimer = C_Timer.NewTicker(5, OnRatingUpdateTimer)
    
    print("PvPLog: Detected arena entry on " .. tostring(map) .. ". Recording combat log events and rating changes.")
end

-- When leaving arena: finalize match
local function OnLeaveArena()
    if not inArena then return end
    inArena = false

    -- Stop rating update timer
    if ratingUpdateTimer then
        ratingUpdateTimer:Cancel()
        ratingUpdateTimer = nil
    end

    if not currentMatch then
        return
    end

    -- Final rating snapshot
    UpdateRatingSnapshot()
    
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
        local eventCount = #currentMatch.events
        local ratingChange = (currentMatch.ratingEnd or 0) - (currentMatch.ratingStart or 0)
        print("PvPLog: Saved match #" .. tostring(newId) .. " (" .. tostring(currentMatch.duration) .. " sec, " .. tostring(eventCount) .. " events, rating: " .. tostring(ratingChange) .. "). Use /pvplogs to list or /pvpexport " .. tostring(newId) .. " to copy JSON.")
    end

    -- clear current
    currentMatch = nil
    lastRatingSnapshot = nil
    matchStartTime = nil
end

local addonInitialized = false

local function EnsureInitialized()
    if addonInitialized then
        return
    end
    InitDB()
    addonInitialized = true
end

PvPLog:RegisterEvent("ADDON_LOADED")
PvPLog:RegisterEvent("PLAYER_ENTERING_WORLD")
PvPLog:RegisterEvent("ZONE_CHANGED_NEW_AREA")
PvPLog:RegisterEvent("PLAYER_LOGOUT")
PvPLog:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
PvPLog:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
PvPLog:RegisterEvent("ARENA_OPPONENT_UPDATE")
PvPLog:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")

PvPLog:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= addonName then
            return
        end
        EnsureInitialized()
        print("PvPLog loaded. Use /pvplogs to list saved matches. Settings: autoEnablePrompt =", tostring(PvPLogDB.settings.autoEnablePrompt))
        -- check if already in arena at load
        local inInstance, instanceType = IsInInstance()
        if inInstance and (instanceType == "arena" or instanceType == "pvp") then
            OnEnterArena()
        end
        return
    end

    if not addonInitialized then
        EnsureInitialized()
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        -- check instance type
        local inInstance, instanceType = IsInInstance()
        if inInstance and (instanceType == "arena" or instanceType == "pvp") then
            OnEnterArena()
        elseif inArena then
            OnLeaveArena()
        end
    elseif event == "PLAYER_LOGOUT" then
        -- ensure we save end if user logs out in arena
        if inArena then
            OnLeaveArena()
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Process all combat log events
        ProcessCombatLogEvent()
    elseif event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" or event == "ARENA_OPPONENT_UPDATE" or event == "UPDATE_BATTLEFIELD_STATUS" then
        -- Update rating snapshot on arena-related events
        if inArena and currentMatch then
            UpdateRatingSnapshot()
        end
    end
end)

-- JSON Serialization Helper
local function EscapeJsonString(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("\\", "\\\\")
    str = str:gsub('"', '\\"')
    str = str:gsub("\n", "\\n")
    str = str:gsub("\r", "\\r")
    str = str:gsub("\t", "\\t")
    return str
end

local function SerializeToJson(value, indent)
    indent = indent or 0
    local indentStr = string.rep("  ", indent)
    local nextIndent = indent + 1
    local nextIndentStr = string.rep("  ", nextIndent)
    
    if type(value) == "table" then
        -- Check if it's an array (sequential numeric indices)
        local isArray = true
        local maxIndex = 0
        local count = 0
        for k, v in pairs(value) do
            count = count + 1
            if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
                isArray = false
                break
            end
            if k > maxIndex then
                maxIndex = k
            end
        end
        
        if isArray and maxIndex == count then
            -- It's an array
            if maxIndex == 0 then
                return "[]"
            end
            local parts = {}
            for i = 1, maxIndex do
                table.insert(parts, SerializeToJson(value[i], nextIndent))
            end
            return "[\n" .. nextIndentStr .. table.concat(parts, ",\n" .. nextIndentStr) .. "\n" .. indentStr .. "]"
        else
            -- It's an object
            local parts = {}
            for k, v in pairs(value) do
                local key = EscapeJsonString(tostring(k))
                local val = SerializeToJson(v, nextIndent)
                table.insert(parts, '"' .. key .. '": ' .. val)
            end
            if #parts == 0 then
                return "{}"
            end
            return "{\n" .. nextIndentStr .. table.concat(parts, ",\n" .. nextIndentStr) .. "\n" .. indentStr .. "}"
        end
    elseif type(value) == "string" then
        return '"' .. EscapeJsonString(value) .. '"'
    elseif type(value) == "number" then
        return tostring(value)
    elseif type(value) == "boolean" then
        return value and "true" or "false"
    elseif value == nil then
        return "null"
    else
        return '"' .. EscapeJsonString(tostring(value)) .. '"'
    end
end

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
            local ratingInfo = ""
            if m.ratingStart and m.ratingEnd then
                local change = m.ratingEnd - m.ratingStart
                local changeStr = change >= 0 and ("+" .. tostring(change)) or tostring(change)
                ratingInfo = string.format(" rating:%d->%d (%s)", m.ratingStart, m.ratingEnd, changeStr)
            end
            local eventCount = m.events and #m.events or 0
            print(string.format("  id=%d  map=%s  mode=%s  start=%s  dur=%ds  events=%d%s  hash=%s",
                m.id, tostring(m.map), tostring(m.mode),
                date("%Y-%m-%d %H:%M:%S", m.startedAt), m.duration or 0, eventCount, ratingInfo, m.matchHash or ""))
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
            -- Serialize entire match data to JSON
            local jsonText = SerializeToJson(found)
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
            -- Serialize entire match data to JSON
            local jsonText = SerializeToJson(m)
            ShowExportDialog(jsonText)
            return
        end
    end
    print("PvPLog: match not found")
end
