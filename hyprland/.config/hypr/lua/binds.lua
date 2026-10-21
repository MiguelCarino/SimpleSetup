-- ~/.config/hypr/lua/binds.lua
-- Loaded from ~/.config/hypr/hyprland.lua (the index). Every key bind and the
-- resize submap. mainMod is ALT (lua/shared.lua); README.md has the full table.
--
-- Every command here is either part of this bundle (~/.config/hypr/scripts/)
-- or a package in packages.txt. Every hl.bind carries a description,
-- "Section: what it does"; `hyprctl binds` lists them.

---@module 'hl'

local S       = require("lua.shared")
local mainMod = S.mainMod
local scrDir  = S.scrDir
local scripts = "~/.config/hypr/scripts/"

-- ========================= Apps =========================
hl.bind(mainMod .. "+Q", hl.dsp.exec_cmd("kitty"), { description = "Apps: Terminal" })
hl.bind(mainMod .. "+W", hl.dsp.exec_cmd("xdg-open \"$HOME\""), { description = "Apps: File manager" })
hl.bind(mainMod .. "+E", hl.dsp.exec_cmd("pkill -x wofi || wofi --show drun"), { description = "Apps: Launcher" })
hl.bind("SUPER+W", hl.dsp.exec_cmd(scripts .. "window-switcher.py"), { description = "Navigation: Window switcher" })

-- ========================= Windows =========================
-- Close -- but only a window you can actually see. A bare close acts on the
-- *active* window, which can be left behind on another screen or on the
-- workspace you just left (an empty workspace gives Hyprland nothing to
-- focus). The guard: the window must sit on the workspace the focused
-- monitor is showing, or on its open scratchpad.
hl.bind(mainMod .. "+C", function()
    local win = hl.get_active_window()
    local mon = hl.get_active_monitor()
    if not win or not mon then return end
    local ws, shown, special = win.workspace, mon.active_workspace, mon.active_special_workspace
    local here = ws ~= nil and ((shown ~= nil and ws.id == shown.id)
                             or (special ~= nil and ws.id == special.id))
    if not here then
        hl.notification.create({ text = "ALT+C ignored: focus is on workspace " ..
                                 (ws and ws.name or "?") .. ", not here",
                                 timeout = 1500, color = "rgb(fffb00)" })
        return
    end
    hl.dispatch(hl.dsp.window.close())
end, { description = "Windows: Close (only on the screen you see)" })

hl.bind(mainMod .. "+F", hl.dsp.window.fullscreen(), { description = "Windows: Fullscreen" })
hl.bind(mainMod .. "+V", hl.dsp.window.float(), { description = "Windows: Toggle floating" })
hl.bind(mainMod .. "+P", hl.dsp.window.pseudo(), { description = "Windows: Pseudo-tile" })
hl.bind(mainMod .. "+R", hl.dsp.layout("togglesplit"), { description = "Windows: Toggle split direction" })
hl.bind(mainMod .. "+SHIFT+P", hl.dsp.window.pin(), { description = "Windows: Pin floating window" })

-- Focus / swap / resize per direction, on the arrows and on h j k l.
-- relative = true is required: without it x/y are an absolute size.
local resize_delta = {
    left  = { x = -60, y = 0,   relative = true },
    right = { x = 60,  y = 0,   relative = true },
    up    = { x = 0,   y = -60, relative = true },
    down  = { x = 0,   y = 60,  relative = true },
}
local vim = { left = "h", down = "j", up = "k", right = "l" }
for _, d in ipairs({ "left", "right", "up", "down" }) do
    for _, key in ipairs({ d, vim[d] }) do
        hl.bind(mainMod .. "+" .. key,       hl.dsp.focus({ direction = d }), { description = "Windows: Focus" })
        hl.bind(mainMod .. "+SHIFT+" .. key, hl.dsp.window.swap({ direction = d }), { description = "Windows: Swap" })
        hl.bind(mainMod .. "+CTRL+" .. key,  hl.dsp.window.resize(resize_delta[d]), { description = "Windows: Resize step" })
    end
end

-- Resize mode: while it is on, the bare arrows resize (hold to repeat) and
-- the bar's submap pill shows it. Escape or Return leaves.
hl.define_submap("resize", function()
    for _, d in ipairs({ "left", "right", "up", "down" }) do
        hl.bind(d, hl.dsp.window.resize(resize_delta[d]), { repeating = true })
    end
    hl.bind("escape", hl.dsp.submap("reset"))
    hl.bind("return", hl.dsp.submap("reset"))
end)
hl.bind("SUPER+R", hl.dsp.submap("resize"), { description = "Windows: Resize mode (Esc to leave)" })

-- Mouse: hold ALT and drag with the left button to move, right to resize.
-- No { mouse = true } and no release/drag flags: hl.dsp.window.drag() is
-- already the press-and-hold dispatcher, and extra flags make it start one
-- click late.
hl.bind(mainMod .. "+mouse:272", hl.dsp.window.drag(), { description = "Windows: Move with mouse" })
hl.bind(mainMod .. "+mouse:273", hl.dsp.window.resize(), { description = "Windows: Resize with mouse" })

-- Groups: stack windows into one tabbed frame.
hl.bind(mainMod .. "+T",            hl.dsp.group.toggle(), { description = "Groups: Toggle group" })
hl.bind(mainMod .. "+bracketright", hl.dsp.group.next(), { description = "Groups: Next tab" })
hl.bind(mainMod .. "+bracketleft",  hl.dsp.group.prev(), { description = "Groups: Previous tab" })

-- ========================= Workspaces =========================
-- Pressing ALT+n for the workspace you are on goes back to the one you came from.
hl.config({ binds = { workspace_back_and_forth = true } })

for i = 1, 9 do
    local ws = tostring(i)
    hl.bind(mainMod .. "+" .. ws,       hl.dsp.focus({ workspace = i }), { description = "Workspaces: Go to" })
    hl.bind(mainMod .. "+SHIFT+" .. ws, hl.dsp.window.move({ workspace = ws, follow = false }), { description = "Workspaces: Send window to" })
end
hl.bind(mainMod .. "+mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Workspaces: Next" })
hl.bind(mainMod .. "+mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "Workspaces: Previous" })
hl.bind("SUPER+Tab", hl.dsp.focus({ workspace = "previous" }), { description = "Navigation: Previous workspace" })

-- ALT+Tab / ALT+SHIFT+Tab: cycle windows on the current workspace. bring_to_top
-- is for floating windows, which would otherwise stay hidden underneath.
-- { next = false } is backwards; unknown keys such as { prev = true } are
-- silently ignored and cycle forward.
local function cycle(forward)
    return function()
        hl.dispatch(hl.dsp.window.cycle_next({ next = forward }))
        hl.dispatch(hl.dsp.window.bring_to_top())
    end
end
hl.bind(mainMod .. "+Tab",       cycle(true), { description = "Navigation: Next window" })
hl.bind(mainMod .. "+SHIFT+Tab", cycle(false), { description = "Navigation: Previous window" })
hl.bind(mainMod .. "+U", hl.dsp.focus({ urgent_or_last = true }), { description = "Navigation: Urgent or last window" })

-- ========================= Monitors =========================
local monitor_dir = { left = "l", right = "r", up = "u", down = "d" }
for _, d in ipairs({ "left", "right", "up", "down" }) do
    hl.bind("SUPER+" .. d,       hl.dsp.focus({ monitor = monitor_dir[d] }), { description = "Monitors: Focus" })
    hl.bind("SUPER+SHIFT+" .. d, hl.dsp.window.move({ monitor = monitor_dir[d], follow = false }), { description = "Monitors: Send window to" })
end

-- ========================= Scratchpads =========================
-- toggle_special takes the bare name as a STRING; the table form
-- { workspace = "magic" } parses but toggles the wrong workspace.
hl.bind(mainMod .. "+grave",       hl.dsp.workspace.toggle_special("magic"), { description = "Scratchpads: Toggle scratchpad" })
hl.bind(mainMod .. "+SHIFT+grave", hl.dsp.window.move({ workspace = "special:magic", follow = false }), { description = "Scratchpads: Send window to scratchpad" })

-- Per-app scratchpads: the key shows / hides the app, and starts it on its
-- own special workspace if it is not running yet. Matched on class, so the
-- terminal is kitty with its own --class, never your ordinary kitty windows.
local function scratchpad(name, class, cmd)
    return function()
        for _, w in ipairs(hl.get_windows()) do
            if w.class == class then
                hl.dispatch(hl.dsp.workspace.toggle_special(name))
                return
            end
        end
        hl.exec_cmd(cmd, { workspace = "special:" .. name })
    end
end
hl.bind("SUPER+Return", scratchpad("term", "scratch-term", "kitty --class scratch-term"),
    { description = "Scratchpads: Drop-down terminal" })
hl.bind("SUPER+A", scratchpad("mixer", "org.pulseaudio.pavucontrol", "pavucontrol"),
    { description = "Scratchpads: Volume mixer" })

-- The drop-down terminal hangs from the top edge: DROP_W of the monitor's
-- width, DROP_H of its height (a rotated monitor swaps the two).
local DROP_W, DROP_H, DROP_TOP = 0.96, 0.45, 0.04
hl.on("window.open", function(w)
    if w.class ~= "scratch-term" then return end
    local target = "address:" .. w.address
    local mon = w.monitor or hl.get_active_monitor()
    if not mon then return end
    local mw, mh = mon.width / mon.scale, mon.height / mon.scale
    if mon.transform % 2 == 1 then mw, mh = mh, mw end
    local ww = math.floor(mw * DROP_W)
    hl.dispatch(hl.dsp.window.float({ action = "enable", window = target }))
    hl.dispatch(hl.dsp.window.resize({ x = ww, y = math.floor(mh * DROP_H), window = target }))
    hl.dispatch(hl.dsp.window.move({ x = math.floor(mon.x + (mw - ww) / 2),
                                     y = math.floor(mon.y + mh * DROP_TOP), window = target }))
end)

-- ========================= Media keys =========================
-- wpctl comes with wireplumber. -l 1.0 caps the raise at 100% (without it,
-- wpctl walks into software gain); raising also unmutes. locked = true keeps
-- the keys working on the lock screen.
hl.bind("XF86AudioRaiseVolume",
    hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ && wpctl set-mute @DEFAULT_AUDIO_SINK@ 0"),
    { locked = true, repeating = true, description = "Media: Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
    { locked = true, repeating = true, description = "Media: Volume down" })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    { locked = true, description = "Media: Mute" })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
    { locked = true, description = "Media: Mic mute" })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set 5%+"),
    { locked = true, repeating = true, description = "Media: Brightness up" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"),
    { locked = true, repeating = true, description = "Media: Brightness down" })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Media: Play / pause" })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"),       { locked = true, description = "Media: Next track" })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"),   { locked = true, description = "Media: Previous track" })
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl stop"),       { locked = true, description = "Media: Stop" })

-- ========================= Screenshots =========================
-- Files go to ~/Pictures/Screenshots (scrDir in lua/shared.lua), named by date.
local shot = "\"" .. scrDir .. "/$(date +%F_%H-%M-%S).png\""
hl.bind(mainMod .. "+S",
    hl.dsp.exec_cmd("mkdir -p \"" .. scrDir .. "\" && grim -o \"$(hyprctl activeworkspace -j | jq -r .monitor)\" " .. shot),
    { description = "Screenshots: Monitor" })
hl.bind(mainMod .. "+SHIFT+S",
    hl.dsp.exec_cmd("mkdir -p \"" .. scrDir .. "\" && grim -g \"$(slurp)\" " .. shot),
    { description = "Screenshots: Region" })
hl.bind("SUPER+S", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy --type image/png"),
    { description = "Screenshots: Region to clipboard (no file)" })

-- ========================= Clipboard =========================
hl.bind("SUPER+V", hl.dsp.exec_cmd("cliphist list | wofi --dmenu --prompt clipboard | cliphist decode | wl-copy"),
    { description = "Clipboard: History" })

-- ========================= Notifications =========================
hl.bind(mainMod .. "+SHIFT+D", hl.dsp.exec_cmd("makoctl mode -t do-not-disturb"), { description = "Notifications: Do not disturb on / off" })
hl.bind(mainMod .. "+SHIFT+X", hl.dsp.exec_cmd("makoctl dismiss --all"), { description = "Notifications: Dismiss all" })
hl.bind(mainMod .. "+SHIFT+R", hl.dsp.exec_cmd("makoctl restore"), { description = "Notifications: Restore last" })

-- ========================= Bar =========================
hl.bind(mainMod .. "+B", hl.dsp.exec_cmd("pkill -USR1 -x waybar"), { description = "Bar: Show / hide" })
hl.bind(mainMod .. "+G", hl.dsp.exec_cmd("pkill -x waybar; sleep 0.3; waybar"), { description = "Bar: Restart" })

-- ========================= Session =========================
-- SUPER+ALT+L rather than SUPER+L so locking is never an accidental press.
hl.bind("SUPER+ALT+L", hl.dsp.exec_cmd("pidof hyprlock || hyprlock"), { description = "Session: Lock" })
hl.bind("SUPER+Escape", hl.dsp.exec_cmd(scripts .. "power-menu.sh"), { description = "Session: Power menu" })
-- Deliberately not a bare ALT+M: it ends the session with no confirmation.
hl.bind("SUPER+SHIFT+M", hl.dsp.exec_cmd(scripts .. "session-exit.sh"), { description = "Session: Exit Hyprland" })
