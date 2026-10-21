-- ~/.config/hypr/lua/env.lua
-- Loaded from ~/.config/hypr/hyprland.lua (the index). hl.env only.
-- XDG_CURRENT_DESKTOP / XDG_SESSION_TYPE / XDG_SESSION_DESKTOP are set by
-- Hyprland itself, so they are not repeated here.

---@module 'hl'

-- ========================= Env =========================
-- The pointer's size and theme. cursor_size and cursor_theme_user can be set
-- in ~/.local/state/hypr/display.conf (lua/shared.lua); otherwise the desktop
-- theme's cursor_theme= is used, then Adwaita, at size 24. Hyprland takes its
-- first cursor from XCURSOR_THEME / XCURSOR_SIZE (and HYPRCURSOR_SIZE for
-- hyprcursor themes), and every app it starts inherits them.
do
    local S = require("lua.shared")
    local st = S.state()
    local size = tonumber(st.cursor_size or "")
    size = (size and size >= 8 and size <= 256) and tostring(math.floor(size)) or "24"
    hl.env("XCURSOR_SIZE", size)
    hl.env("HYPRCURSOR_SIZE", size)
    local home = os.getenv("HOME") or ""
    local function installed(name)
        if not name or name == "" or name:find("/") then return false end
        for _, root in ipairs({ home .. "/.icons", home .. "/.local/share/icons", "/usr/share/icons" }) do
            for _, shape in ipairs({ "default", "left_ptr" }) do
                local f = io.open(root .. "/" .. name .. "/cursors/" .. shape, "r")
                if f then f:close() return true end
            end
        end
        return false
    end
    -- The theme's cursor_theme=, following inherit= (cyberpunk is the base).
    local want = st.cursor_theme_user
    if not installed(want) then
        want = nil
        local themes = home .. "/.config/themes/"
        local name, seen = (st.theme and st.theme ~= "") and st.theme or "cyberpunk", {}
        while name and not seen[name] and not want do
            seen[name] = true
            local conf = S.read_kv(themes .. name .. "/theme.conf")
            if not conf then break end
            if conf.cursor_theme and conf.cursor_theme ~= "" then want = conf.cursor_theme end
            name = (conf.inherit and conf.inherit ~= "") and conf.inherit or (name ~= "cyberpunk" and "cyberpunk" or nil)
        end
        -- No theme names one: Adwaita.
        if not installed(want) then want = installed("Adwaita") and "Adwaita" or nil end
    end
    if want then hl.env("XCURSOR_THEME", want) end
end
hl.env("QT_QPA_PLATFORM", "wayland")
-- Absolute on purpose: env values are not shell-expanded, so a leading ~ would
-- reach apps as a literal character. Same directory the screenshot keys write
-- to (scrDir in lua/shared.lua).
hl.env("XDG_SCREENSHOTS_DIR", (os.getenv("HOME") or "") .. "/Pictures/Screenshots")

-- NVIDIA: nothing is set by default. Recent drivers with nvidia_drm modeset=1
-- need no env vars. If video decode or XWayland apps misbehave, try these
-- (remove the leading "-- " and `hyprctl reload`):
-- hl.env("LIBVA_DRIVER_NAME", "nvidia")
-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
-- hl.env("NVD_BACKEND", "direct")
-- If the cursor glitches: hl.config({ cursor = { no_hardware_cursors = true } })
