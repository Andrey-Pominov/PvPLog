PvPAnalyticsDB = PvPAnalyticsDB or {}

local frame = CreateFrame("Frame")
local currentMatch = nil

-- Helper for adding log lines
local function AddLogLine(match, line)
    table.insert(match.Logs, date("%H:%M:%S") .. " - " .. line)
end

-- Get player class and spec info
local function GetPlayerClassSpec(unit)
    local className, classId = nil, nil
    local specName, specId = nil, nil
    
    if UnitExists(unit) then
        local ok, class, id = pcall(UnitClass, unit)
        if ok and class then
            className = class
            classId = id
        end
    end
    
    if unit == "player" then
        local specIndex = GetSpecialization()
        if specIndex then
            local ok, name, desc, icon, role, classFile, id = pcall(GetSpecializationInfo, specIndex)
            if ok and name then
                specName = name
                specId = id
            end
        end
    else
        local ok, specIdResult = pcall(GetInspectSpecialization, unit)
        if ok and specIdResult and specIdResult > 0 then
            specId = specIdResult
            local ok2, name, desc, icon, role, classFile, id = pcall(GetSpecializationInfoByID, specIdResult)
            if ok2 and name then
                specName = name
            end
        end
    end
    
    return className, classId, specName, specId
end

-- Get arena opponent spec
local function GetArenaOpponentSpecInfo(index)
    local specName, specId = nil, nil
    local ok, specIdResult = pcall(GetArenaOpponentSpec, index)
    if ok and specIdResult and specIdResult > 0 then
        specId = specIdResult
        local ok2, name, desc, icon, role, classFile, id = pcall(GetSpecializationInfoByID, specIdResult)
        if ok2 and name then
            specName = name
        end
    end
    return specName, specId
end

-- Collect all players in the match
local function CollectPlayers()
    local players = {}
    local realm = GetRealmName()
    local faction = UnitFactionGroup("player") or "Unknown"
    
    -- Add local player
    local pname = UnitName("player")
    local className, classId, specName, specId = GetPlayerClassSpec("player")
    table.insert(players, {
        name = pname,
        realm = realm,
        guid = UnitGUID("player"),
        class = className or "Unknown",
        classId = classId or 0,
        spec = specName or "Unknown",
        specId = specId or 0,
        faction = faction,
        isPlayer = true
    })
    
    -- Party members
    local num = GetNumGroupMembers()
    if num and num > 0 then
        local unitPrefix = IsInRaid() and "raid" or "party"
        for i = 1, num - 1 do
            local unit = unitPrefix .. i
            if UnitExists(unit) then
                local name = UnitName(unit)
                local guid = UnitGUID(unit)
                local className, classId, specName, specId = GetPlayerClassSpec(unit)
                table.insert(players, {
                    name = name,
                    realm = realm,
                    guid = guid,
                    class = className or "Unknown",
                    classId = classId or 0,
                    spec = specName or "Unknown",
                    specId = specId or 0,
                    faction = faction,
                    isPlayer = true
                })
            end
        end
    end
    
    -- Opponents
    local ok, arenaCount = pcall(GetNumArenaOpponents)
    if ok and arenaCount and arenaCount > 0 then
        local enemyFaction = (faction == "Alliance") and "Horde" or "Alliance"
        for i = 1, arenaCount do
            local unit = "arena" .. i
            if UnitExists(unit) then
                local name = UnitName(unit)
                local guid = UnitGUID(unit)
                local className, classId = nil, nil
                local specName, specId = nil, nil
                
                local ok2, class, id = pcall(UnitClass, unit)
                if ok2 and class then
                    className = class
                    classId = id
                end
                
                specName, specId = GetArenaOpponentSpecInfo(i)
                
                if not specId then
                    local ok3, specIdResult = pcall(GetInspectSpecialization, unit)
                    if ok3 and specIdResult and specIdResult > 0 then
                        specId = specIdResult
                        local ok4, name, desc, icon, role, classFile, id = pcall(GetSpecializationInfoByID, specIdResult)
                        if ok4 and name then
                            specName = name
                        end
                    end
                end
                
                table.insert(players, {
                    name = name,
                    realm = nil,
                    guid = guid,
                    class = className or "Unknown",
                    classId = classId or 0,
                    spec = specName or "Unknown",
                    specId = specId or 0,
                    faction = enemyFaction,
                    isPlayer = false
                })
            end
        end
    end
    
    return players
end

-- Detect arena mode (2v2, 3v3, shuffle)
local function DetectArenaMode()
    local numMembers = GetNumGroupMembers()
    local totalPlayers = numMembers and (numMembers) or 1
    
    -- Check if it's Solo Shuffle (6 players in party/raid, or check for shuffle-specific indicators)
    -- Solo Shuffle typically has 6 players total (you + 5 others)
    if totalPlayers >= 6 then
        return "Solo Shuffle"
    elseif totalPlayers >= 3 then
        return "3v3"
    elseif totalPlayers >= 2 then
        return "2v2"
    else
        return "1v1"
    end
end

-- Handles arena start/finish
local function TryStartOrFinishMatch()
    local isInside, instanceType = IsInInstance()

    if isInside and (instanceType == "arena" or instanceType == "pvp") then
        if not currentMatch then
            local zone = GetZoneText() or GetRealZoneText() or "Unknown"
            local mode = DetectArenaMode()
            local players = CollectPlayers()
            local faction = UnitFactionGroup("player") or "Unknown"
            
            currentMatch = {
                StartTime = date("%Y-%m-%d %H:%M:%S"),
                Zone = zone,
                Mode = mode,
                Faction = faction,
                Players = players,
                Logs = {},
                Statistics = {
                    totalDamage = 0,
                    totalHealing = 0,
                    totalInterrupts = 0,
                    totalCrits = 0,
                    damageByPlayer = {},
                    healingByPlayer = {},
                    interruptsByPlayer = {},
                    critsByPlayer = {}
                }
            }
            print("|cff00ff00[PvPAnalytics]|r Arena match started - " .. zone .. " (" .. mode .. ")")
        end
    else
        if currentMatch then
            currentMatch.EndTime = date("%Y-%m-%d %H:%M:%S")
            table.insert(PvPAnalyticsDB, currentMatch)
            print("|cffffff00[PvPAnalytics]|r Match saved. Stats: " .. 
                  currentMatch.Statistics.totalInterrupts .. " interrupts, " ..
                  currentMatch.Statistics.totalCrits .. " crits")
            currentMatch = nil
        end
    end
end

-- Register events
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
frame:RegisterEvent("ARENA_OPPONENT_UPDATE")

frame:SetScript("OnEvent", function(_, event)
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        TryStartOrFinishMatch()
        return
    end

    -- Update player info when arena opponent specs become available
    if (event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" or event == "ARENA_OPPONENT_UPDATE") and currentMatch then
        -- Refresh player list to get updated spec info
        currentMatch.Players = CollectPlayers()
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" and currentMatch then
        local timestamp, subEvent, _, srcGUID, srcName, srcFlags, srcRaidFlags,
              dstGUID, dstName, dstFlags, dstRaidFlags,
              spellId, spellName, spellSchool,
              amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand =
              CombatLogGetCurrentEventInfo()

        local stats = currentMatch.Statistics
        local isCrit = critical or false

        -- Damage events
        if subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_PERIODIC_DAMAGE" or 
           subEvent == "RANGE_DAMAGE" or subEvent == "SWING_DAMAGE" then
            local dmg = amount or 0
            stats.totalDamage = stats.totalDamage + dmg
            
            if srcGUID then
                stats.damageByPlayer[srcGUID] = (stats.damageByPlayer[srcGUID] or 0) + dmg
            end
            
            local critStr = isCrit and " |cffff0000[CRIT]|r" or ""
            AddLogLine(currentMatch,
                string.format("DAMAGE: %s used %s for %d on %s%s",
                srcName or "Unknown",
                spellName or "Spell",
                dmg,
                dstName or "Unknown",
                critStr))
            
            if isCrit then
                stats.totalCrits = stats.totalCrits + 1
                if srcGUID then
                    stats.critsByPlayer[srcGUID] = (stats.critsByPlayer[srcGUID] or 0) + 1
                end
            end
        end

        -- Healing events
        if subEvent == "SPELL_HEAL" or subEvent == "SPELL_PERIODIC_HEAL" then
            local heal = amount or 0
            stats.totalHealing = stats.totalHealing + heal
            
            if srcGUID then
                stats.healingByPlayer[srcGUID] = (stats.healingByPlayer[srcGUID] or 0) + heal
            end
            
            local critStr = isCrit and " |cff00ff00[CRIT]|r" or ""
            AddLogLine(currentMatch,
                string.format("HEAL: %s healed with %s for %d%s",
                srcName or "Unknown",
                spellName or "Spell",
                heal,
                critStr))
            
            if isCrit then
                stats.totalCrits = stats.totalCrits + 1
                if srcGUID then
                    stats.critsByPlayer[srcGUID] = (stats.critsByPlayer[srcGUID] or 0) + 1
                end
            end
        end

        -- Interrupt events
        if subEvent == "SPELL_INTERRUPT" then
            stats.totalInterrupts = stats.totalInterrupts + 1
            
            if srcGUID then
                stats.interruptsByPlayer[srcGUID] = (stats.interruptsByPlayer[srcGUID] or 0) + 1
            end
            
            -- In SPELL_INTERRUPT, spellId/spellName is the interrupted spell
            local interruptedSpellName = spellName or "Spell"
            
            AddLogLine(currentMatch,
                string.format("|cffff8800INTERRUPT:|r %s interrupted %s's %s",
                srcName or "Unknown",
                dstName or "Unknown",
                interruptedSpellName))
        end
    end
end)

-- Slash command
SLASH_PVPANALYTICS1 = "/pvpdata"
SlashCmdList["PVPANALYTICS"] = function(msg)
    msg = msg and msg:match("^%s*(.-)%s*$") or ""
    
    if msg == "" then
        -- List all matches
        print("|cff00ff00[PvPAnalytics]|r Stored matches: " .. #PvPAnalyticsDB)
        if #PvPAnalyticsDB > 0 then
            for i, match in ipairs(PvPAnalyticsDB) do
                local mode = match.Mode or "Unknown"
                local zone = match.Zone or "Unknown"
                local stats = match.Statistics or {}
                print(string.format("  Match #%d: %s (%s) - %d interrupts, %d crits, %d damage, %d healing",
                    i, zone, mode, 
                    stats.totalInterrupts or 0,
                    stats.totalCrits or 0,
                    stats.totalDamage or 0,
                    stats.totalHealing or 0))
            end
        end
    elseif msg:match("^info%s+%d+") then
        -- Show detailed match info
        local id = tonumber(msg:match("^info%s+(%d+)"))
        if id and id > 0 and id <= #PvPAnalyticsDB then
            local match = PvPAnalyticsDB[id]
            print("|cff00ff00[PvPAnalytics]|r Match #" .. id .. " Details:")
            print("  Zone: " .. (match.Zone or "Unknown"))
            print("  Mode: " .. (match.Mode or "Unknown"))
            print("  Faction: " .. (match.Faction or "Unknown"))
            print("  Start: " .. (match.StartTime or "Unknown"))
            print("  End: " .. (match.EndTime or "Unknown"))
            
            local stats = match.Statistics or {}
            print("  Statistics:")
            print("    Total Damage: " .. (stats.totalDamage or 0))
            print("    Total Healing: " .. (stats.totalHealing or 0))
            print("    Total Interrupts: " .. (stats.totalInterrupts or 0))
            print("    Total Crits: " .. (stats.totalCrits or 0))
            
            if match.Players and #match.Players > 0 then
                print("  Players (" .. #match.Players .. "):")
                for _, p in ipairs(match.Players) do
                    local team = p.isPlayer and "|cff00ff00[Team]|r" or "|cffff0000[Enemy]|r"
                    local info = string.format("    %s %s (%s %s) - %s",
                        team, p.name or "Unknown",
                        p.class or "Unknown", p.spec or "Unknown",
                        p.faction or "Unknown")
                    print(info)
                end
            end
        else
            print("|cffff0000[PvPAnalytics]|r Invalid match ID. Use /pvpdata info <number>")
        end
    else
        print("|cff00ff00[PvPAnalytics]|r Commands:")
        print("  /pvpdata - List all matches")
        print("  /pvpdata info <id> - Show detailed match information")
    end
end
