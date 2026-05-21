--[[
    Horizon - RareScanner - Events
    Hooks into the RareScanner scanner button (RARESCANNER_BUTTON) once it is
    loaded, tracks an ordered queue of active alerts, and asks HorizonSuite to
    refresh the Focus tracker whenever an alert appears or disappears.
]]

local horizon = _G.HorizonSuite
local RS      = _G.HorizonRareScanner
if not horizon or not RS then return end

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local RS_BUTTON_NAME = "RARESCANNER_BUTTON"

-- ============================================================================
-- NAVIGATION
-- ============================================================================

RS.NavigatePrev = function()
    if #RS.alertOrder == 0 then return end
    RS.alertIndex = RS.alertIndex - 1
    if RS.alertIndex < 1 then RS.alertIndex = #RS.alertOrder end
    if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
end

RS.NavigateNext = function()
    if #RS.alertOrder == 0 then return end
    RS.alertIndex = RS.alertIndex + 1
    if RS.alertIndex > #RS.alertOrder then RS.alertIndex = 1 end
    if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
end

-- ============================================================================
-- ALERT HELPERS
-- ============================================================================

--- Resolve a 0..1 map position for entityID from the live vignette list.
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

    -- Fired each time RareScanner pops an alert (including its own navigation).
    hooksecurefunc(btn, "ShowButton", function(self)
        if not RS.GetDB("enabled", true) then return end

        local entityID = self.entityID
        local name     = self.name
        if not entityID or not name then return end

        local mapID    = self.mapID
                         or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
        local x, y    = ResolveVignettePosition(entityID, mapID)
        local zoneName = ResolveZoneName(mapID)

        -- Check if already queued (dedup by entityID).
        local existingIdx
        for i, eid in ipairs(RS.alertOrder) do
            if eid == entityID then existingIdx = i; break end
        end

        if existingIdx then
            -- Update existing alert and navigate to it.
            local alert = RS.alertQueue[entityID]
            alert.name      = name
            alert.atlasName = self.atlasName
            alert.mapID     = mapID
            alert.x         = x
            alert.y         = y
            alert.zoneName  = zoneName
            RS.alertIndex   = existingIdx
        else
            RS.alertQueue[entityID] = {
                entityID  = entityID,
                name      = name,
                atlasName = self.atlasName,
                mapID     = mapID,
                x         = x,
                y         = y,
                zoneName  = zoneName,
                loot      = {},
            }
            RS.alertOrder[#RS.alertOrder + 1] = entityID
            RS.alertIndex = #RS.alertOrder
        end

        local alert = RS.alertQueue[RS.alertOrder[RS.alertIndex]]
        if horizon.GetDB("rs_autoWaypoint", false) and horizon.SetRareWaypoint and alert then
            pcall(horizon.SetRareWaypoint, { title = alert.name, vignetteMapID = alert.mapID, vignetteX = alert.x, vignetteY = alert.y })
        end

        -- Suppress RareScanner's own popup frame while the Focus integration is active.
        -- SetAlpha(0) keeps the frame "shown" for RS's internal logic (timers, loot bar
        -- hooks, etc.) while making it invisible and non-interactive to the player.
        if horizon.GetDB("rs_enabled", true) then
            self:SetAlpha(0)
        end

        if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
    end)

    -- Fired when the user dismisses the alert or its auto-hide timer expires.
    hooksecurefunc(btn, "HideButton", function()
        -- Restore alpha so the next alert can show normally if the integration is disabled.
        btn:SetAlpha(1)
        if #RS.alertOrder > 0 then
            RS.alertQueue = {}
            RS.alertOrder = {}
            RS.alertIndex = 0
            if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
        end
    end)

    -- Loot bar hooks: capture item IDs as they load asynchronously.
    local pool = btn.LootBar and btn.LootBar.itemFramesPool
    if pool then
        if pool.InitItemList then
            hooksecurefunc(pool, "InitItemList", function(_, _, entityID)
                if entityID and RS.alertQueue[entityID] then
                    RS.alertQueue[entityID].loot = {}
                end
            end)
        end
        if pool.UpdateCacheItem then
            hooksecurefunc(pool, "UpdateCacheItem", function(_, itemID, entityID)
                if not itemID or not entityID then return end
                if not RS.alertQueue[entityID] then return end
                local loot = RS.alertQueue[entityID].loot
                for _, id in ipairs(loot) do
                    if id == itemID then return end
                end
                loot[#loot + 1] = itemID
                if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
            end)
        end
    end
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
