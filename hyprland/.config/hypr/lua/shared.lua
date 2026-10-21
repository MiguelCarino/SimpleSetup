-- ~/.config/hypr/lua/shared.lua
-- The values more than one module needs, in ONE table, returned to whoever
-- requires it. This is the replacement for the file-level locals of the
-- single-file config: a `local` cannot cross a file boundary, and making them
-- globals instead would let any typo silently create a new one.
--
--   local S = require("lua.shared")
--   local mainMod = S.mainMod
--
-- require() caches the module, so every caller in one config load gets the SAME
-- table -- there is one mainMod, not one per module. A `hyprctl
-- reload` starts from a fresh Lua state, so editing this file and reloading
-- always picks up the new values.
--
-- Values that only one module uses stay local to it (resize_delta and
-- monitor_dir in lua/binds.lua).

---@module 'hl'

local M = {}

-- ========================= Variables =========================
-- mainMod is ALT: the whole Carino keymap is built on it (README.md lists the
-- keys). Change it to "SUPER" here if you prefer; SUPER binds stay as they are.
local mainMod = "ALT"
local scrDir  = (os.getenv("HOME") or "") .. "/Pictures/Screenshots"

M.mainMod          = mainMod
M.scrDir           = scrDir

-- ========================= Display state =========================
-- Choices that must survive a reload, kept in one small key=value file:
--
--   ~/.local/state/hypr/display.conf
--     theme=cyberpunk         desktop theme, ~/.config/themes/<name>/ (lua/display.lua)
--     anim=smooth             animation preset: snappy smooth fancy calm
--     filter=grayscale        screen filter from ~/.config/hypr/shaders/, or empty
--     accent=#4fc3ff          focused-border accent, or empty
--     cursor_size=24          pointer size (lua/env.lua)
--
-- A missing file or key means "the config's own default", so deleting the
-- file is always a full reset. Keyboard, mouse and touchpad choices follow
-- the same pattern in ~/.local/state/hypr/input.conf (lua/input.lua lists
-- the keys and their defaults). Not JSON: Hyprland's Lua has no JSON parser,
-- and a line per key is trivial to edit by hand.
M.state_file = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state"))
               .. "/hypr/display.conf"

-- One key=value file, read into a table; nil when the file cannot be opened
-- (so a caller can tell "missing" from "empty"). Lines starting with # are
-- comments. Also the reader for the themes' theme.conf (lua/display.lua),
-- which is the same format on purpose.
function M.read_kv(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local t = {}
    for line in f:lines() do
        if not line:match("^%s*#") then
            local k, v = line:match("^%s*([%w%._%-]+)%s*=%s*(.-)%s*$")
            if k then t[k] = v end
        end
    end
    f:close()
    return t
end

function M.state()
    return M.read_kv(M.state_file) or {}
end

return M
