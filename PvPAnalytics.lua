local addonName, addon = ...

-- Global Object for SavedVariables
PvPAnalytics = LibStub and LibStub("AceAddon-3.0"):NewAddon("PvPAnalytics", "AceConsole-3.0", "AceEvent-3.0") or {}
local Frame = CreateFrame("Frame")

-- Current Match State
addon.CurrentMatch = nil
addon.IsRecording = false

function Frame:OnLoad()
    Frame:RegisterEvent("PLAYER_LOGIN")
    Frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    Frame:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
    Frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    print("|cff00ff00[PvPAnalytics]|r Loaded. Waiting for Arena...")
end

function Frame:OnEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        if not PvPAnalyticsDB then PvPAnalyticsDB = { matches = {} } end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        addon:CheckZone()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" and addon.IsRecording then
        addon:ProcessCombatLog()
    end
end

function addon:CheckZone()
    local _, instanceType = IsInInstance()
    if instanceType == "arena" or instanceType == "pvp" then
        if not addon.IsRecording then
            addon:StartMatch()
        end
    else
        if addon.IsRecording then
            addon:EndMatch()
        end
    end
end

function addon:StartMatch()
    addon.IsRecording = true
    local mapName = GetZoneText()
    local timestamp = date("%Y-%m-%d %H:%M:%S")

    -- Initialize the Match Data Structure
    addon.CurrentMatch = {
        metadata = {
            id = GetTime(), -- Unique ID
            date = timestamp,
            map = mapName,
            duration = 0,
            winner = nil
        },
        players = {}, -- Helper to store name/class info
        events = {},  -- For the Timeline (CC, Deaths, CDs, CC Chains, Trinkets, Big Buttons)
        stats = {
            damage = {},
            healing = {},
            absorbs = {},
            interrupts = {},
            ccChains = {},
            trinketUsage = {},
            bigButtonUsage = {}
        }
    }
    
    -- Reset CC chain tracking (if CombatLog module is loaded)
    if addon.ResetCCTracking then
        addon:ResetCCTracking()
    end
    
    print("|cff00ff00[PvPAnalytics]|r Match Started: " .. mapName)
end

function addon:EndMatch()
    addon.IsRecording = false
    if addon.CurrentMatch then
        -- Save to DB
        table.insert(PvPAnalyticsDB.matches, addon.CurrentMatch)
        print("|cff00ff00[PvPAnalytics]|r Match Ended & Saved.")
        addon.CurrentMatch = nil
    end
    
    -- Reset CC chain tracking
    if addon.ResetCCTracking then
        addon:ResetCCTracking()
    end
end

-- --- SLASH COMMANDS ---
SLASH_PVPANALYTICS1 = "/pvpdata"
SlashCmdList["PVPANALYTICS"] = function(msg)
    if msg == "clear" then
        PvPAnalyticsDB.matches = {}
        print("PvPAnalytics Data Cleared.")
    else
        print("Stored Matches: " .. (#PvPAnalyticsDB.matches or 0))
    end
end

Frame:SetScript("OnEvent", Frame.OnEvent)
Frame:OnLoad()