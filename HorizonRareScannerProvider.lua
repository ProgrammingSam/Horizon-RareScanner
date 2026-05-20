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
    -- VignetteLoot and variants
    if lower:find("loot") or lower:find("container") or lower:find("chest") then
        return "container"
    end
    -- VignetteEvent and variants
    if lower:find("event") then
        return "event"
    end
    return "npc"
end

--- Return the Focus entry list for the current active RareScanner alert.
--- Returns an empty table when the integration is disabled or no alert is active.
--- @return table
local function CollectRareScannerEntries()
    if not RS.GetDB("enabled", true) then return {} end

    local alert = RS.activeAlert
    if not alert then return {} end

    local atlasType = ClassifyAtlas(alert.atlasName)
    local category  = ATLAS_TO_CATEGORY[atlasType] or "RARE"
    local color     = horizon.GetQuestColor and horizon.GetQuestColor(category)
                      or { r = 1, g = 0.2, b = 0.2 }

    local isRare     = (category == "RARE")
    local isRareLoot = (category == "RARE_LOOT")

    return {
        {
            entryKey       = "rarescanner:" .. tostring(alert.entityID),
            questID        = nil,
            title          = alert.name,
            objectives     = {},
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
        },
    }
end

-- ============================================================================
-- REGISTRATION
-- ============================================================================

if horizon.RegisterFocusEntryProvider then
    horizon.RegisterFocusEntryProvider(CollectRareScannerEntries)
end
