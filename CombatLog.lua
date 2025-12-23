local _, addon = ...
-- Use global PvPAnalytics table - ensure it exists
PvPAnalytics = PvPAnalytics or {}
local addon = PvPAnalytics

-- CC Chain tracking: stores recent CC applications per target
local recentCCs = {} -- Format: [destGUID] = { {time, spellId, spellName, sourceName}, ... }
local CC_CHAIN_WINDOW = 5.0 -- seconds

-- Helper to ensure player tables exist in stats
local function InitPlayer(guid, name)
    if not addon or not addon.CurrentMatch or not addon.CurrentMatch.stats then
        return
    end

    if not guid or not name then
        return
    end

    -- Treat combat pets as non-player actors for team-size/mod calculations
    if type(guid) == "string" and guid:sub(1, 4) == "Pet-" then
        -- We still allow stats to be recorded under the GUID, but we avoid
        -- adding them into the players/opponents tables used for team logic.
        if not addon.CurrentMatch.stats.damage[guid] then
            addon.CurrentMatch.stats.damage[guid] = 0
            addon.CurrentMatch.stats.healing[guid] = 0
            addon.CurrentMatch.stats.absorbs[guid] = 0
            addon.CurrentMatch.stats.interrupts[guid] = 0
            addon.CurrentMatch.stats.ccChains[guid] = 0
            addon.CurrentMatch.stats.trinketUsage[guid] = 0
            addon.CurrentMatch.stats.bigButtonUsage[guid] = 0
        end
        return
    end

    if not addon.CurrentMatch.stats.damage[guid] then
        addon.CurrentMatch.stats.damage[guid] = 0
        addon.CurrentMatch.stats.healing[guid] = 0
        addon.CurrentMatch.stats.absorbs[guid] = 0
        addon.CurrentMatch.stats.interrupts[guid] = 0
        addon.CurrentMatch.stats.ccChains[guid] = 0
        addon.CurrentMatch.stats.trinketUsage[guid] = 0
        addon.CurrentMatch.stats.bigButtonUsage[guid] = 0
    end

    if not addon.CurrentMatch.players then
        addon.CurrentMatch.players = {}
    end

    -- Do not overwrite richer player info populated in StartMatch; just ensure name exists.
    addon.CurrentMatch.players[guid] = addon.CurrentMatch.players[guid] or {}
    addon.CurrentMatch.players[guid].name = addon.CurrentMatch.players[guid].name or name
end

-- Helper to check if target has active CC debuff
local function HasActiveCC(targetGUID, currentTime)
    if not recentCCs[targetGUID] then return false end
    
    for _, ccData in ipairs(recentCCs[targetGUID]) do
        -- Check if CC is still active (within window and not removed)
        if currentTime - ccData.time < CC_CHAIN_WINDOW then
            return true, ccData
        end
    end
    return false
end

-- Helper to clean old CC entries
local function CleanOldCCs(currentTime)
    for guid, ccList in pairs(recentCCs) do
        for i = #ccList, 1, -1 do
            if currentTime - ccList[i].time > CC_CHAIN_WINDOW then
                table.remove(ccList, i)
            end
        end
        if #ccList == 0 then
            recentCCs[guid] = nil
        end
    end
end

-- Function to reset CC tracking (called when match starts/ends)
function addon:ResetCCTracking()
    recentCCs = {}
end

function addon:ProcessCombatLog()
    if not addon or not addon.CurrentMatch or not addon.CurrentMatch.stats then 
        return 
    end
    
    local ok, err = pcall(function()
        local timestamp, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, arg12, arg13, arg14, arg15, arg16 = CombatLogGetCurrentEventInfo()
        
        if not subevent or type(subevent) ~= "string" then
            return
        end

        -- Store raw combat log event for full replay
        if addon.CurrentMatch and addon.CurrentMatch.rawEvents then
            local rawEvent = {
                ts = timestamp,
                event = subevent,
                sourceGUID = sourceGUID,
                sourceName = sourceName,
                destGUID = destGUID,
                destName = destName,
                spellId = arg12,
                spellName = arg13,
                amount = arg15,
                extra = arg16,
            }
            table.insert(addon.CurrentMatch.rawEvents, rawEvent)
        end
        
        -- Initialize players involved
        if sourceName then InitPlayer(sourceGUID, sourceName) end
        if destName then InitPlayer(destGUID, destName) end

        -- 1. TRACK DAMAGE
        if subevent:match("_DAMAGE") then
            local amount = arg15
            if subevent == "SWING_DAMAGE" then amount = arg12 end

            if amount and sourceGUID then
                addon.CurrentMatch.stats.damage[sourceGUID] = (addon.CurrentMatch.stats.damage[sourceGUID] or 0) + amount
            end

            -- 2. TRACK HEALING
        elseif subevent:match("_HEAL") then
            local amount = arg15
            if amount and sourceGUID then
                addon.CurrentMatch.stats.healing[sourceGUID] = (addon.CurrentMatch.stats.healing[sourceGUID] or 0) + amount
            end

            -- 3. TRACK ABSORBS (New)
        elseif subevent == "SPELL_ABSORBED" then
            -- Argument mapping for SPELL_ABSORBED: amount is typically arg15 or last argument
            -- For simplicity, we'll track absorbs on the destination
            if destGUID and arg15 and type(arg15) == "number" then
                addon.CurrentMatch.stats.absorbs[destGUID] = (addon.CurrentMatch.stats.absorbs[destGUID] or 0) + arg15
            end

            -- 4. TRACK INTERRUPTS
        elseif subevent == "SPELL_INTERRUPT" then
            local spellId = arg12
            local extraSpellId = arg14 -- The spell that was kicked

            if sourceGUID then
                addon.CurrentMatch.stats.interrupts[sourceGUID] = (addon.CurrentMatch.stats.interrupts[sourceGUID] or 0) + 1

                -- Log Event for Timeline
                if addon.CurrentMatch.events then
                    table.insert(addon.CurrentMatch.events, {
                        type = "INTERRUPT",
                        time = timestamp,
                        source = sourceName,
                        dest = destName,
                        spellId = spellId,
                        kickedSpell = extraSpellId
                    })
                end
            end

            -- 5. TRACK DEATHS
        elseif subevent == "UNIT_DIED" and destName and destGUID then
            -- Check if it's a player (not a pet/minion)
            if UnitIsPlayer and UnitIsPlayer(destName) then
                if addon.CurrentMatch.events then
                    table.insert(addon.CurrentMatch.events, {
                        type = "DEATH",
                        time = timestamp,
                        dest = destName,
                        destGUID = destGUID  -- New: Include GUID for win/loss calculation
                    })
                end
                -- Track deaths in stats
                if addon.CurrentMatch.stats.deaths then
                    addon.CurrentMatch.stats.deaths[destGUID] = (addon.CurrentMatch.stats.deaths[destGUID] or 0) + 1
                end
            end

            -- 6. TRACK AURAS (CC Chains & Defensives)
        elseif (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REMOVED") and arg12 then
            local spellId = arg12
            local spellName = arg13
            
            if addon.IsImportantSpell then
                local spellInfo = addon.IsImportantSpell(spellId)

                if spellInfo then
                    local eventType = "UNKNOWN"

                    if spellInfo.type == "STUN" or spellInfo.type == "SILENCE" or spellInfo.type == "INCAP" or spellInfo.type == "DISORIENT" or spellInfo.type == "ROOT" then
                        eventType = "CC"
                        
                        -- CC Chain Detection
                        if subevent == "SPELL_AURA_APPLIED" then
                            CleanOldCCs(timestamp)
                            
                            -- Initialize CC list for this target if needed
                            if not recentCCs[destGUID] then
                                recentCCs[destGUID] = {}
                            end
                            
                            -- Check if this is part of a chain
                            local isChain = #recentCCs[destGUID] > 0
                            local chainSequence = {}
                            
                            -- Build chain sequence
                            for _, ccData in ipairs(recentCCs[destGUID]) do
                                table.insert(chainSequence, {
                                    spellId = ccData.spellId,
                                    spellName = ccData.spellName,
                                    source = ccData.sourceName,
                                    time = ccData.time
                                })
                            end
                            
                            -- Add current CC to sequence
                            table.insert(chainSequence, {
                                spellId = spellId,
                                spellName = spellName,
                                source = sourceName,
                                time = timestamp
                            })
                            
                            -- Store current CC
                            table.insert(recentCCs[destGUID], {
                                time = timestamp,
                                spellId = spellId,
                                spellName = spellName,
                                sourceName = sourceName
                            })
                            
                            -- If this is a chain, log it
                            if isChain and sourceGUID then
                                -- Increment chain count for source
                                addon.CurrentMatch.stats.ccChains[sourceGUID] = (addon.CurrentMatch.stats.ccChains[sourceGUID] or 0) + 1
                                
                                -- Log CC chain event
                                if addon.CurrentMatch.events then
                                    table.insert(addon.CurrentMatch.events, {
                                        type = "CC_CHAIN",
                                        time = timestamp,
                                        target = destName,
                                        targetGUID = destGUID,
                                        chainSequence = chainSequence,
                                        chainLength = #chainSequence
                                    })
                                end
                            end
                        elseif subevent == "SPELL_AURA_REMOVED" then
                            -- Remove CC from tracking when it's removed
                            if recentCCs[destGUID] then
                                for i = #recentCCs[destGUID], 1, -1 do
                                    if recentCCs[destGUID][i].spellId == spellId then
                                        table.remove(recentCCs[destGUID], i)
                                        break
                                    end
                                end
                                if #recentCCs[destGUID] == 0 then
                                    recentCCs[destGUID] = nil
                                end
                            end
                        end
                    elseif spellInfo.type == "DEFENSIVE" then
                        eventType = "DEFENSIVE"
                    elseif spellInfo.type == "BURST" then
                        eventType = "BURST"
                    end

                    -- Log to events for timeline
                    if addon.CurrentMatch.events then
                        table.insert(addon.CurrentMatch.events, {
                            type = eventType,
                            subType = spellInfo.type, -- e.g., "STUN"
                            action = (subevent == "SPELL_AURA_APPLIED" and "APPLIED" or "REMOVED"),
                            time = timestamp,
                            source = sourceName,
                            dest = destName,
                            spellId = spellId,
                            spellName = spellName
                        })
                    end
                end
            end

            -- 7. TRACK TRINKET USAGE
        elseif subevent == "SPELL_CAST_SUCCESS" and arg12 then
            local spellId = arg12
            local spellName = arg13
            
            if addon.IsTrinketSpell then
                -- Check if this is a trinket
                if addon.IsTrinketSpell(spellId) then
                    CleanOldCCs(timestamp)
                    
                    -- Check if player had active CC when trinket was used
                    local hadCC, ccData = HasActiveCC(sourceGUID, timestamp)
                    
                    if sourceGUID then
                        -- Increment trinket usage count
                        addon.CurrentMatch.stats.trinketUsage[sourceGUID] = (addon.CurrentMatch.stats.trinketUsage[sourceGUID] or 0) + 1
                        
                        -- Log trinket usage event
                        if addon.CurrentMatch.events then
                            table.insert(addon.CurrentMatch.events, {
                                type = "TRINKET",
                                time = timestamp,
                                source = sourceName,
                                sourceGUID = sourceGUID,
                                spellId = spellId,
                                spellName = spellName,
                                brokeCC = hadCC,
                                brokenCC = hadCC and ccData or nil
                            })
                        end
                    end
                end
            end
            
            -- 8. TRACK BIG BUTTON ABILITIES (Cooldowns & Racials)
            if addon.IsBigButtonSpell then
                local isBigButton, buttonCategory = addon.IsBigButtonSpell(spellId)
                if isBigButton and sourceGUID then
                    -- Increment big button usage count
                    addon.CurrentMatch.stats.bigButtonUsage[sourceGUID] = (addon.CurrentMatch.stats.bigButtonUsage[sourceGUID] or 0) + 1
                    
                    -- Determine subtype
                    local subType = buttonCategory
                    if addon.IsImportantSpell then
                        local spellInfo = addon.IsImportantSpell(spellId)
                        if spellInfo then
                            if spellInfo.type == "BURST" then
                                subType = "OFFENSIVE"
                            elseif spellInfo.type == "DEFENSIVE" then
                                subType = "DEFENSIVE"
                            end
                        elseif addon.IsRacialAbility and addon.IsRacialAbility(spellId) then
                            if addon.Constants and addon.Constants.RacialAbilities then
                                local racial = addon.Constants.RacialAbilities[spellId]
                                if racial then
                                    subType = racial.category
                                end
                            end
                        end
                    end
                    
                    -- Log big button event
                    if addon.CurrentMatch.events then
                        table.insert(addon.CurrentMatch.events, {
                            type = "BIG_BUTTON",
                            subType = subType, -- OFFENSIVE, DEFENSIVE, or RACIAL
                            time = timestamp,
                            source = sourceName,
                            sourceGUID = sourceGUID,
                            spellId = spellId,
                            spellName = spellName
                        })
                    end
                end
            end
        end
    end)
    
    if not ok then
        -- Silently fail - we don't want to spam errors
        return
    end
end