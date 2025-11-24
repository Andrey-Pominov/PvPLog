local _, addon = ...

-- Helper to ensure player tables exist in stats
local function InitPlayer(guid, name)
    if not addon.CurrentMatch.stats.damage[guid] then
        addon.CurrentMatch.stats.damage[guid] = 0
        addon.CurrentMatch.stats.healing[guid] = 0
        addon.CurrentMatch.stats.absorbs[guid] = 0
        addon.CurrentMatch.stats.interrupts[guid] = 0
        addon.CurrentMatch.players[guid] = { name = name }
    end
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

            if spellInfo.type == "STUN" or spellInfo.type == "SILENCE" or spellInfo.type == "INCAP" then
                eventType = "CC"
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
    end
end