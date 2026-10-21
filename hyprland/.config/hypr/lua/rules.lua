-- ~/.config/hypr/lua/rules.lua
-- Loaded from ~/.config/hypr/hyprland.lua (the index). Window rules, layer
-- rules and workspace rules, in that order.
--
-- ORDER MATTERS within this file: window rules are evaluated in the order
-- they are declared, so moving a block around can change which value wins
-- when two rules set the same property on one window.

---@module 'hl'

-- ========================= Window rules: games =========================
-- Steam games open truly fullscreen: (2,2), Hyprland fills the monitor AND
-- the game is told it is fullscreen, so it takes its fullscreen render path.
-- The state has to be set at map time, by a rule rather than a keypress: a
-- game decides which render path to use when it first sees the state.
--
-- The value is a string, "internal client" -- NOT a table. Passing
-- { internal = 0, client = 2 } is rejected with "string type requires a string".
--
-- float = false: a Steam game arrives floating; tiled, ALT+F leaves an
-- ordinary tiled window under the bar instead of a float covering it.
hl.window_rule({
    name  = "fs-render-windowed-steam",
    match = { class = "^(steam_app_.*)$" },
    float = false,
    fullscreen_state = "2 2",
})

-- Games are always opaque. Some engines hand the compositor a surface with an
-- alpha channel they never meant to be used, and the desktop shows through
-- dark scenes. force_rgbx ignores the alpha channel; no_blur skips a blur pass
-- that would only take GPU time from the game. Another game showing the
-- desktop through it: add its class here (`hyprctl clients` prints it).
hl.window_rule({
    name       = "games-opaque",
    match      = { class = "^(steam_app_.*)$" },
    force_rgbx = true,
    no_blur    = true,
})

-- Browsers and mpv are always opaque too: pages and video are content, the
-- wallpaper never belongs behind them. Chrome's Flatpak still calls itself
-- google-chrome.
hl.window_rule({
    name       = "browsers-mpv-opaque",
    match      = { class = "^(org\\.mozilla\\.firefox|firefox|google-chrome|chromium-browser|[Cc]hromium|org\\.gnome\\.Epiphany|mpv)$" },
    force_rgbx = true,
    no_blur    = true,
})

-- ========================= Window rules: behaviour =========================
-- A fullscreen window keeps hypridle from dimming, locking or switching the
-- screens off. A controller-driven game sends no keyboard or mouse input at
-- all, so Steam games keep the screen awake even when not fullscreen.
hl.window_rule({
    name         = "idle-inhibit-fullscreen",
    match        = { class = ".*" },
    idle_inhibit = "fullscreen",
})
hl.window_rule({
    name         = "idle-inhibit-steam-games",
    match        = { class = "^(steam_app_.*)$" },
    idle_inhibit = "always",
})

-- Apps asking to be maximized fight the tiler: the window flashes to full size
-- and then snaps back into its tile. Ignore the request; ALT+F is the way to
-- make something big. (From Hyprland's own bundled example config.)
hl.window_rule({
    name           = "suppress-maximize-events",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

-- XWayland menus and drag-and-drop helpers are nameless floating surfaces that
-- steal focus and break drags out of Steam and other X11 apps. No focus for
-- them. (Also from the bundled example.)
hl.window_rule({
    name     = "fix-xwayland-drags",
    match    = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

-- ========================= Window rules: floating =========================
-- File dialogs float and centre instead of splitting the window you were
-- working in. Matched on title because the dialog's class is its parent
-- app's, and on the portal's own class for apps that go through
-- xdg-desktop-portal.
hl.window_rule({
    name   = "float-file-dialogs",
    match  = { title = "^(Open File|Open Files|Open Folder|Save File|Save As|Save Image|File Upload|Choose Files?|Select a File|Enter name of file to save to).*$" },
    float  = true,
    center = true,
    size   = "1100 700",
})
hl.window_rule({
    name   = "float-portal-file-chooser",
    match  = { class = "^(xdg-desktop-portal-gtk)$" },
    float  = true,
    center = true,
    size   = "1100 700",
})

-- Small utility windows that are useless at tile size: the volume mixer, the
-- network editor, and the polkit password prompt (hyprpolkitagent).
hl.window_rule({
    name   = "float-utilities",
    match  = { class = "^(org\\.pulseaudio\\.pavucontrol|pavucontrol|nm-connection-editor|hyprpolkitagent)$" },
    float  = true,
    center = true,
    size   = "900 600",
})

-- Steam's side windows (friends list, settings, the sign-in splash) are
-- separate toplevels with the same class as the main client: matched by title.
hl.window_rule({
    name  = "float-steam-side-windows",
    match = { class = "^(steam)$", title = "^(Friends List|Steam Settings|Sign in to Steam|Steam - News.*|Special Offers)$" },
    float = true,
})

-- Picture-in-picture: float, pinned (stays on screen across workspace
-- switches), 16:9 in the bottom-right corner of the monitor it opens on.
-- move is the window size plus a 24px margin (640+24, 360+24), spelled out
-- because move expressions do not resolve window_w / window_h. Change size,
-- change move with it.
hl.window_rule({
    name              = "pip",
    match             = { title = "^(Picture-in-Picture|Picture in picture)$" },
    float             = true,
    pin               = true,
    keep_aspect_ratio = true,
    size              = "640 360",
    move              = "monitor_w-664 monitor_h-384",
})

-- ========================= Layer rules =========================
-- Glass effect for waybar: frost whatever sits behind the bar's translucent
-- pills. The namespace is the bar's "name" from ~/.config/waybar/config
-- ("waybar-main"), NOT the literal string "waybar". ignore_alpha leaves the
-- fully transparent gaps between pills unblurred.
hl.layer_rule({
    name         = "waybar-glass",
    match        = { namespace = "^(waybar-.*)$" },
    blur         = true,
    ignore_alpha = 0.2,
})

-- The launcher: frosted so the page underneath does not read through the
-- list, pops in, and dims everything behind it.
hl.layer_rule({
    name         = "wofi-glass",
    match        = { namespace = "^(wofi)$" },
    blur         = true,
    ignore_alpha = 0.2,
    animation    = "popin 80%",
    dim_around   = true,
})

-- mako's notification stack. The namespace is "notifications", NOT "mako"
-- (`hyprctl layers` prints the real namespace of every live surface).
hl.layer_rule({
    name         = "mako-glass",
    match        = { namespace = "^(notifications)$" },
    blur         = true,
    ignore_alpha = 0.05,
})

-- ========================= Workspace rules =========================
-- Workspaces 1-6 always exist, even empty: the bar reads workspaces over
-- ext-workspace-v1, which can only report workspaces that really exist, so
-- the always-there pills have to be real persistent workspaces.
-- They live on the primary screen from lua/monitors.lua; when it names none
-- (the default) Hyprland creates them on the screen that is focused at load.
local mon_ok, MON = pcall(require, "lua.monitors")
local P = (mon_ok and type(MON) == "table" and MON.primary and MON.primary()) or ""
for i = 1, 6 do
    local rule = { workspace = tostring(i), persistent = true }
    if P ~= "" then rule.monitor = P end
    if i == 1 then rule.default = true end
    hl.workspace_rule(rule)
end
