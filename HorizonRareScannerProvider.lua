--[[
    Horizon - RareScanner - Provider
    Builds normalized Focus entry tables from the active RareScanner alert
    and registers itself with HorizonSuite's external entry provider system.
]]

local horizon = _G.HorizonSuite
local RS      = _G.HorizonRareScanner
if not horizon or not RS then return end

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local RS_MIN_LOOT_QUALITY_MIN     = 0
local RS_MIN_LOOT_QUALITY_MAX     = 5
local RS_MIN_LOOT_QUALITY_DEFAULT = 2

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
    if lower:find("loot") or lower:find("treasure") or lower:find("container")
        or lower:find("chest") or lower:find("object") or lower:find("interact") then
        return "container"
    end
    if lower:find("event") then
        return "event"
    end
    return "npc"
end

-- When item data is missing from cache, we request it and listen for the
-- GET_ITEM_INFO_RECEIVED event to refresh Focus once it arrives.
local rsItemRefreshFrame

local function EnsureItemRefreshListener()
    if rsItemRefreshFrame then return end
    rsItemRefreshFrame = CreateFrame("Frame")
    rsItemRefreshFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    rsItemRefreshFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        rsItemRefreshFrame = nil
        if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
    end)
end

--- Return itemIDs from loot filtered to the configured minimum quality,
--- sorted by quality descending.  Items not yet in the client cache are
--- requested via RequestLoadItemDataByID; a refresh fires on arrival.
--- @param loot table  array of itemIDs
--- @return table  filtered+sorted array of itemIDs
local function FilterLootByQuality(loot)
    if not loot or #loot == 0 then return {} end
    local minQ = math.max(RS_MIN_LOOT_QUALITY_MIN,
        math.min(RS_MIN_LOOT_QUALITY_MAX,
            tonumber(horizon.GetDB("rs_minLootQuality", RS_MIN_LOOT_QUALITY_DEFAULT))
            or RS_MIN_LOOT_QUALITY_DEFAULT))
    local out = {}
    for _, itemID in ipairs(loot) do
        local _, _, quality = C_Item.GetItemInfo(itemID)
        if quality == nil then
            -- Item not yet in cache: request it and refresh Focus when it arrives.
            C_Item.RequestLoadItemDataByID(itemID)
            EnsureItemRefreshListener()
        elseif minQ == 0 or quality >= minQ then
            out[#out + 1] = { id = itemID, q = quality }
        end
    end
    table.sort(out, function(a, b) return a.q > b.q end)
    local result = {}
    for _, item in ipairs(out) do result[#result + 1] = item.id end
    return result
end

--- Return the Focus entry list for the current active RareScanner alert.
--- Returns an empty table when the module is disabled, the integration is
--- toggled off for this entity type, or no alert is active.
--- @return table
local function CollectRareScannerEntries()
    if not horizon.GetDB("rs_enabled", false) then return {} end

    if #RS.alertOrder == 0 or RS.alertIndex == 0 then return {} end
    local entityID = RS.alertOrder[RS.alertIndex]
    local alert    = entityID and RS.alertQueue[entityID]
    if not alert then return {} end

    local atlasType    = ClassifyAtlas(alert.atlasName)
    local vignetteAtlas = (atlasType == "container") and "VignetteLoot" or "VignetteKillElite"

    -- Respect the per-type toggles from the Integrations options tab.
    if atlasType == "npc"       and not horizon.GetDB("rs_showRares",     true) then return {} end
    if atlasType == "container" and not horizon.GetDB("rs_showTreasures", true) then return {} end
    if atlasType == "event"     and not horizon.GetDB("rs_showEvents",    true) then return {} end

    local rsCategory = ATLAS_TO_CATEGORY[atlasType] or "RARE"  -- "RARE" or "RARE_LOOT" (sub-type)
    local color      = horizon.GetQuestColor and horizon.GetQuestColor("RARESCANNER")
                       or { r = 1, g = 0.2, b = 0.2 }

    local isRare     = (rsCategory == "RARE")
    local isRareLoot = (rsCategory == "RARE_LOOT")
    local isNPC      = (atlasType == "npc")

    local objectives = {}

    if horizon.GetDB("rs_showCoords", true) and alert.x and alert.y then
        objectives[#objectives + 1] = { text = ("%.1f, %.1f"):format(alert.x * 100, alert.y * 100), finished = false, noBullet = true, rsCoord = true }
    end

    if horizon.GetDB("rs_showSeenAgo", true) and alert.seenAt then
        local text = horizon.FormatTimeAgo and horizon.FormatTimeAgo(alert.seenAt)
        if text then
            objectives[#objectives + 1] = { text = text, finished = false, noBullet = true, rareSeenAgo = true }
        end
    end

    local rsLoot = {}
    if horizon.GetDB("rs_showLoot", true) and alert.loot and #alert.loot > 0 then
        rsLoot = FilterLootByQuality(alert.loot)
    end

    -- Kill state: append colored suffix and flag for model desaturation + flash.
    local title = alert.name
    local rareIsKilled = alert.killedAt ~= nil
    local triggerFlash = false
    local FLASH_WINDOW = 0.6
    if rareIsKilled then
        title = (title or "") .. " |cffff5533(Killed)|r"
        triggerFlash = (GetTime() - alert.killedAt) < FLASH_WINDOW
    end

    return {
        {
            entryKey       = "rarescanner:" .. tostring(alert.entityID),
            questID        = nil,
            title          = title,
            objectives     = objectives,
            color          = color,
            category       = "RARESCANNER",
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
            rsAtlasName    = alert.atlasName,
            vignetteAtlas  = vignetteAtlas,
            rsLoot         = rsLoot,
            rsAlertIndex   = RS.alertIndex,
            rsAlertTotal   = #RS.alertOrder,
            noEntryNumber  = true,
            rareIsKilled   = rareIsKilled,
            triggerFlash   = triggerFlash,
        },
    }
end

-- ============================================================================
-- REGISTRATION
-- ============================================================================

if horizon.RegisterFocusEntryProvider then
    horizon.RegisterFocusEntryProvider(CollectRareScannerEntries)
end
