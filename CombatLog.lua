local _, addon = ...

-- CC Chain tracking: stores recent CC applications per target
local recentCCs = {} -- Format: [destGUID] = { {time, spellId, spellName, sourceName}, ... }
local CC_CHAIN_WINDOW = 5.0 -- seconds

-- Helper to ensure player tables exist in stats
local function InitPlayer(guid, name)
    if not addon.CurrentMatch.stats.damage[guid] then
        addon.CurrentMatch.stats.damage[guid] = 0
        addon.CurrentMatch.stats.healing[guid] = 0
        addon.CurrentMatch.stats.absorbs[guid] = 0
        addon.CurrentMatch.stats.interrupts[guid] = 0
        addon.CurrentMatch.stats.ccChains[guid] = 0
        addon.CurrentMatch.stats.trinketUsage[guid] = 0
        addon.CurrentMatch.stats.bigButtonUsage[guid] = 0
        addon.CurrentMatch.players[guid] = { name = name }
    end
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
    local timestamp, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, arg12, arg13, arg14, arg15, arg16 = CombatLogGetCurrentEventInfo()

    if not addon.CurrentMatch then return end

    -- Initialize players involved
    if sourceName then InitPlayer(sourceGUID, sourceName) end
    if destName then InitPlayer(destGUID, destName) end

    -- 1. TRACK DAMAGE
    if subevent:match("_DAMAGE") then
        local amount = arg15
        if subevent == "SWING_DAMAGE" then amount = arg12 end

        if amount then
            addon.CurrentMatch.stats.damage[sourceGUID] = (addon.CurrentMatch.stats.damage[sourceGUID] or 0) + amount
        end

        -- 2. TRACK HEALING
    elseif subevent:match("_HEAL") then
        local amount = arg15
        if amount then
            addon.CurrentMatch.stats.healing[sourceGUID] = (addon.CurrentMatch.stats.healing[sourceGUID] or 0) + amount
        end

        -- 3. TRACK ABSORBS (New)
    elseif subevent == "SPELL_ABSORBED" then
        -- Argument mapping for SPELL_ABSORBED is tricky. 
        -- Usually: casterGUID, casterName, flags, flags, spellId, spellName, school, absorbedGUID, absorbedName, flags, flags, absorbSpellId, absorbSpellName, school, amount
        -- But easiest way is to catch the last argument for Amount
        local amount = select(select("#", ...), ...) -- Get last arg
        if type(amount) == "number" then
            -- Credit the source (the shielder) if possible, otherwise just track it on the target
            -- NOTE: Standardizing absorb source is complex in Lua, here we track TOTAL absorbs on the target
            addon.CurrentMatch.stats.absorbs[destGUID] = (addon.CurrentMatch.stats.absorbs[destGUID] or 0) + amount
        end

        -- 4. TRACK INTERRUPTS
    elseif subevent == "SPELL_INTERRUPT" then
        local spellId = arg12
        local extraSpellId = arg14 -- The spell that was kicked

        addon.CurrentMatch.stats.interrupts[sourceGUID] = (addon.CurrentMatch.stats.interrupts[sourceGUID] or 0) + 1

        -- Log Event for Timeline
        table.insert(addon.CurrentMatch.events, {
            type = "INTERRUPT",
            time = timestamp,
            source = sourceName,
            dest = destName,
            spellId = spellId,
            kickedSpell = extraSpellId
        })

        -- 5. TRACK DEATHS
    elseif subevent == "UNIT_DIED" and UnitIsPlayer(destName) then
        table.insert(addon.CurrentMatch.events, {
            type = "DEATH",
            time = timestamp,
            dest = destName
        })

        -- 6. TRACK AURAS (CC Chains & Defensives)
    elseif subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REMOVED" then
        local spellId = arg12
        local spellName = arg13
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
                    if isChain then
                        -- Increment chain count for source
                        addon.CurrentMatch.stats.ccChains[sourceGUID] = (addon.CurrentMatch.stats.ccChains[sourceGUID] or 0) + 1
                        
                        -- Log CC chain event
                        table.insert(addon.CurrentMatch.events, {
                            type = "CC_CHAIN",
                            time = timestamp,
                            target = destName,
                            targetGUID = destGUID,
                            chainSequence = chainSequence,
                            chainLength = #chainSequence
                        })
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

        -- 7. TRACK TRINKET USAGE
    elseif subevent == "SPELL_CAST_SUCCESS" then
        local spellId = arg12
        local spellName = arg13
        
        -- Check if this is a trinket
        if addon.IsTrinketSpell(spellId) then
            CleanOldCCs(timestamp)
            
            -- Check if player had active CC when trinket was used
            local hadCC, ccData = HasActiveCC(sourceGUID, timestamp)
            
            -- Increment trinket usage count
            addon.CurrentMatch.stats.trinketUsage[sourceGUID] = (addon.CurrentMatch.stats.trinketUsage[sourceGUID] or 0) + 1
            
            -- Log trinket usage event
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
        
        -- 8. TRACK BIG BUTTON ABILITIES (Cooldowns & Racials)
        local isBigButton, buttonCategory = addon.IsBigButtonSpell(spellId)
        if isBigButton then
            -- Increment big button usage count
            addon.CurrentMatch.stats.bigButtonUsage[sourceGUID] = (addon.CurrentMatch.stats.bigButtonUsage[sourceGUID] or 0) + 1
            
            -- Determine subtype
            local subType = buttonCategory
            local spellInfo = addon.IsImportantSpell(spellId)
            if spellInfo then
                if spellInfo.type == "BURST" then
                    subType = "OFFENSIVE"
                elseif spellInfo.type == "DEFENSIVE" then
                    subType = "DEFENSIVE"
                end
            elseif addon.IsRacialAbility(spellId) then
                local racial = addon.Constants.RacialAbilities[spellId]
                subType = racial.category
            end
            
            -- Log big button event
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