-- ~/.config/hypr/lua/monitors.lua
-- Generic screen setup: every connected screen at its preferred mode and
-- refresh rate, placed side by side automatically, scale 1.
--
-- To lay out your own screens, add hl.monitor lines inside M.apply() below,
-- after the catch-all one. `hyprctl monitors` prints each output's name.
-- Example (left screen at 0x0, a 1.25-scaled one to its right):
--
--     hl.monitor({ output = "<name-1>", mode = "1920x1080@60", position = "0x0", scale = 1 })
--     hl.monitor({ output = "<name-2>", mode = "preferred", position = "auto-right", scale = 1.25 })

---@module 'hl'

local M = {}

-- The screen workspace 1 (and the bar) belong on. Empty = no preference:
-- Hyprland uses whichever screen comes up first. lua/rules.lua reads it.
local PRIMARY = ""

function M.primary()
    return PRIMARY
end

-- No screen is assumed HDR-capable.
M.hdr_capable = {}

function M.apply()
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
end

M.apply()

return M
