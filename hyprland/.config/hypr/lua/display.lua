-- ~/.config/hypr/lua/display.lua
-- Loaded from ~/.config/hypr/hyprland.lua (the index), right after settings.
-- The parts of the look that are chosen at runtime rather than written down:
--
--   desktop theme      ~/.config/themes/<name>/theme.conf: border colours,
--                      rounding, gaps, border size, blur, shadow, and the
--                      theme's own window/layer rules (hypr.lua)
--   animation preset   snappy / smooth / fancy / calm
--   screen filter      a GLSL screen shader from ~/.config/hypr/shaders/
--   accent             the focused-window border, from the wallpaper
--   your window look   hyprlook.* overrides of the theme's look (gaps,
--                      borders, corners, blur, shadow, dimming, the tiling
--                      layout), written by hand into display.conf
--
-- Each choice lives in the display state file (lua/shared.lua explains it) and
-- is applied here at every load, so a reload puts it back instead of dropping
-- to the defaults. To change one: edit ~/.local/state/hypr/display.conf, then
-- `hyprctl reload` (or  hyprctl eval 'require("lua.display").apply()').
--
-- Some of it (themes other than cyberpunk, a "gamemode" switch, the accent
-- and window-look keys) is only used when an external tool writes display.conf;
-- without one it stays idle.

---@module 'hl'

local S = require("lua.shared")

local M = {}

-- ========================= Animations =========================
-- "smooth" is the set that used to sit in lua/settings.lua, unchanged. Its
-- reasoning still holds and still applies to the others:
--
-- Hyprland's stock global speed is 10, and speed is in deciseconds, so the
-- default for anything not overridden was a full second, which reads as the
-- desktop waiting for you. The target is "present but never
-- in the way": nothing a keypress causes takes more than ~0.35 s, and things
-- leaving are faster than things arriving, because you already know where a
-- closed window went.
--
-- easeOutQuint does nearly all the work: it covers most of the distance in
-- the first third of the time, so a 0.3 s animation feels finished at ~0.1 s
-- and the rest is settling. That is what makes short durations look smooth
-- rather than abrupt.
--
-- The other presets:
--   snappy  about 60% of smooth's durations, smaller pop-in. For working fast.
--   fancy   longer, with a slight overshoot on windows arriving and a wider
--           workspace slide. For showing the desktop off.
--   calm    no movement at all, only fades: windows and workspaces cross-fade
--           in place. For when motion is distracting.
--
-- None of them sets animations.enabled = false: that is reserved for an
-- external "gamemode" switch (see Theme below).
hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1},   {0.32, 1}    } })
hl.curve("linear",       { type = "bezier", points = { {0, 0},      {1, 1}       } })
hl.curve("quick",        { type = "bezier", points = { {0.15, 0},   {0.1, 1}     } })
hl.curve("overshot",     { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.08}  } })
hl.curve("easeInOut",    { type = "bezier", points = { {0.65, 0},   {0.35, 1}    } })

--          leaf               speed (ds)  curve           style
local PRESETS = {
    smooth = {
        { "global",           4,   "easeOutQuint" },
        { "border",           4,   "easeOutQuint" },
        { "windowsIn",        3,   "easeOutQuint", "popin 90%" },
        { "windowsOut",       1.8, "linear",       "popin 90%" },
        { "windowsMove",      3,   "easeOutQuint" },
        { "fade",             2.5, "quick" },
        { "layersIn",         2.5, "easeOutQuint", "fade" },
        { "layersOut",        1.5, "linear",       "fade" },
        -- Workspaces slide rather than fade so you can tell which way you
        -- went: e+1 / e-1 (ALT+wheel) and SUPER+Tab get a direction, not just
        -- a cut.
        { "workspaces",       3,   "easeOutQuint", "slidefade 15%" },
        -- Scratchpads (ALT+grave, SUPER+Return, SUPER+A) drop in vertically,
        -- so an overlay never looks like a workspace switch.
        { "specialWorkspace", 3,   "easeOutQuint", "slidefadevert 15%" },
    },
    snappy = {
        { "global",           2.5, "easeOutQuint" },
        { "border",           2.5, "easeOutQuint" },
        { "windowsIn",        1.8, "easeOutQuint", "popin 95%" },
        { "windowsOut",       1.1, "linear",       "popin 95%" },
        { "windowsMove",      1.8, "easeOutQuint" },
        { "fade",             1.5, "quick" },
        { "layersIn",         1.5, "easeOutQuint", "fade" },
        { "layersOut",        1,   "linear",       "fade" },
        { "workspaces",       1.8, "easeOutQuint", "slidefade 10%" },
        { "specialWorkspace", 1.8, "easeOutQuint", "slidefadevert 10%" },
    },
    fancy = {
        { "global",           6,   "easeOutQuint" },
        { "border",           6,   "easeOutQuint" },
        { "windowsIn",        4.5, "overshot",     "popin 75%" },
        { "windowsOut",       2.5, "easeInOut",    "popin 80%" },
        { "windowsMove",      4.5, "overshot" },
        { "fade",             3.5, "quick" },
        { "layersIn",         3.5, "overshot",     "popin 85%" },
        { "layersOut",        2,   "linear",       "fade" },
        { "workspaces",       4.5, "easeOutQuint", "slidefade 30%" },
        { "specialWorkspace", 4.5, "overshot",     "slidefadevert 25%" },
    },
    calm = {
        { "global",           3,   "easeInOut" },
        { "border",           3,   "easeInOut" },
        { "windowsIn",        2.5, "easeInOut",    "popin 100%" },
        { "windowsOut",       2,   "easeInOut",    "popin 100%" },
        { "windowsMove",      0.1, "linear" },
        { "fade",             2.5, "easeInOut" },
        { "layersIn",         2.5, "easeInOut",    "fade" },
        { "layersOut",        2,   "easeInOut",    "fade" },
        { "workspaces",       3,   "easeInOut",    "fade" },
        { "specialWorkspace", 3,   "easeInOut",    "fade" },
    },
}
M.presets = { "snappy", "smooth", "fancy", "calm" }

local function apply_animations(name)
    for _, a in ipairs(PRESETS[name] or PRESETS.smooth) do
        local spec = { leaf = a[1], enabled = true, speed = a[2], bezier = a[3] }
        if a[4] then spec.style = a[4] end
        hl.animation(spec)
    end
end

-- ========================= Screen filter =========================
-- One screen shader at a time is all Hyprland has. A filter never overwrites a
-- shader that is not from ~/.config/hypr/shaders/, so another tool's shader
-- cannot be clobbered silently.
local SHADER_DIR = os.getenv("HOME") .. "/.config/hypr/shaders/"

local function apply_filter(name)
    local current = hl.get_config("decoration.screen_shader") or ""
    local ours = current == "" or current:sub(1, #SHADER_DIR) == SHADER_DIR
    if not ours then return end
    local want = (name and name ~= "") and (SHADER_DIR .. name .. ".frag") or ""
    if want ~= current then
        hl.config({ decoration = { screen_shader = want } })
    end
end

-- ========================= Theme =========================
-- The desktop theme's Hyprland half. An external tool may write
-- theme=<name> into the state file; this reads that theme's theme.conf on
-- every apply and sets the look from it, so a `hyprctl reload` -- and
-- gamemode OFF, which IS a reload -- comes back to the THEME's look, not to
-- the bare values in lua/settings.lua. settings.lua still holds the
-- cyberpunk values, so with no themes folder at all nothing changes.
--
-- theme.conf is key=value (S.read_kv); every theme inherits cyberpunk for the
-- keys it leaves out, or the theme named by inherit=. The hypr.* keys used here:
--   hypr.rounding  hypr.gaps_in  hypr.gaps_out  hypr.border_size   numbers
--   hypr.active_border  hypr.inactive_border   "rgb(..) rgba(..) 135deg"
--   hypr.accent_stops   active_border stops the accent replaces ("1 2")
--   hypr.blur=yes|no  hypr.blur_size  _passes  _brightness  _contrast
--                     _vibrancy  _vibrancy_darkness  _noise
--   hypr.shadow=yes|no  hypr.shadow_range  _render_power  _color
-- A key that is missing everywhere leaves that option alone.
--
-- Gamemode: animations.enabled == false means gamemode is on. While it is on, the stripped keys -- rounding,
-- gaps, border size, blur, shadow -- are NOT applied, so picking a theme or a
-- filter mid-game cannot undo the strip; colours and rules still are. OFF
-- reloads, and the reload lands here with gamemode off.
local THEMES_DIR = os.getenv("HOME") .. "/.config/themes/"
local BASE_THEME = "cyberpunk"

function M.theme(name)
    local layers, seen = {}, {}
    name = (name and name ~= "") and name or BASE_THEME
    while name ~= "" and not seen[name] do
        local kv = S.read_kv(THEMES_DIR .. name .. "/theme.conf")
        if not kv then break end
        seen[name] = true
        layers[#layers + 1] = kv
        local parent = kv.inherit or ""
        if parent == "" and name ~= BASE_THEME then parent = BASE_THEME end
        name = parent
    end
    if not seen[BASE_THEME] then
        -- The named theme is gone (or its chain is): fall back to the base.
        layers[#layers + 1] = S.read_kv(THEMES_DIR .. BASE_THEME .. "/theme.conf") or {}
    end
    local conf = {}
    for i = #layers, 1, -1 do
        for k, v in pairs(layers[i]) do conf[k] = v end
    end
    return conf
end

-- "rgb(0ff0fc) rgba(00f0ff33) 135deg" -> { colors = {...}, angle = 135 }
local function gradient(spec)
    if not spec or spec == "" then return nil end
    local colors, angle = {}, 0
    for tok in spec:gmatch("%S+") do
        local deg = tok:match("^(%-?[%d%.]+)deg$")
        if deg then angle = tonumber(deg) else colors[#colors + 1] = tok end
    end
    if #colors == 0 then return nil end
    return { colors = colors, angle = angle }
end

local function flag(v)
    if v == nil or v == "" then return nil end
    return v == "yes" or v == "on" or v == "true" or v == "1"
end

local function apply_look(t)
    local gamemode = not hl.get_config("animations.enabled")
    local general = { col = {
        active_border   = gradient(t["hypr.active_border"]),
        inactive_border = gradient(t["hypr.inactive_border"]),
    } }
    local decoration = { shadow = { color = t["hypr.shadow_color"] } }
    if not gamemode then
        general.gaps_in      = tonumber(t["hypr.gaps_in"])
        general.gaps_out     = tonumber(t["hypr.gaps_out"])
        general.border_size  = tonumber(t["hypr.border_size"])
        decoration.rounding  = tonumber(t["hypr.rounding"])
        decoration.blur = {
            enabled           = flag(t["hypr.blur"]),
            size              = tonumber(t["hypr.blur_size"]),
            passes            = tonumber(t["hypr.blur_passes"]),
            brightness        = tonumber(t["hypr.blur_brightness"]),
            contrast          = tonumber(t["hypr.blur_contrast"]),
            vibrancy          = tonumber(t["hypr.blur_vibrancy"]),
            vibrancy_darkness = tonumber(t["hypr.blur_vibrancy_darkness"]),
            noise             = tonumber(t["hypr.blur_noise"]),
        }
        decoration.shadow.enabled      = flag(t["hypr.shadow"])
        decoration.shadow.range        = tonumber(t["hypr.shadow_range"])
        decoration.shadow.render_power = tonumber(t["hypr.shadow_render_power"])
    end
    hl.config({ general = general, decoration = decoration })
end

-- Theme rules: a theme may ship ~/.config/themes/<name>/hypr.lua returning
--     return {
--         window_rules = { { name = "aero-nautilus-glass",
--                            match = { class = "^(org\\.gnome\\.Nautilus)$" },
--                            opacity = "1.0 0.92" }, ... },
--         layer_rules  = { { name = ..., match = { namespace = ... }, ... } },
--     }
-- -- the same tables hl.window_rule / hl.layer_rule take (lua/rules.lua is
-- full of examples). Each rule is created once per Lua state, by name, and
-- then only switched with set_enabled: on while its theme is current, off
-- otherwise, so switching themes back and forth never stacks duplicates.
-- They are declared after every rule in lua/rules.lua, so they win a tie.
-- Only the current theme's own file is read (rules do not inherit). Editing
-- an existing rule's fields needs a `hyprctl reload` to take; a NEW name
-- takes at the next apply. Names must be unique across all themes.
local theme_rules = {}      -- "window:<name>" / "layer:<name>" -> HL rule

local function apply_rules(theme_name)
    local wanted = {}
    local chunk = loadfile(THEMES_DIR .. theme_name .. "/hypr.lua")
    if chunk then
        local ok, spec = pcall(chunk)
        if ok and type(spec) == "table" then
            for _, kind in ipairs({ "window", "layer" }) do
                local make = kind == "window" and hl.window_rule or hl.layer_rule
                for _, r in ipairs(spec[kind .. "_rules"] or {}) do
                    local key = kind .. ":" .. tostring(r.name)
                    wanted[key] = true
                    if not theme_rules[key] then theme_rules[key] = make(r) end
                end
            end
        end
    end
    for key, rule in pairs(theme_rules) do rule:set_enabled(wanted[key] == true) end
end

-- ========================= Accent =========================
-- The focused-window border is the theme's gradient (hypr.active_border,
-- applied just above). With an accent= set in the state file
-- (an external tool may write it), the stops listed in hypr.accent_stops
-- take the accent instead -- in cyberpunk the two leading cyan ones -- so the
-- frame matches the bar and the wallpaper; the rest of the gradient stays.
-- No accent = the theme's border untouched (apply_look has just set it, so
-- turning the accent off needs no reload any more).
local function apply_accent(hex, t)
    if not hex or not hex:match("^#%x%x%x%x%x%x$") then return end
    local g = gradient(t["hypr.active_border"])
    if not g then return end
    local c = "rgb(" .. hex:sub(2) .. ")"
    local any = false
    for i in (t["hypr.accent_stops"] or ""):gmatch("%d+") do
        i = tonumber(i)
        if g.colors[i] then g.colors[i] = c; any = true end
    end
    if any then hl.config({ general = { col = { active_border = g } } }) end
end

-- ========================= Your window look =========================
-- The theme decides how windows look; you get the last word. Any hypr.* key
-- of a theme can be overridden in the display state file (lua/shared.lua) as
-- hyprlook.<the same key without "hypr.">:
--
--     hyprlook.gaps_out=12        wins over the theme's hypr.gaps_out
--     hyprlook.blur=no            ... over hypr.blur
--
-- The overrides are laid over the resolved theme before ANY of it is applied,
-- so they go through exactly the code above: gamemode still strips gaps /
-- borders / rounding / blur / shadow while it is on (and your values come
-- back with everything else when it goes off), the accent is still laid over
-- the border gradient, and switching themes keeps your overrides -- they are
-- yours, not the theme's. Removing the hyprlook.* lines is the whole undo.
-- Write them by hand (or let an external tool write display.conf), then
-- `hyprctl reload`.
--
-- The behaviour keys. No theme sets these today, but a theme may (as
-- hypr.<key>), so they are read from the same merged table. A key nobody
-- sets gets the value below, which is also the plain config's (Hyprland's
-- defaults, and general.layout from lua/settings.lua), so clearing an
-- override really goes back -- unlike the theme keys, which the base theme
-- always supplies.
local LOOK_DEFAULTS = {
    rounding_power   = "2",        -- corner shape: 2 round, higher = squircle
    dim_inactive     = "no",       -- darken the windows you are not using
    dim_strength     = "0.5",      -- by how much (0-1)
    inactive_opacity = "1.0",      -- see-through unfocused windows (0-1)
    layout           = "dwindle",  -- dwindle | master | scrolling
    force_split      = "0",        -- dwindle: new window 0 by the mouse, 1 left/top, 2 right/bottom
    new_status       = "slave",    -- master: new window master | slave (the stack) | inherit
    orientation      = "left",     -- master: where the master sits
    resize_on_border = "no",       -- drag a window's border to resize it
    snap             = "no",       -- floating windows snap to edges and each other
}
local LOOK_CHOICES = {
    layout      = { dwindle = true, master = true, scrolling = true },
    new_status  = { master = true, slave = true, inherit = true },
    orientation = { left = true, right = true, top = true, bottom = true, center = true },
    force_split = { ["0"] = true, ["1"] = true, ["2"] = true },
}

-- theme table + the state's hyprlook.* keys, as one new table (the theme's
-- own table is left as M.theme returned it).
function M.with_overrides(t, st)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    for k, v in pairs(st) do
        local key = k:match("^hyprlook%.([%w_]+)$")
        if key and v ~= "" then out["hypr." .. key] = v end
    end
    return out
end

local function clamp(v, lo, hi)
    v = tonumber(v)
    if not v then return nil end
    return math.max(lo, math.min(hi, v))
end

local function apply_behaviour(t)
    local function v(key)
        local x = t["hypr." .. key]
        if x == nil or x == "" or (LOOK_CHOICES[key] and not LOOK_CHOICES[key][x]) then
            x = LOOK_DEFAULTS[key]     -- a hand-typed "masterr" must not break the load
        end
        return x
    end
    hl.config({
        general = {
            resize_on_border = flag(v("resize_on_border")),
            snap = { enabled = flag(v("snap")) },
        },
        decoration = {
            rounding_power   = clamp(v("rounding_power"), 1, 10),
            dim_inactive     = flag(v("dim_inactive")),
            dim_strength     = clamp(v("dim_strength"), 0, 1),
            inactive_opacity = clamp(v("inactive_opacity"), 0.1, 1),
        },
        dwindle = { force_split = tonumber(v("force_split")) },
        master  = { new_status = v("new_status"), orientation = v("orientation") },
    })
    -- Only when it changes: a layout switch re-tiles every workspace, and
    -- apply() runs for every filter / animation / accent change too.
    local layout = v("layout")
    if hl.get_config("general.layout") ~= layout then
        hl.config({ general = { layout = layout } })
    end
end

function M.apply()
    local st = S.state()
    local name = (st.theme and st.theme ~= "") and st.theme or BASE_THEME
    local t = M.with_overrides(M.theme(name), st)
    apply_look(t)
    apply_behaviour(t)
    apply_rules(name)
    apply_animations(st.anim or t.anim)
    apply_filter(st.filter)
    apply_accent(st.accent, t)
end

M.apply()

return M
