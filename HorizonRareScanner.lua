--[[
    Horizon - RareScanner
    Namespace, version, and DB access helpers.
    Requires HorizonSuite. RareScanner is optional; gracefully absent.
]]

local horizon = _G.HorizonSuite
if not horizon then return end

-- ============================================================================
-- NAMESPACE
-- ============================================================================

local RS = {}
_G.HorizonRareScanner = RS

RS.ADDON_NAME    = "Horizon-RareScanner"
RS.VERSION       = "1.0.0"
RS.DB_PREFIX     = "rs_"

-- ============================================================================
-- DB HELPERS (stored inside HorizonSuite's HorizonDB via its GetDB/SetDB)
-- ============================================================================

--- Read a setting from HorizonSuite's DB under the rs_ namespace.
--- @param key string
--- @param default any
--- @return any
function RS.GetDB(key, default)
    return horizon.GetDB(RS.DB_PREFIX .. key, default)
end

--- Write a setting into HorizonSuite's DB under the rs_ namespace.
--- @param key string
--- @param value any
function RS.SetDB(key, value)
    horizon.SetDB(RS.DB_PREFIX .. key, value)
end

-- ============================================================================
-- ACTIVE ALERT STATE
-- The current RareScanner alert being injected into the Focus tracker.
-- Populated by HorizonRareScannerEvents and consumed by HorizonRareScannerProvider.
-- ============================================================================

RS.activeAlert = nil  -- table | nil: { entityID, name, atlasName, category, mapID, x, y, zoneName }
