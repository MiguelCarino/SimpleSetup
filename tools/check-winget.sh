#!/usr/bin/env bash
# Checks that every winget id in setup.ps1 (section 4, the $PKG table) exists in microsoft/winget-pkgs.
# Usage: tools/check-winget.sh [id ...]      (no ids: every id in setup.ps1)
# Uses `gh api` when gh is logged in, else curl against api.github.com (set GITHUB_TOKEN to avoid the
# 60 requests/hour anonymous limit). An id exists when one of its version folders holds <id>.yaml.
cd "$(dirname "$0")/.." || exit 1
FOUND=0 MISSING=0 UNPROVEN=0 GH=0
command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && GH=1

api() { # api <repo path>: prints the JSON listing of a winget-pkgs folder, fails when it does not exist
    local url="repos/microsoft/winget-pkgs/contents/$1"
    if (( GH )); then
        gh api "$url" 2>/dev/null
    else
        curl -sf --max-time 20 ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "https://api.github.com/$url"
    fi
}
dirs() { python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(2)
if not isinstance(d,list): sys.exit(2)
print("\n".join(e["name"] for e in d if e.get("type")=="dir"))'; }
files() { python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: d=[]
print("\n".join(e["name"] for e in d if isinstance(e,dict) and e.get("type")=="file") if isinstance(d,list) else "")'; }

ids() { # the quoted ids inside the @( ... ) lists of the $PKG = @{ ... } block of setup.ps1 (keys are not ids)
    awk '/^\$PKG = @\{/{f=1;next} f&&/^\}/{exit} f' setup.ps1 | sed 's/#.*//' | grep -o '@(.*)' |
        grep -oE "'[A-Za-z0-9][^' ]*'" | tr -d "'" | sort -u
}
check() { # check <id>
    local id=$1 path listing versions v; local -a cand
    path="manifests/$(printf '%s' "${id:0:1}" | tr '[:upper:]' '[:lower:]')/${id//.//}"
    listing=$(api "$path") || { MISSING=$((MISSING + 1)); printf '  MISSING   %s\n' "$id"; return; }
    versions=$(dirs <<<"$listing") || { UNPROVEN=$((UNPROVEN + 1)); printf '  unproven  %s (unexpected answer)\n' "$id"; return; }
    # a digit-named folder can also be a sub-package (Microsoft.Office.2010), so try the newest few
    mapfile -t cand < <( (grep -E '^[0-9]' <<<"$versions" | sort -rV; grep -vE '^[0-9]' <<<"$versions") | head -n3)
    for v in "${cand[@]}"; do   # version folders can hold spaces ("6.0 patchlevel 4")
        if api "$path/${v// /%20}" | files | grep -qxF -- "$id.yaml"; then FOUND=$((FOUND + 1)); return; fi
    done
    MISSING=$((MISSING + 1)); printf '  MISSING   %s (a folder, but no version in it holds %s.yaml)\n' "$id" "$id"
}

if (( $# )); then list=("$@"); else mapfile -t list < <(ids); fi
(( ${#list[@]} )) || { echo "No winget ids found in setup.ps1."; exit 1; }
printf 'winget-pkgs: %d ids\n' "${#list[@]}"
for id in "${list[@]}"; do check "$id"; done
printf '\n%d ids exist, %d missing, %d unproven\n' "$FOUND" "$MISSING" "$UNPROVEN"
(( MISSING == 0 ))
