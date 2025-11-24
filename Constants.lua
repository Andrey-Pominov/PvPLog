local _, addon = ...
addon.Constants = {}

addon.Constants.CCTypes = {
    STUN = "STUN",
    SILENCE = "SILENCE",
    INCAPACITATE = "INCAP",
    ROOT = "ROOT",
    DISORIENT = "DISORIENT"
}

-- Format: [SpellID] = { type = "CATEGORY", name = "Name" }
addon.Constants.ImportantSpells = {
    -- --- DEFENSIVES ---
    [33206] = { type = "DEFENSIVE", name = "Pain Suppression" },
    [642]   = { type = "DEFENSIVE", name = "Divine Shield" },
    [186265]= { type = "DEFENSIVE", name = "Turtle Aspect" },
    [47585] = { type = "DEFENSIVE", name = "Dispersion" },
    [108968]= { type = "DEFENSIVE", name = "Void Shift" },

    -- --- BURSTS / OFFENSIVE ---
    [31884] = { type = "BURST", name = "Avenging Wrath" },
    [1719]  = { type = "BURST", name = "Recklessness" },
    [190319]= { type = "BURST", name = "Combustion" },

    -- --- CROWD CONTROL (Examples) ---
    -- Rogues
    [408]   = { type = "STUN", name = "Kidney Shot" },
    [1833]  = { type = "STUN", name = "Cheap Shot" },
    [6770]  = { type = "INCAP", name = "Sap" },
    [2094]  = { type = "INCAP", name = "Blind" },
    -- Mages
    [118]   = { type = "INCAP", name = "Polymorph" },
    -- Priests
    [8122]  = { type = "DISORIENT", name = "Psychic Scream" },
    -- Druids
    [33786] = { type = "INCAP", name = "Cyclone" },
    [5211]  = { type = "STUN", name = "Mighty Bash" },
}

function addon.IsImportantSpell(spellId)
    return addon.Constants.ImportantSpells[spellId]
end