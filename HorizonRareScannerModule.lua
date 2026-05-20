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
        -- If an alert was already active before the module was enabled, refresh.
        if RS.activeAlert and horizon.ScheduleRefresh then
            horizon.ScheduleRefresh()
        end
    end,

    OnDisable = function()
        -- Clear any active alert from the tracker immediately.
        if RS.activeAlert then
            RS.activeAlert = nil
        end
        if horizon.ScheduleRefresh then
            horizon.ScheduleRefresh()
        end
    end,
})
