#!/bin/sh
# Carino Hyprland power menu: a wofi list of session actions.
# Used by SUPER+Escape (lua/binds.lua) and the power pill in the bar.
# Pressing it again while the menu is open closes it.
pkill -x wofi && exit 0

choice=$(printf '%s\n' "Lock" "Log out" "Suspend" "Reboot" "Power off" |
    wofi --dmenu --insensitive --prompt power --width 260 --lines 6)

case "$choice" in
    "Lock")      exec sh -c 'pidof hyprlock || hyprlock' ;;
    "Log out")   exec "$(dirname "$0")/session-exit.sh" ;;
    "Suspend")   exec systemctl suspend ;;
    "Reboot")    exec systemctl reboot ;;
    "Power off") exec systemctl poweroff ;;
esac
