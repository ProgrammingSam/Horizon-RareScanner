--[[
    Horizon - RareScanner - Module
    Registers this addon as a HorizonSuite module so it appears in the
    Modules list and respects the global enable/disable toggle.
    The provider reads horizon:IsModuleEnabled("rarescanner") directly,
    so no separate DB flag is needed here.
]]

local horizon = _G.HorizonSuite
local RS      = _G.HorizonRareScanner
if not horizon or not RS or not horizon.RegisterModule then return end

-- ============================================================================
-- MODULE REGISTRATION
-- ============================================================================

horizon:RegisterModule("rarescanner", {
    title       = "RareScanner",
    description = "Shows active RareScanner alerts inside the Focus tracker.",
    order       = 60,

    OnInit = function()
        -- Nothing to initialise at load time; hooks are set up by Events.
    end,

    OnEnable = function()
        -- If alerts were already queued before the module was enabled, refresh.
        if #RS.alertOrder > 0 and horizon.ScheduleRefresh then
            horizon.ScheduleRefresh()
        end
    end,

    OnDisable = function()
        -- Clear any active alerts from the tracker immediately.
        RS.alertQueue = {}
        RS.alertOrder = {}
        RS.alertIndex = 0
        if horizon.ScheduleRefresh then
            horizon.ScheduleRefresh()
        end
    end,
})

-- ============================================================================
-- AUTO-ENABLE
-- HorizonSuite's ADDON_LOADED enable-pass runs before this companion addon
-- loads, so "rarescanner" is never in the iteration. We restore the persisted
-- state here instead: auto-enable on first install, respect explicit disables.
-- ============================================================================

local db    = _G[horizon.DATABASE]
local modDb = db and db.modules and db.modules["rarescanner"]
if modDb and modDb.enabled == false then
    -- User explicitly disabled the module via the Modules panel — respect it.
else
    horizon:EnableModule("rarescanner")
end
