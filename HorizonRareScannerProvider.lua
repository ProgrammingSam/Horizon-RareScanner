--[[
    Horizon - RareScanner - Provider
    Builds normalized Focus entry tables from the active RareScanner alert
    and registers itself with HorizonSuite's external entry provider system.
]]

local horizon = _G.HorizonSuite
local RS      = _G.HorizonRareScanner
if not horizon or not RS then return end

-- ============================================================================
-- ENTRY BUILDER
-- ============================================================================

-- Maps the RareScanner atlas type to a Focus category and entry flags.
local ATLAS_TO_CATEGORY = {
    npc       = "RARE",
    event     = "RARE",
    container = "RARE_LOOT",
}

--- Classify a RareScanner atlasName into a simple type key.
--- @param atlasName string|nil
--- @return string  "npc" | "container" | "event"
local function ClassifyAtlas(atlasName)
    if not atlasName then return "npc" end
    local lower = atlasName:lower()
    if lower:find("loot") or lower:find("container") or lower:find("chest") then
        return "container"
    end
    if lower:find("event") then
        return "event"
    end
    return "npc"
end

--- Build objective lines for loot items from the alert's loot table.
--- Returns up to 5 items; silently skips uncached items.
--- @param loot table  array of itemIDs
--- @return table  array of {text, finished} objective entries
local function BuildLootObjectives(loot)
    local objs = {}
    for _, itemID in ipairs(loot) do
        if #objs >= 5 then break end
        local name, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
        if name then
            local iconStr = texture and ("|T" .. texture .. ":12:12:0:0|t ") or ""
            objs[#objs + 1] = { text = iconStr .. name, finished = false }
        end
    end
    return objs
end

--- Return the Focus entry list for the current active RareScanner alert.
--- Returns an empty table when the module is disabled, the integration is
--- toggled off for this entity type, or no alert is active.
--- @return table
local function CollectRareScannerEntries()
    -- Respect the module-level enable toggle (Modules tab in options).
    if not horizon:IsModuleEnabled("rarescanner") then return {} end

    if #RS.alertOrder == 0 or RS.alertIndex == 0 then return {} end
    local entityID = RS.alertOrder[RS.alertIndex]
    local alert    = entityID and RS.alertQueue[entityID]
    if not alert then return {} end

    local atlasType = ClassifyAtlas(alert.atlasName)

    -- Respect the per-type toggles from the Integrations options tab.
    if atlasType == "npc"       and not horizon.GetDB("rs_showRares",     true) then return {} end
    if atlasType == "container" and not horizon.GetDB("rs_showTreasures", true) then return {} end
    if atlasType == "event"     and not horizon.GetDB("rs_showEvents",    true) then return {} end

    local category  = ATLAS_TO_CATEGORY[atlasType] or "RARE"
    local color     = horizon.GetQuestColor and horizon.GetQuestColor(category)
                      or { r = 1, g = 0.2, b = 0.2 }

    local isRare     = (category == "RARE")
    local isRareLoot = (category == "RARE_LOOT")
    local isNPC      = (atlasType == "npc")

    local objectives = {}

    if horizon.GetDB("rs_showCoords", true) and alert.x and alert.y then
        objectives[#objectives + 1] = { text = ("%.1f, %.1f"):format(alert.x * 100, alert.y * 100), finished = false }
    end

    if horizon.GetDB("rs_showLoot", true) and alert.loot and #alert.loot > 0 then
        local lootObjs = BuildLootObjectives(alert.loot)
        for _, obj in ipairs(lootObjs) do
            objectives[#objectives + 1] = obj
        end
    end

    return {
        {
            entryKey       = "rarescanner:" .. tostring(alert.entityID),
            questID        = nil,
            title          = alert.name,
            objectives     = objectives,
            color          = color,
            category       = category,
            isComplete     = false,
            isSuperTracked = false,
            isNearby       = true,
            isRare         = isRare,
            isRareLoot     = isRareLoot,
            creatureID     = tonumber(alert.entityID),
            vignetteMapID  = alert.mapID,
            vignetteX      = alert.x,
            vignetteY      = alert.y,
            zoneName       = alert.zoneName,
            rsIsNPC        = isNPC,
            rsAlertIndex   = RS.alertIndex,
            rsAlertTotal   = #RS.alertOrder,
        },
    }
end

-- ============================================================================
-- REGISTRATION
-- ============================================================================

if horizon.RegisterFocusEntryProvider then
    horizon.RegisterFocusEntryProvider(CollectRareScannerEntries)
end
