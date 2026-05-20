--[[
    Horizon - RareScanner - Events
    Hooks into the RareScanner scanner button (RARESCANNER_BUTTON) once it is
    loaded, tracks the active alert, and asks HorizonSuite to refresh the
    Focus tracker whenever an alert appears or disappears.
]]

local horizon = _G.HorizonSuite
local RS      = _G.HorizonRareScanner
if not horizon or not RS then return end

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local RS_BUTTON_NAME = "RARESCANNER_BUTTON"

-- ============================================================================
-- ALERT HELPERS
-- ============================================================================

--- Resolve a 0..1 map position for entityID from the live vignette list.
--- Falls back to nil if no matching vignette is found.
--- @param entityID number
--- @param mapID number|nil
--- @return number|nil x, number|nil y
local function ResolveVignettePosition(entityID, mapID)
    if not entityID or not mapID then return nil, nil end
    if not (C_VignetteInfo and C_VignetteInfo.GetVignettes and C_VignetteInfo.GetVignetteInfo) then
        return nil, nil
    end
    local vignettes = C_VignetteInfo.GetVignettes()
    if not vignettes then return nil, nil end
    for _, guid in ipairs(vignettes) do
        local vi = C_VignetteInfo.GetVignetteInfo(guid)
        if vi and vi.objectGUID then
            local _, _, _, _, _, id = strsplit("-", vi.objectGUID)
            if tonumber(id) == entityID and C_VignetteInfo.GetVignettePosition then
                local ok, pos = pcall(C_VignetteInfo.GetVignettePosition, guid, mapID)
                if ok and pos then
                    return pos.x, pos.y
                end
            end
        end
    end
    return nil, nil
end

--- Resolve the zone name for a given uiMapID.
--- @param mapID number|nil
--- @return string|nil
local function ResolveZoneName(mapID)
    if not mapID or not (C_Map and C_Map.GetMapInfo) then return nil end
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or nil
end

-- ============================================================================
-- BUTTON HOOK
-- ============================================================================

local hooked = false

--- Hook ShowButton / HideButton on the RareScanner scanner button.
--- Safe to call more than once; subsequent calls are no-ops.
local function HookScannerButton()
    if hooked then return end
    local btn = _G[RS_BUTTON_NAME]
    if not btn then return end
    hooked = true

    -- Fired each time RareScanner pops an alert (including navigation).
    hooksecurefunc(btn, "ShowButton", function(self)
        if not RS.GetDB("enabled", true) then return end

        local entityID = self.entityID
        local name     = self.name
        if not entityID or not name then return end

        -- Deduplicate: skip if same entity is already the active alert.
        if RS.activeAlert and RS.activeAlert.entityID == entityID then return end

        local mapID    = self.mapID
                         or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
        local x, y    = ResolveVignettePosition(entityID, mapID)
        local zoneName = ResolveZoneName(mapID)

        RS.activeAlert = {
            entityID  = entityID,
            name      = name,
            atlasName = self.atlasName,
            mapID     = mapID,
            x         = x,
            y         = y,
            zoneName  = zoneName,
        }

        if horizon.GetDB("rs_autoWaypoint", false) and horizon.SetRareWaypoint then
            pcall(horizon.SetRareWaypoint, { title = name, vignetteMapID = mapID, vignetteX = x, vignetteY = y })
        end

        if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
    end)

    -- Fired when the user dismisses the alert or its auto-hide timer expires.
    hooksecurefunc(btn, "HideButton", function()
        if RS.activeAlert then
            RS.activeAlert = nil
            if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
        end
    end)
end

-- ============================================================================
-- EVENT FRAME
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, _, addonName)
    -- Try to hook on RareScanner's own ADDON_LOADED, or on ours if RS was
    -- already loaded before this addon (e.g. alphabetical load order).
    if addonName == "RareScanner" or addonName == RS.ADDON_NAME then
        -- Defer one frame so RareScanner finishes its OnLoad before we hook.
        C_Timer.After(0, HookScannerButton)
    end
end)

-- Safety net: if RareScanner was loaded before us and we missed ADDON_LOADED,
-- attempt the hook immediately.
C_Timer.After(0, HookScannerButton)
