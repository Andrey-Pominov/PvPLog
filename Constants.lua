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
    [13750] = { type = "BURST", name = "Adrenaline Rush" },
    [79140] = { type = "BURST", name = "Vendetta" },
    [198589]= { type = "BURST", name = "Dark Soul: Instability" },
    [12472] = { type = "BURST", name = "Icy Veins" },
    [194223]= { type = "BURST", name = "Celestial Alignment" },
    [102543]= { type = "BURST", name = "Incarnation: Chosen of Elune" },
    [106951]= { type = "BURST", name = "Berserk" },
    [19574] = { type = "BURST", name = "Bestial Wrath" },
    [266779]= { type = "BURST", name = "Coordinated Assault" },

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
    -- Warriors
    [5246]  = { type = "STUN", name = "Intimidating Shout" },
    [132169]= { type = "STUN", name = "Storm Bolt" },
    -- Paladins
    [20066] = { type = "INCAP", name = "Repentance" },
    [853]   = { type = "STUN", name = "Hammer of Justice" },
    -- Death Knights
    [207167]= { type = "STUN", name = "Blinding Sleet" },
    [221562]= { type = "STUN", name = "Asphyxiate" },
    -- Demon Hunters
    [200166]= { type = "STUN", name = "Metamorphosis" },
    [179057]= { type = "STUN", name = "Chaos Nova" },
    -- Warlocks
    [6789]  = { type = "INCAP", name = "Mortal Coil" },
    [30283] = { type = "STUN", name = "Shadowfury" },
    -- Shamans
    [51514] = { type = "INCAP", name = "Hex" },
    [211015]= { type = "STUN", name = "Hex" },
    -- Monks
    [115078]= { type = "STUN", name = "Paralysis" },
    [119381]= { type = "STUN", name = "Leg Sweep" },
    -- Hunters
    [3355]  = { type = "INCAP", name = "Freezing Trap" },
    [213691]= { type = "STUN", name = "Scatter Shot" },
}

-- PvP Trinket Spell IDs (various versions across expansions)
addon.Constants.TrinketSpells = {
    [42292] = { name = "PvP Trinket" }, -- Classic/BC
    [59752] = { name = "PvP Trinket" }, -- WotLK
    [195710] = { name = "PvP Trinket" }, -- Legion/Retail (current)
    [208683] = { name = "PvP Trinket" }, -- BFA
    [336126] = { name = "PvP Trinket" }, -- Shadowlands
}

-- Racial Abilities
addon.Constants.RacialAbilities = {
    -- Human
    [59752] = { type = "RACIAL", name = "Every Man for Himself", category = "DEFENSIVE" },
    -- Undead
    [7744]  = { type = "RACIAL", name = "Will of the Forsaken", category = "DEFENSIVE" },
    -- Orc
    [33697] = { type = "RACIAL", name = "Blood Fury", category = "OFFENSIVE" },
    -- Troll
    [26297] = { type = "RACIAL", name = "Berserking", category = "OFFENSIVE" },
    -- Dwarf
    [20594] = { type = "RACIAL", name = "Stoneform", category = "DEFENSIVE" },
    -- Gnome
    [20589] = { type = "RACIAL", name = "Escape Artist", category = "DEFENSIVE" },
    -- Night Elf
    [58984] = { type = "RACIAL", name = "Shadowmeld", category = "DEFENSIVE" },
    -- Draenei
    [28880] = { type = "RACIAL", name = "Gift of the Naaru", category = "DEFENSIVE" },
    -- Blood Elf
    [28730] = { type = "RACIAL", name = "Arcane Torrent", category = "OFFENSIVE" },
    -- Tauren
    [20549] = { type = "RACIAL", name = "War Stomp", category = "OFFENSIVE" },
    -- Pandaren
    [107079] = { type = "RACIAL", name = "Quaking Palm", category = "OFFENSIVE" },
    -- Goblin
    [69041] = { type = "RACIAL", name = "Rocket Jump", category = "DEFENSIVE" },
    -- Worgen
    [68992] = { type = "RACIAL", name = "Darkflight", category = "DEFENSIVE" },
    -- Void Elf
    [256948] = { type = "RACIAL", name = "Spatial Rift", category = "DEFENSIVE" },
    -- Lightforged Draenei
    [255647] = { type = "RACIAL", name = "Light's Judgment", category = "OFFENSIVE" },
    -- Dark Iron Dwarf
    [265221] = { type = "RACIAL", name = "Fireblood", category = "DEFENSIVE" },
    -- Kul Tiran
    [287712] = { type = "RACIAL", name = "Haymaker", category = "OFFENSIVE" },
    -- Mechagnome
    [312924] = { type = "RACIAL", name = "Hyper Organic Light Originator", category = "DEFENSIVE" },
    -- Vulpera
    [312411] = { type = "RACIAL", name = "Bag of Tricks", category = "OFFENSIVE" },
    -- Mag'har Orc
    [274738] = { type = "RACIAL", name = "Ancestral Call", category = "OFFENSIVE" },
    -- Zandalari Troll
    [291944] = { type = "RACIAL", name = "Regeneratin'", category = "DEFENSIVE" },
    -- Nightborne
    [260364] = { type = "RACIAL", name = "Arcane Pulse", category = "OFFENSIVE" },
    -- Highmountain Tauren
    [255654] = { type = "RACIAL", name = "Bull Rush", category = "OFFENSIVE" },
}

function addon.IsImportantSpell(spellId)
    return addon.Constants.ImportantSpells[spellId]
end

function addon.IsTrinketSpell(spellId)
    return addon.Constants.TrinketSpells[spellId] ~= nil
end

function addon.IsRacialAbility(spellId)
    return addon.Constants.RacialAbilities[spellId] ~= nil
end

function addon.IsBigButtonSpell(spellId)
    local spellInfo = addon.IsImportantSpell(spellId)
    if spellInfo and (spellInfo.type == "BURST" or spellInfo.type == "DEFENSIVE") then
        return true, spellInfo.type == "BURST" and "OFFENSIVE" or "DEFENSIVE"
    end
    if addon.IsRacialAbility(spellId) then
        local racial = addon.Constants.RacialAbilities[spellId]
        return true, racial.category
    end
    return false
end