-- ~/.config/hypr/lua/settings.lua
-- Loaded from ~/.config/hypr/hyprland.lua (the index). The main hl.config
-- block; the animation curves and presets are in lua/display.lua. The one
-- other hl.config call, binds.workspace_back_and_forth, lives with the
-- navigation binds it changes (lua/binds.lua).
--
-- The LOOK below -- border colours and size, gaps, rounding, blur, shadow --
-- is the cyberpunk theme's, and only the fallback: lua/display.lua, loaded
-- right after this file, re-applies the current desktop theme's values
-- (~/.config/themes/<name>/theme.conf, hypr.* keys) at every load, so a
-- reload returns to the THEME's look. To change the neon
-- look, change ~/.config/themes/cyberpunk/theme.conf -- and these values with
-- it, so the two never disagree about what "no theme" looks like.

---@module 'hl'

-- ========================= Config =========================
hl.config({
    -- No input block here: keyboard layouts, the layout switch, key repeat,
    -- mouse / touchpad and focus-follows-mouse are applied by lua/input.lua,
    -- required at the end of this file.
    -- SDR apps on an HDR monitor: decode them with a pure 2.2 gamma, as GNOME
    -- does, not the piecewise sRGB curve ("default"), whose linear toe lifts
    -- near-black and leaves the desktop looking washed out in HDR.
    render = {
        cm_sdr_eotf = "gamma22",
    },
    general = {
        gaps_in     = 3,
        gaps_out    = 4,
        border_size = 4,
        layout      = "dwindle",
        col = {
            active_border   = { colors = { "rgb(0ff0fc)", "rgb(00fff7)", "rgb(39ff14)", "rgb(fffb00)", "rgb(ff0055)", "rgb(9f00ff)" }, angle = 135 },
            -- Unfocused windows: a dim cyan-to-magenta hairline instead of grey,
            -- so they still belong to the neon theme but never compete with the
            -- focused frame. (Old grey: rgba(c9c9c9ee) -> rgba(6d6c6cee).)
            inactive_border = { colors = { "rgba(00f0ff33)", "rgba(ff2a6d26)" }, angle = 135 },
        },
    },
    decoration = {
        -- 4 rather than 10: the neon theme (waybar, wofi, mako, hyprlock) is
        -- angular -- chamfers and near-square corners -- and soft 10px windows
        -- looked like they came from a different desktop.
        rounding = 4,
        -- Neon glow around the FOCUSED window only (color_inactive is fully
        -- transparent). No offset, so it reads as light bleeding off the frame
        -- rather than as a drop shadow. Off: the bar and panels dropped their
        -- glow too (2026-10-13); the values are kept for turning it back on.
        shadow = {
            enabled        = false,
            range          = 14,
            render_power   = 3,
            offset         = { 0, 0 },
            color          = "rgba(00f0ff55)",
            color_inactive = "rgba(00000000)",
        },
        -- Blur is the other half of waybar's glass: style.css
        -- only supply the tint and the lit edges, everything behind them is
        -- frosted here.
        --
        -- size/passes: a wide, soft frost comes far more cheaply from more
        -- passes than from a bigger kernel, because each pass runs on a
        -- half-resolution buffer. 6/4 covers roughly the radius the old 16/2
        -- did, for less GPU time and with a smoother falloff.
        --
        -- brightness below 1.0 is what lets the bar survive a white window
        -- sliding under it: the backdrop is knocked down before the dark pill
        -- tint goes over it, so white text never sits on a near-white surface.
        --
        -- vibrancy puts saturation back: averaging pixels together is
        -- inherently desaturating, and without this the frost goes grey and
        -- dead over a colourful wallpaper.
        --
        -- noise hides the banding a heavy blur leaves on smooth gradients. Keep
        -- it low -- at the old 0.03 the grain read as texture on the pills.
        blur = {
            enabled           = true,
            size              = 6,
            passes            = 4,
            new_optimizations = true,
            ignore_opacity    = true,
            brightness        = 0.80,
            contrast          = 1.10,
            vibrancy          = 0.30,
            vibrancy_darkness = 0.30,
            noise             = 0.012,
            popups            = true,
        },
    },
    cursor = {
        -- Only matters with VRR on: the lowest rate Hyprland will drive a
        -- panel at to keep the cursor moving on a static screen. The default,
        -- 24, is below the adaptive-sync floor of most panels (typically
        -- 40-50 Hz); asking for less drops the panel out of its VRR window and
        -- the brightness shift as it enters and leaves it reads as flicker.
        min_refresh_rate = 50,
    },
    -- Curves and per-animation speeds are in the Animations section below.
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    misc = {
        animate_manual_resizes       = true,
        animate_mouse_windowdragging = true,
        -- A GUI app started from one of these terminals takes the terminal's
        -- place until it exits. Without a regex, enable_swallow does nothing:
        -- an empty swallow_regex matches no terminal, so no window was ever
        -- swallowed. Classes as `hyprctl clients` reports them.
        enable_swallow               = true,
        swallow_regex                = "^(kitty)$",
        disable_hyprland_logo        = true,
        -- Both default to false, which is only safe while nothing ever turns
        -- the displays off. hypridle does (30 s after a lock), so these make
        -- any input wake them, independently of hypridle's on-resume hook.
        mouse_move_enables_dpms      = true,
        key_press_enables_dpms       = true,
    },
})

-- ========================= Animations =========================
-- The curves and every hl.animation live in lua/display.lua, as presets
-- (snappy / smooth / fancy / calm): set anim=<name> in
-- ~/.local/state/hypr/display.conf and `hyprctl reload`.

-- ========================= Input =========================
-- Keyboard, mouse and touchpad, from ~/.local/state/hypr/input.conf (see the
-- module's header). After the hl.config block above, so nothing here can
-- overwrite what the user chose.
require("lua.input")
