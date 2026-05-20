--[[
    Horizon - RareScanner - Module
    Registers this addon as a HorizonSuite module so it appears in the
    Modules list and respects the global enable/disable toggle.
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
        RS.SetDB("enabled", true)
        -- If an alert was already active before the module was enabled, refresh now.
        if RS.activeAlert and horizon.ScheduleRefresh then
            horizon.ScheduleRefresh()
        end
    end,

    OnDisable = function()
        RS.SetDB("enabled", false)
        -- Clear any active alert from the tracker immediately.
        if RS.activeAlert then
            RS.activeAlert = nil
            if horizon.ScheduleRefresh then horizon.ScheduleRefresh() end
        end
    end,
})
