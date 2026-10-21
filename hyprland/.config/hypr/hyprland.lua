-- ~/.config/hypr/hyprland.lua -- Carino Hyprland (needs Hyprland >= 0.55, Lua config)
--
-- This file is only the INDEX. The config lives in ~/.config/hypr/lua/, one
-- module per concern:
--
--   lua/shared.lua      values more than one module needs (mainMod, scrDir)
--   lua/monitors.lua    every screen at its preferred mode, side by side
--   lua/rules.lua       window rules, layer rules, workspace rules
--   lua/env.lua         hl.env
--   lua/settings.lua    the main hl.config block (+ lua/input.lua)
--   lua/display.lua     the theme's look (~/.config/themes/), animations
--   lua/binds.lua       every key bind
--   lua/autostart.lua   hl.on("hyprland.start"): bar, wallpaper, daemons
--
-- require("lua.x") finds ~/.config/hypr/lua/x.lua: Hyprland's package.path
-- starts with ~/.config/hypr/?.lua. The "lua." prefix keeps a module name from
-- colliding with a system Lua module of the same name.
--
-- ORDER MATTERS: rules first (window rules apply in declaration order),
-- settings before display and binds, autostart last.
-- `hyprctl configerrors` names the module and line of any error.

---@module 'hl'

require("lua.monitors")
require("lua.rules")
require("lua.env")
require("lua.settings")
require("lua.display")
require("lua.binds")
require("lua.autostart")
