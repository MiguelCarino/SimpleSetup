# Carino Hyprland

A complete, small Hyprland desktop: the neon "cyberpunk" look of the Carino
desktop, its ALT-based keymap, a waybar bar, a lock screen, idle handling,
notifications, a launcher, clipboard history and screenshots. `setup.sh`
installs it when you answer yes to "Install the Carino Hyprland desktop
configuration?", pick Carino Hyprland in the desktop menu, or run
`bash setup.sh hyprland` (unattended: the `hyprland` or
`desktop=carino-hyprland` plan token in `CARINO_SETUP_PLAN`).

This folder mirrors your home folder: `.config/hypr/...` goes to
`~/.config/hypr/...`, and so on.

## Requirements

- **Hyprland 0.55 or newer, with Lua config support.** The config is
  `~/.config/hypr/hyprland.lua`, not `hyprland.conf`. Older Hyprland ignores
  it and starts with its default config. `Hyprland --version` shows yours.
- The packages in [`packages.txt`](packages.txt) (Fedora names; `setup.sh`
  installs the matching names on other distributions).
- A graphical login screen (GDM, SDDM...) where you can pick "Hyprland".
  `setup.sh` does not install one for Carino Hyprland; without one, start it
  by typing `Hyprland` on a text console after logging in.

After installing, log out and choose **Hyprland** at the login screen.

## What is included

| Path | What it is |
| --- | --- |
| `.config/hypr/hyprland.lua` | The index: loads the modules in `lua/` in order |
| `.config/hypr/lua/` | `monitors` `rules` `env` `settings` `input` `display` `binds` `autostart` `shared` |
| `.config/hypr/shaders/` | Optional screen filters (grayscale, colour-blind, CRT, reading...) |
| `.config/hypr/hypridle.conf` | Lock after 10 min idle; screens off 30 s after a lock |
| `.config/hypr/hyprlock.conf` | The neon lock screen (clock, date, layout, password) |
| `.config/hypr/hyprpaper.conf` | Wallpaper: `~/Pictures/Wallpapers/carino.png` on every screen |
| `.config/hypr/scripts/` | `window-switcher.py`, `power-menu.sh`, `session-exit.sh` |
| `.config/waybar/` | The bar: built-in modules only, plus its stylesheet |
| `.config/wofi/`, `.config/mako/`, `.config/kitty/`, `.config/cliphist/` | Launcher, notifications, terminal, clipboard history |
| `.config/themes/cyberpunk/theme.conf` | The palette and window look `lua/display.lua` applies |
| `.local/share/fonts/carino/` | Orbitron, Rajdhani SemiBold, Share Tech Mono (SIL OFL 1.1, licence files beside them) |
| `Pictures/Wallpapers/carino.png` | The Carino skyline wallpaper (procedurally rendered for this desktop) |

Screens: every connected screen runs at its preferred mode, side by side.
To place them yourself, edit `~/.config/hypr/lua/monitors.lua` (it has an
example). `hyprctl monitors` prints their names.

Keyboard: the layout is `us`. To change it, create
`~/.local/state/hypr/input.conf` with a line such as `layouts=us,de` and run
`hyprctl reload`. With two layouts, SUPER+Space switches between them.
`lua/input.lua` lists every key you can set there.

## Key bindings

The main modifier is **ALT** (change `mainMod` in `lua/shared.lua` to use
SUPER instead). `hyprctl binds` lists every bind with its description.

| Keys | Action |
| --- | --- |
| ALT+Q | Terminal (kitty) |
| ALT+E | App launcher (wofi); again to close |
| ALT+W | File manager (your home folder) |
| SUPER+W | Window switcher: every window on every workspace |
| ALT+C | Close window (only if it is on the screen you are looking at) |
| ALT+F | Fullscreen |
| ALT+V | Toggle floating |
| ALT+P | Pseudo-tile |
| ALT+R | Toggle split direction |
| ALT+SHIFT+P | Pin a floating window to every workspace |
| ALT+arrows or ALT+H/J/K/L | Focus window in that direction |
| ALT+SHIFT+arrows / H/J/K/L | Swap window in that direction |
| ALT+CTRL+arrows / H/J/K/L | Resize by one step |
| SUPER+R | Resize mode: arrows resize, Esc or Enter leaves |
| ALT+left drag / ALT+right drag | Move / resize a window with the mouse |
| ALT+T | Toggle group (tabbed windows) |
| ALT+] / ALT+[ | Next / previous tab in a group |
| ALT+1..9 | Go to workspace (again: back to the previous one) |
| ALT+SHIFT+1..9 | Send window to workspace |
| ALT+mouse wheel | Next / previous workspace |
| SUPER+Tab | Previous workspace |
| ALT+Tab / ALT+SHIFT+Tab | Next / previous window on this workspace |
| ALT+U | Window asking for attention, or the last one |
| SUPER+arrows | Focus monitor in that direction |
| SUPER+SHIFT+arrows | Send window to monitor in that direction |
| ALT+\` | Show / hide the scratchpad |
| ALT+SHIFT+\` | Send window to the scratchpad |
| SUPER+Return | Drop-down terminal |
| SUPER+A | Volume mixer (pavucontrol) |
| ALT+S | Screenshot of the current monitor to `~/Pictures/Screenshots` |
| ALT+SHIFT+S | Screenshot of a region to `~/Pictures/Screenshots` |
| SUPER+S | Screenshot of a region to the clipboard |
| SUPER+V | Clipboard history |
| ALT+SHIFT+D | Do not disturb on / off |
| ALT+SHIFT+X | Dismiss all notifications |
| ALT+SHIFT+R | Bring back the last notification |
| ALT+B | Show / hide the bar |
| ALT+G | Restart the bar |
| SUPER+ALT+L | Lock the screen |
| SUPER+Escape | Power menu: lock, log out, suspend, reboot, power off |
| SUPER+SHIFT+M | Log out of Hyprland |
| SUPER+Space | Switch keyboard layout (when you have two) |
| Volume, mute, mic, brightness, media keys | Work as labelled, also on the lock screen |

## Deliberately left out

The full Carino desktop is much larger. These parts are not in this bundle:

- **Personal:** identity, shell profile, input methods, bookmarks, default
  apps, personal automations and status widgets.
- **Machine-specific:** the per-host monitor layout (names, modes, HDR,
  rotation), GPU-specific environment variables and game profiles, mpv tuned
  for one graphics card and refresh rate, per-monitor wallpaper folders.
  NVIDIA users: `lua/env.lua` has the usual variables as commented examples.
- **Heavy optional builds:** the Hyprland overview and cube plugins (they are
  compiled from source and must be rebuilt after every Hyprland update), the
  theme switcher and its other themes, the custom Python bar panels, the
  settings app, the GTK launcher, local AI and voice tools, and the generators
  for icons, sounds and wallpapers.
- **Third-party artwork:** wallpapers by other artists and fonts whose licence
  could not be confirmed.

## How to undo

`setup.sh` moves your existing `~/.config/hypr`, `waybar`, `wofi`, `mako`,
`kitty`, `cliphist` and `themes` folders to `~/.config/carino-backup-<timestamp>/`
before copying this bundle. To go back:

```sh
cd ~/.config
rm -rf hypr waybar wofi mako kitty cliphist themes
cp -a carino-backup-<timestamp>/. ~/.config/
```

The fonts are in `~/.local/share/fonts/carino/` (delete the folder, then run
`fc-cache -f`) and the wallpaper is `~/Pictures/Wallpapers/carino.png`.
Installed packages stay installed; remove them with your package manager if
you no longer want them.
