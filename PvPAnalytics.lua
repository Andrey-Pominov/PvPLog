local addonName, addon = ...

-- Global Object for SavedVariables - Constants.lua should have created this
PvPAnalytics = PvPAnalytics or {}
local Frame = CreateFrame("Frame")

-- Current Match State
PvPAnalytics.CurrentMatch = nil
PvPAnalytics.IsRecording = false

function Frame:OnLoad()
    Frame:RegisterEvent("PLAYER_LOGIN")
    Frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    Frame:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
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
    if instanceType == "arena" or instanceType == "pvp" then
        if not PvPAnalytics.IsRecording then
            PvPAnalytics:StartMatch()
        end
    else
        if PvPAnalytics.IsRecording then
            PvPAnalytics:EndMatch()
        end
    end
end

function PvPAnalytics:StartMatch()
    PvPAnalytics.IsRecording = true
    local mapName = GetZoneText()
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    local _, instanceType, difficulty = IsInInstance()
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
    
    if groupSize == 2 then 
        arenaMode = "2v2"
    elseif groupSize == 3 then 
        arenaMode = "3v3"
    elseif difficulty == 7 then 
        arenaMode = "Solo Shuffle"  -- Rated Solo Shuffle
    end
    
    -- Get your team info (enhanced player tracking)
    local teamPlayers = {}
    local playerGUID = UnitGUID("player")
    if playerGUID then
        local name = UnitName("player")
        local class, classId = UnitClass("player")
        local specId = GetSpecializationInfo(GetSpecialization() or 1)
        local faction = UnitFactionGroup("player")
        
        -- Store/update player profile (DBContext)
        if not PvPAnalyticsDB.players[playerGUID] then
            PvPAnalyticsDB.players[playerGUID] = {
                name = name,
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
                local name = UnitName(unit)
                local class, classId = UnitClass(unit)
                local specId = GetSpecializationInfo(GetSpecialization() or 1, nil, UnitSex(unit))
                local faction = UnitFactionGroup(unit)
                
                -- Store/update player profile (DBContext)
                if not PvPAnalyticsDB.players[guid] then
                    PvPAnalyticsDB.players[guid] = {
                        name = name,
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
    
    print("|cff00ff00[PvPAnalytics]|r Match Started: " .. mapName .. " (" .. arenaMode .. ")")
end

function PvPAnalytics:EndMatch()
    PvPAnalytics.IsRecording = false
    if PvPAnalytics.CurrentMatch then
        local match = PvPAnalytics.CurrentMatch
        local endTime = date("%Y-%m-%d %H:%M:%S")
        match.metadata.endTime = endTime
        local startTime = match.metadata.id
        match.metadata.duration = math.floor(GetTime() - startTime)  -- Duration in seconds
        
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
        
        local youWon = opponentDeaths > allyDeaths or opponentDeaths >= match.metadata.yourTeamSize
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
