#!/usr/bin/env bash
# Checks that every formula and cask in macos.sh (section 4, arrays brew_<group> / cask_<group>) exists on
# formulae.brew.sh and is not deprecated or disabled. HTTP only, runs on any system with curl and python3.
# Usage: tools/check-brew.sh
cd "$(dirname "$0")/.." || exit 1
MISSING=0 CHECKED=0 STALE=0
# shellcheck source=/dev/null  # section 4 of macos.sh is plain data: arrays only
source <(awk '/^# ==== 4\./,/^# ==== 5\./' macos.sh)
lookup() { # lookup formula|cask <name>: prints ok, deprecated, disabled or missing
    curl -s --max-time 20 -w '\n%{http_code}' "https://formulae.brew.sh/api/$1/$2.json" | python3 -I -c 'import sys,json
body, _, code = sys.stdin.read().rpartition("\n")
if code != "200": print("missing"); sys.exit()
try: d = json.loads(body)
except Exception: print("missing"); sys.exit()
print("disabled" if d.get("disabled") else "deprecated" if d.get("deprecated") else "ok")'
}
for kind in brew cask; do
    api=formula; [[ $kind == cask ]] && api=cask
    printf '\n%s (formulae.brew.sh/api/%s)\n' "$kind" "$api"
    for n in $(for a in $(compgen -A arrayvar | grep -E "^${kind}_"); do declare -n l=$a; printf '%s\n' "${l[@]}"; unset -n l; done | sort -u); do
        case $(lookup "$api" "$n") in
            ok)         CHECKED=$((CHECKED + 1)) ;;
            deprecated|disabled) STALE=$((STALE + 1)); printf '  STALE     %s %s (%s)\n' "$api" "$n" "$(lookup "$api" "$n")" ;;
            *)          MISSING=$((MISSING + 1)); printf '  MISSING   %s %s\n' "$api" "$n" ;;
        esac
    done
done
printf '\n%d names resolve, %d missing, %d deprecated or disabled\n' "$CHECKED" "$MISSING" "$STALE"
(( MISSING + STALE == 0 ))
