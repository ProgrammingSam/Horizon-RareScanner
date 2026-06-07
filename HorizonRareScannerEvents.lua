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

local RS_BUTTON_NAME        = "RARESCANNER_BUTTON"
local RS_MAX_ALERTS_MIN     = 1
local RS_MAX_ALERTS_MAX     = 10
local RS_MAX_ALERTS_DEFAULT = 4

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

-- ============================================================================
-- SEEN-AGO TIMER
-- Fires every 60 s while the queue is non-empty to keep "X ago" text fresh.
-- ============================================================================

local seenAgoTimerActive = false

local function RunSeenAgoTick()
    if #RS.alertOrder == 0 then
        seenAgoTimerActive = false
        return
    end
    if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
    C_Timer.After(60, RunSeenAgoTick)
end

local function StartSeenAgoTimer()
    if seenAgoTimerActive then return end
    seenAgoTimerActive = true
    C_Timer.After(60, RunSeenAgoTick)
end

-- ============================================================================
-- BUTTON HOOK
-- ============================================================================

local hooked = false
local suppressingNativePopup = false
local observedAlertKey

--- Hook ShowButton / HideButton on the RareScanner scanner button.
--- Safe to call more than once; subsequent calls are no-ops.
local function HookScannerButton()
    if hooked then return end
    local btn = _G[RS_BUTTON_NAME]
    if not btn then return end
    hooked = true

    -- Expose the frame so Horizon Suite can suppress it directly without
    -- re-resolving the button name on its own side.
    RS.alertFrame = btn

    -- HookScript fires in the same clean context as RS's Show()/Hide() calls (which come
    -- from WoW event handlers). Unlike hooksecurefunc on a SecureActionButton method,
    -- HookScript is registered at the C level by WoW and does not create a C/Lua security
    -- boundary crossing, so it never introduces taint into the ScheduleRefresh chain.

    local function CaptureShownAlert(self)
        if not RS.GetDB("enabled", true) then return end

        local entityID = self.entityID
        local name     = self.name
        if not entityID or not name then return end

        local alertKey = tostring(entityID) .. ":" .. tostring(name) .. ":" .. tostring(self.atlasName or "")
        if alertKey == observedAlertKey then return end
        observedAlertKey = alertKey

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
            -- Update existing alert and navigate to it; preserve original seenAt.
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
                seenAt    = GetTime(),
            }
            RS.alertOrder[#RS.alertOrder + 1] = entityID
            RS.alertIndex = #RS.alertOrder
            StartSeenAgoTimer()

            -- FIFO trim: drop oldest entries when queue exceeds the configured limit.
            local maxAlerts = math.max(RS_MAX_ALERTS_MIN,
                math.min(RS_MAX_ALERTS_MAX,
                    horizon.GetDB("rs_maxAlerts", RS_MAX_ALERTS_DEFAULT)))
            while #RS.alertOrder > maxAlerts do
                local removed = table.remove(RS.alertOrder, 1)
                RS.alertQueue[removed] = nil
                RS.alertIndex = RS.alertIndex - 1
            end
            if RS.alertIndex < 1 then RS.alertIndex = 1 end
        end

        local alert = RS.alertQueue[RS.alertOrder[RS.alertIndex]]
        local rsModule = horizon.focus and horizon.focus.rs
        if horizon.GetDB("rs_autoWaypoint", false) and rsModule and rsModule.SetWaypoint and alert then
            pcall(rsModule.SetWaypoint, { title = alert.name, vignetteMapID = alert.mapID, vignetteX = alert.x, vignetteY = alert.y })
        end

        -- Suppress the native button while the Focus integration is active.
        -- ApplyPopupSuppression (registered by Horizon Suite on RS) performs full
        -- hide + input-blocking, which alpha alone cannot achieve — an alpha-zero
        -- frame is still hit-testable and will eat clicks over the Focus tracker.
        if horizon.GetDB("rs_enabled", false) then
            suppressingNativePopup = true
            if RS.ApplyPopupSuppression then
                RS.ApplyPopupSuppression(true)
            else
                self:SetAlpha(0)
                if self.ModelView then self.ModelView:SetAlpha(0) end
            end
            C_Timer.After(0, function()
                suppressingNativePopup = false
            end)
        end

        if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
    end

    -- Fired each time RareScanner pops an alert. OnShow can run before
    -- RareScanner finishes assigning entityID/name, so capture on the next tick.
    btn:HookScript("OnShow", function(self)
        C_Timer.After(0, function()
            CaptureShownAlert(self)
        end)
    end)

    btn:HookScript("OnUpdate", function(self)
        CaptureShownAlert(self)
    end)

    -- Fired when the user dismisses the alert or its auto-hide timer expires.
    btn:HookScript("OnHide", function()
        if suppressingNativePopup then return end
        observedAlertKey = nil
        if RS.ApplyPopupSuppression then
            RS.ApplyPopupSuppression(false)
        else
            btn:SetAlpha(1)
            if btn.ModelView then btn.ModelView:SetAlpha(1) end
        end
        -- When the Focus integration is active, the tracker owns the alert lifecycle.
        -- Let the auto-hide timer hide the native button without clearing the queue;
        -- entries are removed explicitly via DismissCurrentAlert (symmetric with SD).
        if horizon.GetDB("rs_enabled", false) then
            if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
            return
        end
        if #RS.alertOrder > 0 then
            RS.alertQueue = {}
            RS.alertOrder = {}
            RS.alertIndex = 0
            seenAgoTimerActive = false
            if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
        end
    end)

    -- DisplayMessages fires before InCombatLockdown() check in ShowAlert, so it
    -- is the earliest point we can capture a new alert — even during combat when
    -- ShowButton() is deferred and OnShow never fires until combat ends.
    -- Pre-populating alertOrder here lets the Focus tracker show the entry
    -- immediately; OnShow updates coords/atlasName once the button actually shows.
    if btn.DisplayMessages then
        hooksecurefunc(btn, "DisplayMessages", function(self, entityID, name)
            if not RS.GetDB("enabled", true) then return end
            if not entityID or not name then return end
            -- Skip if already in queue (OnShow may have already added it).
            for _, eid in ipairs(RS.alertOrder) do
                if eid == entityID then return end
            end
            local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
            RS.alertQueue[entityID] = {
                entityID  = entityID,
                name      = name,
                atlasName = nil, -- unknown at this stage; OnShow updates it
                mapID     = mapID,
                x         = nil,
                y         = nil,
                zoneName  = nil,
                loot      = {},
                seenAt    = GetTime(),
            }
            RS.alertOrder[#RS.alertOrder + 1] = entityID
            RS.alertIndex = #RS.alertOrder
            StartSeenAgoTimer()
            local maxAlerts = math.max(RS_MAX_ALERTS_MIN,
                math.min(RS_MAX_ALERTS_MAX,
                    horizon.GetDB("rs_maxAlerts", RS_MAX_ALERTS_DEFAULT)))
            while #RS.alertOrder > maxAlerts do
                local removed = table.remove(RS.alertOrder, 1)
                RS.alertQueue[removed] = nil
                RS.alertIndex = RS.alertIndex - 1
            end
            if RS.alertIndex < 1 then RS.alertIndex = 1 end
            if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
        end)
    end

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
-- Kill detection uses PARTY_KILL (passes attacker GUID + target GUID), which
-- lets us extract npcID without parsing the combat log. Registered at module
-- level on the shared eventFrame — same pattern as ADDON_LOADED — so
-- RegisterEvent runs in the safe main-chunk initialization context.
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PARTY_KILL")
eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        -- Try to hook on RareScanner's own ADDON_LOADED, or on ours if RS was
        -- already loaded before this addon (e.g. alphabetical load order).
        if arg1 == "RareScanner" or arg1 == RS.ADDON_NAME then
            -- Defer one frame so RareScanner finishes its OnLoad before we hook.
            C_Timer.After(0, HookScannerButton)
        end

    elseif event == "PARTY_KILL" then
        -- arg1 = attacker GUID, arg2 = target (killed unit) GUID
        local destGUID = arg2
        if not destGUID or not RS.alertOrder then return end
        local npcID = tonumber(destGUID:match("Creature%-0%-%d+%-%d+%-%d+%-(%d+)%-"))
        if not npcID then return end
        for i, entityID in ipairs(RS.alertOrder) do
            if entityID == npcID then
                table.remove(RS.alertOrder, i)
                RS.alertQueue[npcID] = nil
                if RS.alertIndex > i then
                    RS.alertIndex = RS.alertIndex - 1
                elseif RS.alertIndex >= i then
                    RS.alertIndex = math.max(0, math.min(RS.alertIndex, #RS.alertOrder))
                end
                if #RS.alertOrder == 0 then RS.alertIndex = 0 end
                if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
                return
            end
        end
    end
end)

-- Safety net: if RareScanner was loaded before us and we missed ADDON_LOADED,
-- attempt the hook immediately.
C_Timer.After(0, HookScannerButton)
