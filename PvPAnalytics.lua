local addonName, addon = ...

-- Global Object for SavedVariables - Constants.lua should have created this
PvPAnalytics = PvPAnalytics or {}
local Frame = CreateFrame("Frame")

-- Current Match State
PvPAnalytics.CurrentMatch = nil
PvPAnalytics.IsRecording = false

function Frame:OnLoad()
    Frame:RegisterEvent("PLAYER_LOGIN")
    Frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    Frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    Frame:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
    Frame:RegisterEvent("ARENA_OPPONENT_UPDATE")
    Frame:RegisterEvent("ARENA_MATCH_START")
    Frame:RegisterEvent("ARENA_MATCH_END")
    Frame:RegisterEvent("PVP_MATCH_COMPLETE")
    Frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    print("|cff00ff00[PvPAnalytics]|r Loaded. Waiting for Arena...")
end

function Frame:OnEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        -- Enhanced DBContext initialization (like ArenaAnalytics player profiles)
        if not PvPAnalyticsDB then 
            PvPAnalyticsDB = { 
                matches = {},  -- Existing match history
                players = {},  -- New: Player profiles (GUID-indexed)
                userProfile = {},  -- New: Main character's data
                settings = {}  -- New: User preferences
            } 
        end
        
        -- Ensure all DB tables exist (backward compatibility)
        if not PvPAnalyticsDB.matches then
            PvPAnalyticsDB.matches = {}
        end
        if not PvPAnalyticsDB.players then
            PvPAnalyticsDB.players = {}
        end
        if not PvPAnalyticsDB.userProfile then
            PvPAnalyticsDB.userProfile = {}
        end
        if not PvPAnalyticsDB.settings then
            PvPAnalyticsDB.settings = {
                trackCCChains = true,
                trackTrinkets = true,
                exportFormat = "json"
            }
        end
        
        -- Initialize or update user profile
        local playerGUID = UnitGUID("player")
        if playerGUID then
            if not PvPAnalyticsDB.userProfile.guid then
                PvPAnalyticsDB.userProfile.guid = playerGUID
                PvPAnalyticsDB.userProfile.name = UnitName("player")
                PvPAnalyticsDB.userProfile.realm = GetRealmName()
                PvPAnalyticsDB.userProfile.faction = UnitFactionGroup("player")
                PvPAnalyticsDB.userProfile.totalMatches = 0
                PvPAnalyticsDB.userProfile.totalWins = 0
                PvPAnalyticsDB.userProfile.totalLosses = 0
                PvPAnalyticsDB.userProfile.avgDamage = 0
                PvPAnalyticsDB.userProfile.avgHealing = 0
                PvPAnalyticsDB.userProfile.avgInterrupts = 0
                PvPAnalyticsDB.userProfile.favoriteMaps = {}
                PvPAnalyticsDB.userProfile.performanceTrends = {}
            end
        end
        
        -- Initialize addon after login
        PvPAnalytics:Initialize()
    elseif event == "PLAYER_ENTERING_WORLD" then
        PvPAnalytics:CheckZone()
    elseif event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" then
        PvPAnalytics:CacheOpponentSpecs()
    elseif event == "ARENA_OPPONENT_UPDATE" then
        PvPAnalytics:UpdateArenaOpponent(...)
    elseif event == "ARENA_MATCH_START" or event == "PVP_MATCH_START" then
        PvPAnalytics:StartMatch()
    elseif event == "PVP_MATCH_COMPLETE" or event == "ARENA_MATCH_END" then
        PvPAnalytics:EndMatch()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        PvPAnalytics:CheckZone()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" and PvPAnalytics.IsRecording then
        PvPAnalytics:ProcessCombatLog()
    end
end

function PvPAnalytics:Initialize()
    -- Initialize is called after PLAYER_LOGIN
    -- This ensures all modules are loaded
end

function PvPAnalytics:CheckZone()
    local _, instanceType = IsInInstance()
    if instanceType ~= "arena" and instanceType ~= "pvp" then
        if PvPAnalytics.IsRecording then
            PvPAnalytics:EndMatch()
        end
        PvPAnalytics.CurrentMatch = nil
        return
    end
    -- In arena and not recording yet: start once gates open event fires; if missed, start now
    if instanceType == "arena" and not PvPAnalytics.IsRecording then
        PvPAnalytics:StartMatch()
    end
end

function PvPAnalytics:StartMatch()
    if PvPAnalytics.IsRecording then return end
    PvPAnalytics.IsRecording = true
    PvPAnalytics.GuidToRealm = {}
    local mapName = GetZoneText()
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    local _, _, difficulty = GetInstanceInfo()
    local arenaMode = "unknown"  -- Detect 2v2/3v3 like ArenaAnalytics
    
    -- Detect arena mode (inspired by Details! group detection)
    local groupSize = 1
    if IsInGroup() then
        if IsInRaid() then
            groupSize = GetNumGroupMembers()
        else
            groupSize = GetNumGroupMembers() + 1  -- +1 for player
        end
    end
    
    if difficulty == 10 or difficulty == 8 or difficulty == 7 then
        arenaMode = "Solo Shuffle"
    elseif groupSize == 2 then 
        arenaMode = "2v2"
    elseif groupSize == 3 then 
        arenaMode = "3v3"
    end
    
    -- Get your team info (enhanced player tracking)
    local teamPlayers = {}
    local playerGUID = UnitGUID("player")
    if playerGUID then
        local name = UnitName("player")
        local realm = GetRealmName()
        local class, classId = UnitClass("player")
        local specId = GetSpecializationInfo(GetSpecialization() or 1)
        local faction = UnitFactionGroup("player")
        
        -- Store/update player profile (DBContext)
        if not PvPAnalyticsDB.players[playerGUID] then
            PvPAnalyticsDB.players[playerGUID] = {
                name = name,
                realm = realm,
                class = class,
                classId = classId,
                specId = specId,
                faction = faction,
                matchesPlayed = 0,
                wins = 0,
                losses = 0,
                totalDamage = 0,
                totalHealing = 0,
                kdratio = 0,
                interruptsPerMatch = 0
            }
        end
        teamPlayers[playerGUID] = true
    end
    
    -- Track party members
    for i = 1, GetNumGroupMembers() do
        local unit = "party" .. i
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            if guid then
                local name, realm = UnitName(unit)
                local class, classId = UnitClass(unit)
                local specId = GetSpecializationInfo(GetSpecialization() or 1, nil, UnitSex(unit))
                local faction = UnitFactionGroup(unit)
                
                -- Store/update player profile (DBContext)
                if not PvPAnalyticsDB.players[guid] then
                    PvPAnalyticsDB.players[guid] = {
                        name = name,
                        realm = realm,
                        class = class,
                        classId = classId,
                        specId = specId,
                        faction = faction,
                        matchesPlayed = 0,
                        wins = 0,
                        losses = 0,
                        totalDamage = 0,
                        totalHealing = 0,
                        kdratio = 0,
                        interruptsPerMatch = 0
                    }
                end
                teamPlayers[guid] = true
                PvPAnalyticsDB.players[guid].matchesPlayed = (PvPAnalyticsDB.players[guid].matchesPlayed or 0) + 1
            end
        end
    end
    
    -- Initialize the Match Data Structure (enhanced with team/opponent tracking)
    PvPAnalytics.CurrentMatch = {
        metadata = {
            id = GetTime(), -- Unique ID
            date = timestamp,
            map = mapName,
            mode = arenaMode,
            duration = 0,
            winner = nil,  -- Will be set on end (your team wins if opponents die first)
            yourTeamSize = groupSize
        },
        players = {}, -- Enhanced: {guid = {name, class, spec, faction, isAlly = true/false, damageShare, ccUptime}}
        opponents = {},  -- New: Separate opponent tracking like ArenaAnalytics
        events = {},  -- Existing timeline
        stats = {
            damage = {},
            healing = {},
            absorbs = {},
            interrupts = {},
            ccChains = {},
            trinketUsage = {},
            bigButtonUsage = {},
            deaths = {},  -- New: Track who died when
            teamDamageShare = 0,  -- Total team damage for percentages
            matchRating = 0  -- Calculated post-match (win/loss + performance)
        }
    }
    
    -- Populate initial player data (your team)
    if playerGUID then
        PvPAnalytics.CurrentMatch.players[playerGUID] = {
            name = UnitName("player"),
            class = select(2, UnitClass("player")),
            spec = GetSpecializationInfo(GetSpecialization() or 1),
            faction = UnitFactionGroup("player"),
            realm = GetRealmName(),
            isAlly = true,
            damageShare = 0,
            ccUptime = 0
        }
    end
    
    for i = 1, GetNumGroupMembers() do
        local unit = "party" .. i
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            if guid then
                PvPAnalytics.CurrentMatch.players[guid] = {
                    name = UnitName(unit),
                    class = select(2, UnitClass(unit)),
                    spec = GetSpecializationInfo(GetSpecialization() or 1, nil, UnitSex(unit)),
                    faction = UnitFactionGroup(unit),
                    realm = select(2, UnitName(unit)),
                    isAlly = true,
                    damageShare = 0,
                    ccUptime = 0
                }
            end
        end
    end
    
    -- Reset CC chain tracking (if CombatLog module is loaded)
    if PvPAnalytics.ResetCCTracking then
        PvPAnalytics:ResetCCTracking()
    end
    
    PvPAnalytics:CacheOpponentSpecs()
    print("|cff00ff00[PvPAnalytics]|r Match Started: " .. mapName .. " (" .. arenaMode .. ")")
end

-- Opponent prep data (class/spec/realm) before the match starts
function PvPAnalytics:CacheOpponentSpecs()
    if not PvPAnalytics.CurrentMatch then return end
    local match = PvPAnalytics.CurrentMatch
    for i = 1, GetNumArenaOpponentSpecs() do
        local specId = GetArenaOpponentSpec(i)
        if specId and specId > 0 then
            local _, specName, _, _, _, classFile = GetSpecializationInfoByID(specId)
            local unit = "arena" .. i
            local name, realm = UnitName(unit)
            local guid = UnitGUID(unit)
            if name then
                realm = realm and realm ~= "" and realm or GetRealmName()
                local entry = {
                    name = name,
                    class = classFile,
                    spec = specName or specId,
                    faction = "opponent",
                    isAlly = false,
                    damageShare = 0,
                    ccUptime = 0,
                    realm = realm
                }
                if guid then
                    PvPAnalytics.GuidToRealm[guid] = realm
                    match.opponents[guid] = entry
                else
                    -- Store by slot name if GUID not yet available
                    match.opponents[name] = entry
                end
            end
        end
    end
end

-- Update opponent data when units become visible
function PvPAnalytics:UpdateArenaOpponent(unitId, updateReason)
    if not PvPAnalytics.CurrentMatch or not unitId then return end
    local guid = UnitGUID(unitId)
    local name, realm = UnitName(unitId)
    if not guid or not name then return end
    realm = realm and realm ~= "" and realm or GetRealmName()
    PvPAnalytics.GuidToRealm[guid] = realm
    local classFile = select(2, UnitClass(unitId))
    local index = tonumber(string.match(unitId, "arena(%d+)") or "")
    local specId
    if index then
        local id = GetArenaOpponentSpec(index)
        if id and id > 0 then
            specId = select(1, GetSpecializationInfoByID(id))
        end
    end
    local match = PvPAnalytics.CurrentMatch
    match.opponents[guid] = match.opponents[guid] or {
        damageShare = 0,
        ccUptime = 0
    }
    match.opponents[guid].name = name
    match.opponents[guid].class = classFile
    match.opponents[guid].spec = specId
    match.opponents[guid].faction = "opponent"
    match.opponents[guid].isAlly = false
    match.opponents[guid].realm = realm
end

local function AddAmount(tbl, guid, amount)
    if not guid or not amount then return end
    tbl[guid] = (tbl[guid] or 0) + amount
end

local function GetBaseName(name)
    if not name then return nil end
    local short = strsplit("-", name)
    return short or name
end

function PvPAnalytics:EnsureActor(guid, name, isAlly)
    if not guid or not PvPAnalytics.CurrentMatch then return end
    local match = PvPAnalytics.CurrentMatch
    local faction = isAlly and UnitFactionGroup("player") or "opponent"
    local targetTable = isAlly and match.players or match.opponents
    if not targetTable[guid] then
        targetTable[guid] = {
            name = GetBaseName(name) or "Unknown",
            class = nil,
            spec = nil,
            faction = faction,
            isAlly = isAlly,
            damageShare = 0,
            ccUptime = 0,
            realm = PvPAnalytics.GuidToRealm[guid]
        }
    end
end

function PvPAnalytics:IsAlly(flags)
    return bit.band(flags or 0, COMBATLOG_OBJECT_REACTION_FRIENDLY) > 0
end

function PvPAnalytics:ProcessCombatLog()
    if not PvPAnalytics.CurrentMatch then return end
    local match = PvPAnalytics.CurrentMatch
    local info = { CombatLogGetCurrentEventInfo() }
    local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags = unpack(info)
    local eventTime = date("%H:%M:%S")

    local isAllySource = PvPAnalytics:IsAlly(sourceFlags)
    local isAllyDest = PvPAnalytics:IsAlly(destFlags)

    if sourceGUID then
        PvPAnalytics:EnsureActor(sourceGUID, sourceName, isAllySource)
    end
    if destGUID then
        PvPAnalytics:EnsureActor(destGUID, destName, isAllyDest)
    end

    -- Record timeline event with timestamp
    table.insert(match.events, {
        type = subevent,
        time = eventTime,
        rawTime = timestamp,
        sourceGUID = sourceGUID,
        sourceName = sourceName,
        destGUID = destGUID,
        destName = destName
    })

    -- Damage events
    if subevent == "SWING_DAMAGE" then
        local amount = info[12]
        AddAmount(match.stats.damage, sourceGUID, amount)
    elseif subevent == "RANGE_DAMAGE" or subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "DAMAGE_SPLIT" or subevent == "DAMAGE_SHIELD" or subevent == "SPELL_BUILDING_DAMAGE" then
        local amount = info[15]
        AddAmount(match.stats.damage, sourceGUID, amount)
    elseif subevent == "ENVIRONMENTAL_DAMAGE" then
        local amount = info[13]
        AddAmount(match.stats.damage, sourceGUID, amount)
    end

    -- Healing
    if subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        local amount = info[15]
        AddAmount(match.stats.healing, sourceGUID, amount)
    end

    -- Absorbs (logged as healing/absorbed)
    if subevent == "SPELL_ABSORBED" then
        local absorbAmount = info[#info]  -- last param is amount
        AddAmount(match.stats.absorbs, destGUID or sourceGUID, absorbAmount)
    end

    -- Interrupts
    if subevent == "SPELL_INTERRUPT" then
        AddAmount(match.stats.interrupts, sourceGUID, 1)
    end

    -- Deaths
    if subevent == "UNIT_DIED" or subevent == "PARTY_KILL" then
        table.insert(match.events, {
            type = "DEATH",
            time = eventTime,
            rawTime = timestamp,
            sourceGUID = sourceGUID,
            sourceName = sourceName,
            destGUID = destGUID,
            destName = destName
        })
        AddAmount(match.stats.deaths, destGUID, 1)
    end
end

-- Pull final damage/heal from scoreboard to ensure completeness
function PvPAnalytics:PopulateScoreboardStats(match)
    if not match then return end
    local numScores = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
    for i = 1, numScores do
        local name, killingBlows, honorableKills, deaths, honor, faction, race, class, classFileName, damageDone, healingDone = GetBattlefieldScore(i)
        local guid = PvPAnalytics:FindGuidByName(name, match)
        if guid then
            if damageDone and damageDone > 0 then
                match.stats.damage[guid] = damageDone
            end
            if healingDone and healingDone > 0 then
                match.stats.healing[guid] = healingDone
            end
        end
    end
    if C_PvP and C_PvP.GetScoreInfo then
        for i = 1, numScores do
            local scoreInfo = C_PvP.GetScoreInfo(i)
            if scoreInfo and scoreInfo.name then
                local guid = PvPAnalytics:FindGuidByName(scoreInfo.name, match)
                if guid then
                    if scoreInfo.damageDone and scoreInfo.damageDone > 0 then
                        match.stats.damage[guid] = scoreInfo.damageDone
                    end
                    if scoreInfo.healingDone and scoreInfo.healingDone > 0 then
                        match.stats.healing[guid] = scoreInfo.healingDone
                    end
                end
            end
        end
    end
end

function PvPAnalytics:FindGuidByName(name, match)
    if not name or not match then return nil end
    local short = GetBaseName(name)
    for guid, data in pairs(match.players) do
        if GetBaseName(data.name) == short then
            return guid
        end
    end
    for guid, data in pairs(match.opponents) do
        if GetBaseName(data.name) == short then
            return guid
        end
    end
    return nil
end

function PvPAnalytics:EndMatch()
    if not PvPAnalytics.IsRecording then return end
    PvPAnalytics.IsRecording = false
    if PvPAnalytics.CurrentMatch then
        local match = PvPAnalytics.CurrentMatch
        local endTime = date("%Y-%m-%d %H:%M:%S")
        match.metadata.endTime = endTime
        local startTime = match.metadata.id
        match.metadata.duration = math.floor(GetTime() - startTime)  -- Duration in seconds
        PvPAnalytics:PopulateScoreboardStats(match)
        
        -- Determine winner (simple: if more opponent deaths than ally deaths)
        local allyDeaths = 0
        local opponentDeaths = 0
        local allyDeathGUIDs = {}
        local opponentDeathGUIDs = {}
        
        for _, event in ipairs(match.events) do
            if event.type == "DEATH" and event.destGUID then
                -- Check if this is an ally or opponent
                if match.players[event.destGUID] and match.players[event.destGUID].isAlly then
                    allyDeaths = allyDeaths + 1
                    allyDeathGUIDs[event.destGUID] = true
                else
                    opponentDeaths = opponentDeaths + 1
                    opponentDeathGUIDs[event.destGUID] = true
                end
            end
        end
        
        local youWon
        local battlefieldWinner = GetBattlefieldWinner and GetBattlefieldWinner()
        if battlefieldWinner ~= nil then
            local faction = UnitFactionGroup("player")
            if faction == "Alliance" then
                youWon = battlefieldWinner == 0
            elseif faction == "Horde" then
                youWon = battlefieldWinner == 1
            end
        end
        if youWon == nil then
            youWon = opponentDeaths > allyDeaths or opponentDeaths >= match.metadata.yourTeamSize
        end
        match.metadata.winner = youWon and "your_team" or "opponents"
        
        -- Update user profile (DBContext)
        local userGuid = UnitGUID("player")
        if userGuid and PvPAnalyticsDB.userProfile then
            PvPAnalyticsDB.userProfile.totalMatches = (PvPAnalyticsDB.userProfile.totalMatches or 0) + 1
            if youWon then
                PvPAnalyticsDB.userProfile.totalWins = (PvPAnalyticsDB.userProfile.totalWins or 0) + 1
            else
                PvPAnalyticsDB.userProfile.totalLosses = (PvPAnalyticsDB.userProfile.totalLosses or 0) + 1
            end
            
            -- Calculate performance metrics (inspired by Details! breakdowns)
            local totalDamage = 0
            local totalHealing = 0
            local totalInterrupts = 0
            for guid, dmg in pairs(match.stats.damage) do totalDamage = totalDamage + dmg end
            for guid, heal in pairs(match.stats.healing) do totalHealing = totalHealing + heal end
            for guid, intr in pairs(match.stats.interrupts) do totalInterrupts = totalInterrupts + intr end
            
            match.stats.teamDamageShare = totalDamage
            
            -- Simple Elo-like rating calculation
            local baseRating = youWon and 1000 or 500
            local damageBonus = math.min((match.stats.damage[userGuid] or 0) / 10000, 500)
            local deathPenalty = allyDeaths * 100
            match.stats.matchRating = math.max(0, baseRating + damageBonus - deathPenalty)
            
            -- Update averages
            local totalMatches = PvPAnalyticsDB.userProfile.totalMatches
            local currentAvgDamage = PvPAnalyticsDB.userProfile.avgDamage or 0
            local currentAvgHealing = PvPAnalyticsDB.userProfile.avgHealing or 0
            local currentAvgInterrupts = PvPAnalyticsDB.userProfile.avgInterrupts or 0
            
            local playerDamage = match.stats.damage[userGuid] or 0
            local playerHealing = match.stats.healing[userGuid] or 0
            local playerInterrupts = match.stats.interrupts[userGuid] or 0
            
            PvPAnalyticsDB.userProfile.avgDamage = ((currentAvgDamage * (totalMatches - 1)) + playerDamage) / totalMatches
            PvPAnalyticsDB.userProfile.avgHealing = ((currentAvgHealing * (totalMatches - 1)) + playerHealing) / totalMatches
            PvPAnalyticsDB.userProfile.avgInterrupts = ((currentAvgInterrupts * (totalMatches - 1)) + playerInterrupts) / totalMatches
            
            -- Track favorite maps
            local mapName = match.metadata.map
            if not PvPAnalyticsDB.userProfile.favoriteMaps then
                PvPAnalyticsDB.userProfile.favoriteMaps = {}
            end
            if not PvPAnalyticsDB.userProfile.favoriteMaps[mapName] then
                PvPAnalyticsDB.userProfile.favoriteMaps[mapName] = 0
            end
            PvPAnalyticsDB.userProfile.favoriteMaps[mapName] = PvPAnalyticsDB.userProfile.favoriteMaps[mapName] + 1
            
            -- Track performance trends (last 10 matches)
            if not PvPAnalyticsDB.userProfile.performanceTrends then
                PvPAnalyticsDB.userProfile.performanceTrends = {}
            end
            table.insert(PvPAnalyticsDB.userProfile.performanceTrends, {
                rating = match.stats.matchRating,
                won = youWon,
                date = endTime
            })
            -- Keep only last 10
            while #PvPAnalyticsDB.userProfile.performanceTrends > 10 do
                table.remove(PvPAnalyticsDB.userProfile.performanceTrends, 1)
            end
        end
        
        -- Update player profiles
        for guid, playerData in pairs(match.players) do
            if playerData.isAlly then
                local dbPlayer = PvPAnalyticsDB.players[guid]
                if dbPlayer then
                    dbPlayer.totalDamage = (dbPlayer.totalDamage or 0) + (match.stats.damage[guid] or 0)
                    dbPlayer.totalHealing = (dbPlayer.totalHealing or 0) + (match.stats.healing[guid] or 0)
                    dbPlayer.matchesPlayed = (dbPlayer.matchesPlayed or 0) + 1
                    if youWon then 
                        dbPlayer.wins = (dbPlayer.wins or 0) + 1 
                    else 
                        dbPlayer.losses = (dbPlayer.losses or 0) + 1 
                    end
                    local totalMatches = dbPlayer.wins + dbPlayer.losses
                    if totalMatches > 0 then
                        dbPlayer.kdratio = dbPlayer.wins / totalMatches
                    end
                    dbPlayer.interruptsPerMatch = (dbPlayer.totalDamage or 0) / math.max(dbPlayer.matchesPlayed, 1)  -- Simplified metric
                end
            end
        end
        
        -- Ensure DB exists before saving
        if not PvPAnalyticsDB then
            PvPAnalyticsDB = { matches = {} }
        end
        if not PvPAnalyticsDB.matches then
            PvPAnalyticsDB.matches = {}
        end
        
        -- Save to DB
        table.insert(PvPAnalyticsDB.matches, match)
        
        local winLossText = youWon and "WIN" or "LOSS"
        local ratingText = math.floor(match.stats.matchRating)
        local durationText = math.floor(match.metadata.duration)
        print("|cff00ff00[PvPAnalytics]|r Match Ended: " .. winLossText .. " | Rating: " .. ratingText .. " | Duration: " .. durationText .. "s")
        PvPAnalytics.CurrentMatch = nil
    end
    
    -- Reset CC chain tracking
    if PvPAnalytics.ResetCCTracking then
        PvPAnalytics:ResetCCTracking()
    end
end

-- New: JSON serialization helper (for web export, simple version)
function PvPAnalytics:SerializeToJSON(data, depth)
    depth = depth or 0
    local indent = string.rep("  ", depth)
    
    if type(data) == "nil" then
        return "null"
    elseif type(data) == "boolean" then
        return data and "true" or "false"
    elseif type(data) == "number" then
        return tostring(data)
    elseif type(data) == "string" then
        -- Escape special characters
        local escaped = data:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
        return '"' .. escaped .. '"'
    elseif type(data) == "table" then
        -- Check if it's an array (sequential numeric keys starting from 1)
        local isArray = true
        local maxIndex = 0
        local count = 0
        for k, v in pairs(data) do
            count = count + 1
            if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
                isArray = false
                break
            end
            if k > maxIndex then maxIndex = k end
        end
        if isArray and maxIndex == count then
            -- Array format
            local json = "["
            local first = true
            for i = 1, maxIndex do
                if not first then json = json .. "," end
                first = false
                json = json .. "\n" .. indent .. "  " .. PvPAnalytics:SerializeToJSON(data[i], depth + 1)
            end
            json = json .. "\n" .. indent .. "]"
            return json
        else
            -- Object format
            local json = "{"
            local first = true
            for key, value in pairs(data) do
                if not first then json = json .. "," end
                first = false
                local keyStr = type(key) == "string" and PvPAnalytics:SerializeToJSON(key, depth + 1) or '"' .. tostring(key) .. '"'
                json = json .. "\n" .. indent .. "  " .. keyStr .. ": " .. PvPAnalytics:SerializeToJSON(value, depth + 1)
            end
            json = json .. "\n" .. indent .. "}"
            return json
        end
    else
        return '"' .. tostring(data) .. '"'
    end
end

-- --- SLASH COMMANDS ---
SLASH_PVPANALYTICS1 = "/pvpdata"
SLASH_PVPANALYTICS2 = "/pvpexport"  -- New: Export command alias
SlashCmdList["PVPANALYTICS"] = function(msg)
    msg = msg or ""
    -- Trim whitespace
    msg = msg:match("^%s*(.-)%s*$") or ""
    
    -- Ensure DB is initialized
    if not PvPAnalyticsDB then
        PvPAnalyticsDB = { matches = {}, players = {}, userProfile = {}, settings = {} }
    end
    if not PvPAnalyticsDB.matches then
        PvPAnalyticsDB.matches = {}
    end
    if not PvPAnalyticsDB.players then
        PvPAnalyticsDB.players = {}
    end
    
    -- Parse arguments
    local args = {}
    for word in msg:gmatch("%S+") do 
        table.insert(args, word) 
    end
    
    if args[1] and args[1]:lower() == "clear" then
        PvPAnalyticsDB.matches = {}
        PvPAnalyticsDB.players = {}
        print("|cff00ff00[PvPAnalytics]|r All Data Cleared.")
    elseif args[1] and args[1]:lower() == "profile" then
        -- New: Show user profile like Details!
        local profile = PvPAnalyticsDB.userProfile
        if profile and profile.name then
            local winRate = 0
            if profile.totalMatches and profile.totalMatches > 0 then
                winRate = math.floor((profile.totalWins or 0) / profile.totalMatches * 100)
            end
            print("|cff00ff00[PvPAnalytics]|r Profile: " .. profile.name .. " (" .. (profile.faction or "Unknown") .. ")")
            print("Matches: " .. (profile.totalMatches or 0) .. " | Wins: " .. (profile.totalWins or 0) .. " (" .. winRate .. "%)")
            print("Avg DPS: " .. math.floor(profile.avgDamage or 0) .. " | Avg HPS: " .. math.floor(profile.avgHealing or 0))
            print("Avg Interrupts: " .. string.format("%.1f", profile.avgInterrupts or 0))
        else
            print("|cffff0000[PvPAnalytics]|r Profile not initialized. Play a match first.")
        end
    elseif args[1] and args[1]:lower() == "export" and args[2] then
        -- New: Export specific match for web
        local matchId = tonumber(args[2])
        if matchId then
            local found = false
            for _, match in ipairs(PvPAnalyticsDB.matches) do
                if math.floor(match.metadata.id) == math.floor(matchId) then
                    -- Generate JSON (simple serialization for web)
                    local json = PvPAnalytics:SerializeToJSON(match)
                    print("|cff00ff00[PvPAnalytics]|r Export for Match " .. matchId .. ":")
                    print("|cffffffff" .. json)
                    print("|cff00ff00[PvPAnalytics]|r Copy the above JSON and upload to your website!")
                    found = true
                    break
                end
            end
            if not found then
                print("|cffff0000[PvPAnalytics]|r Match ID not found. Use /pvpdata to list matches.")
            end
        else
            print("|cffff0000[PvPAnalytics]|r Usage: /pvpdata export <matchId>")
            print("|cffff0000[PvPAnalytics]|r Example: /pvpdata export 1234567890")
        end
    elseif msg == "" then
        local count = #PvPAnalyticsDB.matches
        local playerCount = 0
        for _ in pairs(PvPAnalyticsDB.players) do playerCount = playerCount + 1 end
        print("|cff00ff00[PvPAnalytics]|r Stored Matches: " .. count .. " | Players Tracked: " .. playerCount)
        if count > 0 then
            print("|cff00ff00[PvPAnalytics]|r Commands: clear, profile, export <id>")
            print("|cff00ff00[PvPAnalytics]|r Example: /pvpdata export " .. math.floor(PvPAnalyticsDB.matches[count].metadata.id))
        end
    else
        print("|cff00ff00[PvPAnalytics]|r Unknown command: " .. msg)
        print("|cff00ff00[PvPAnalytics]|r Commands: clear, profile, export <id>")
    end
end

Frame:SetScript("OnEvent", Frame.OnEvent)
Frame:OnLoad()
