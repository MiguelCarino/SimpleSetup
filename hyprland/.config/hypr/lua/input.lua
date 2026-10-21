-- ~/.config/hypr/lua/input.lua
-- Required from the end of lua/settings.lua. Keyboard, mouse and touchpad:
-- every input.* option the desktop sets, plus the two pointer habits that
-- live in other sections (cursor.hide_on_key_press, misc.middle_click_paste).
--
-- The values can be changed without touching this file: write them into
-- their own small key=value file, the same format as the display state
-- (lua/shared.lua explains both), then `hyprctl reload`:
--
--   ~/.local/state/hypr/input.conf
--
--   e.g.  layouts=us,de        repeat_rate=40        natural_scroll=on
--
-- A missing key means DEFAULTS below, so deleting the file is a full reset.
-- This module applies the file at every config load, so a reload and a
-- re-login both put the choices back.

---@module 'hl'

local S = require("lua.shared")

local M = {}

M.state_file = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state"))
               .. "/hypr/input.conf"

-- ========================= Defaults =========================
-- Strings, in the state file's own format (keep one `["key"] = "value",`
-- per line). Hyprland's own defaults except where noted.
--
--   layouts     the xkb layouts in switching order, a variant in brackets:
--               "us", "us,de" or "us(intl),es". xkb allows at most 4.
--   switch      the xkb option that switches layout ("grp:win_space_toggle"
--               is SUPER+Space). Empty = no key. Not a Hyprland bind, so `hyprctl binds`
--               does not list it.
--   caps        what Caps Lock does (an xkb caps:/ctrl: option), or empty
--   compose     the Compose key (an xkb compose: option), or empty
--   xkb_extra   any other xkb options, comma separated, passed through
--   follow_mouse  0 click to focus, 1 focus follows the mouse, 2 click
--               focuses but the hovered window gets the scroll wheel
-- INPUT-DEFAULTS-BEGIN
local DEFAULTS = {
    ["layouts"]                    = "us",
    ["switch"]                     = "grp:win_space_toggle",
    ["caps"]                       = "",
    ["compose"]                    = "",
    ["xkb_extra"]                  = "",
    ["repeat_rate"]                = "25",
    ["repeat_delay"]               = "600",
    ["numlock"]                    = "off",
    ["sensitivity"]                = "0",
    ["accel"]                      = "adaptive",
    ["natural_scroll"]             = "off",
    ["left_handed"]                = "off",
    ["scroll_factor"]              = "1",
    ["middle_click_paste"]         = "on",
    ["hide_on_typing"]             = "off",
    ["follow_mouse"]               = "1",
    ["touchpad.natural_scroll"]    = "off",
    ["touchpad.tap_to_click"]      = "on",
    ["touchpad.disable_while_typing"] = "on",
    ["touchpad.clickfinger"]       = "off",
    ["touchpad.scroll_factor"]     = "1",
}
-- INPUT-DEFAULTS-END
M.defaults = DEFAULTS

-- ========================= Reading =========================
-- A value from the state file when it is there and usable, else the
-- default: a hand-edited file with "repeat_rate=fast" falls back to 25 for
-- that one key instead of breaking the whole config load.
local function flag(v)
    return v == "on" or v == "yes" or v == "true" or v == "1"
end

local function number(st, key, lo, hi)
    local n = tonumber(st[key])
    if n == nil or n < lo or n > hi then n = tonumber(DEFAULTS[key]) end
    return n
end

local function str(st, key)
    local v = st[key]
    if v == nil then v = DEFAULTS[key] end
    return v
end

local function bool(st, key)
    return flag(str(st, key))
end

-- "us,es(deadtilde)" -> kb_layout "us,es", kb_variant ",deadtilde".
-- kb_variant stays "" when no layout has one (what Hyprland had before).
function M.split_layouts(spec)
    local codes, variants, any = {}, {}, false
    for tok in (spec or ""):gmatch("[^,%s]+") do
        local code, variant = tok:match("^([%w_%-]+)%(([%w_%-]*)%)$")
        if not code then code, variant = tok, "" end
        if code:match("^[%w_%-]+$") and #codes < 4 then
            codes[#codes + 1] = code
            variants[#variants + 1] = variant
            if variant ~= "" then any = true end
        end
    end
    if #codes == 0 then return M.split_layouts(DEFAULTS.layouts) end
    return table.concat(codes, ","), any and table.concat(variants, ",") or ""
end

-- switch, caps, compose and the extras, as one kb_options string.
local function xkb_options(st)
    local parts = {}
    for _, key in ipairs({ "switch", "caps", "compose", "xkb_extra" }) do
        for opt in str(st, key):gmatch("[^,%s]+") do
            if opt:match("^[%w_%-]+:[%w_%-]+$") then parts[#parts + 1] = opt end
        end
    end
    return table.concat(parts, ",")
end

function M.state()
    return S.read_kv(M.state_file) or {}
end

-- ========================= Apply =========================
function M.apply()
    local st = M.state()
    local layout, variant = M.split_layouts(str(st, "layouts"))
    local accel = str(st, "accel")
    if accel ~= "flat" and accel ~= "adaptive" then accel = DEFAULTS.accel end
    local follow = number(st, "follow_mouse", 0, 3)
    hl.config({
        input = {
            kb_layout          = layout,
            kb_variant         = variant,
            kb_options         = xkb_options(st),
            repeat_rate        = math.floor(number(st, "repeat_rate", 1, 100)),
            repeat_delay       = math.floor(number(st, "repeat_delay", 100, 2000)),
            numlock_by_default = bool(st, "numlock"),
            sensitivity        = number(st, "sensitivity", -1, 1),
            accel_profile      = accel,
            natural_scroll     = bool(st, "natural_scroll"),
            left_handed        = bool(st, "left_handed"),
            scroll_factor      = number(st, "scroll_factor", 0.1, 5),
            follow_mouse       = math.floor(follow),
            touchpad = {
                natural_scroll       = bool(st, "touchpad.natural_scroll"),
                tap_to_click         = bool(st, "touchpad.tap_to_click"),
                disable_while_typing = bool(st, "touchpad.disable_while_typing"),
                clickfinger_behavior = bool(st, "touchpad.clickfinger"),
                scroll_factor        = number(st, "touchpad.scroll_factor", 0.1, 5),
            },
        },
        cursor = { hide_on_key_press = bool(st, "hide_on_typing") },
        misc   = { middle_click_paste = bool(st, "middle_click_paste") },
    })
end

M.apply()

return M
