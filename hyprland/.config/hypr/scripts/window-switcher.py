#!/usr/bin/env python3
"""Pick any window on any workspace from a wofi list and focus it.

Bound to SUPER+W in lua/binds.lua. Lists windows most-recently-focused first, so
the top entry is the one you were just in -- Enter on it is "go back".

Focusing goes through the Lua dispatcher (hl.dsp.focus with an address
selector) because this config is Lua: the classic `hyprctl dispatch
focuswindow` form is a syntax error with it.
"""
import json
import subprocess
import sys

clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"],
                                    capture_output=True, text=True).stdout)
clients = [c for c in clients if c.get("mapped")]
clients.sort(key=lambda c: c["focusHistoryID"])
if not clients:
    sys.exit(0)

def label(c):
    ws = c["workspace"]["name"].removeprefix("special:")
    app = c["class"].rsplit(".", 1)[-1] or "?"
    return f"{ws:>6}  {app:<16}  {c['title'][:90]}"

lines = [f"{i:02d} {label(c)}" for i, c in enumerate(clients)]
pick = subprocess.run(["wofi", "--dmenu", "--insensitive", "--prompt", "window",
                       "--width", "900", "--lines", str(min(len(lines), 15) + 1)],
                      input="\n".join(lines), capture_output=True, text=True).stdout.strip()
if not pick:
    sys.exit(0)
# wofi --dmenu returns typed text as-is when it matches no entry; that is not
# a pick, so it is ignored rather than crashing on int().
try:
    addr = clients[int(pick.split(" ", 1)[0])]["address"]
except (ValueError, IndexError):
    sys.exit(0)
subprocess.run(["hyprctl", "dispatch", f"hl.dsp.focus({{ window = 'address:{addr}' }})"],
               capture_output=True)
