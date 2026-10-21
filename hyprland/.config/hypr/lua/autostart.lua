-- ~/.config/hypr/lua/autostart.lua
-- Loaded from ~/.config/hypr/hyprland.lua (the index), last. The
-- hyprland.start event fires once per login, NOT on `hyprctl reload`, so
-- nothing in here re-runs when the config is reloaded.

---@module 'hl'

-- ========================= Wallpaper =========================
-- hyprpaper.conf needs absolute paths (it is hyprlang, not a shell: a leading
-- ~ is taken literally), so the shipped file says $HOME and this writes a copy
-- with it expanded to $XDG_RUNTIME_DIR, which hyprpaper is then started with.
-- Edit ~/.config/hypr/hyprpaper.conf as usual; $HOME there keeps working.
local function hyprpaper_cmd()
    local home = os.getenv("HOME") or ""
    local src = io.open(home .. "/.config/hypr/hyprpaper.conf", "r")
    if not src then return "hyprpaper" end
    local text = src:read("*a")
    src:close()
    local dir = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
    local out_path = dir .. "/carino-hyprpaper.conf"
    local out = io.open(out_path, "w")
    if not out then return "hyprpaper" end
    out:write((text:gsub("%$HOME", function() return home end)))
    out:close()
    return "hyprpaper -c '" .. out_path .. "'"
end

-- ========================= Autostart =========================
-- The desktop's daemons, started straight from here so the session works the
-- same with or without uwsm. `pidof x || x` keeps a daemon that is already
-- running (e.g. one a systemd user unit started) from being started twice.
--
--   waybar           the bar (~/.config/waybar/config); ALT+G restarts it
--   hypridle         lock after 10 min, screens off 30 s after a lock
--   mako             notifications (owns org.freedesktop.Notifications)
--   cliphist         records the clipboard for SUPER+V, text and images
--   hyprpolkitagent  password prompts for GUI apps needing admin rights
local daemons = {
    "mkdir -p \"$HOME/Pictures/Screenshots\"",
    "pidof waybar || waybar",
    "pidof hypridle || hypridle",
    "pidof mako || mako",
    "wl-paste --type text --watch cliphist store",
    "wl-paste --type image --watch cliphist store",
    "systemctl --user start hyprpolkitagent",
}

hl.on("hyprland.start", function()
    hl.exec_cmd("pidof hyprpaper || " .. hyprpaper_cmd())
    for _, cmd in ipairs(daemons) do hl.exec_cmd(cmd) end
end)
