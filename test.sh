#!/bin/bash
# SimpleSetup test harness. Run from the repository root: ./test.sh [--network]
# Exits non-zero on the first failing category, so CI can gate a push on it.
cd "$(dirname "$0")" || exit 1
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[94m"; ENDCOLOR="\e[0m"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo -e "  ${GREEN}pass${ENDCOLOR}  $1"; }
bad()  { FAIL=$((FAIL+1)); echo -e "  ${RED}FAIL${ENDCOLOR}  $1"; }
head2() { echo -e "\n${BLUE}$1${ENDCOLOR}"; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
NETWORK=0; [[ "$1" == "--network" ]] && NETWORK=1

head2 "1. Syntax"
for f in setup.sh macos.sh test.sh; do
    if bash -n "$f" 2>/dev/null; then ok "$f parses"; else bad "$f does not parse"; bash -n "$f"; fi
done

head2 "2. Menu numbering matches the case statement that dispatches it"
menuNumbers() { grep -m1 "^\s*$1=" setup.sh | grep -o '\\n[0-9]\+\.' | tr -cd '0-9\n' | sed '/^$/d' | sort -n | tr '\n' ' '; } # the printed list, read out of the localized string
caseNumbers() { awk "/^$1 ?\(\)/,/^}/" setup.sh | grep -oE '^\s{2,8}[0-9]+\)' | tr -cd '0-9\n' | sed '/^$/d' | sort -n | tr '\n' ' '; } # the labels the shell will actually match against
deNumbers()   { grep -m1 'What Desktop Environment' setup.sh | grep -o '\\n[0-9]\+\.' | tr -cd '0-9\n' | sed '/^$/d' | sort -n | tr '\n' ' '; }
for lang in en_US ja_JP ru_RU es_ES fi_FI zh_CN ko_KR he_IL; do
    for pair in "tech_setup:displayMenu" "purpose_setup:purposeMenu"; do
        var="${pair%%:*}_${lang}"; fn="${pair##*:}"
        printed=$(menuNumbers "$var"); dispatched=$(caseNumbers "$fn")
        if [[ -z "$printed" ]]; then bad "$var is missing entirely"
        elif [[ "$printed" == "$dispatched" ]]; then ok "$var prints [$printed] and $fn dispatches the same"
        else bad "$var prints [$printed] but $fn dispatches [$dispatched]"; fi
    done
done
printed=$(deNumbers); dispatched=$(caseNumbers desktopenvironmentMenu)
if [[ "$printed" == "$dispatched" ]]; then ok "desktop menu prints [$printed] and dispatches the same"
else bad "desktop menu prints [$printed] but dispatches [$dispatched]"; fi

head2 "3. Supported distributions produce a real install command"
runFake() { printf 'NAME="%s"\nVERSION_ID="%s"\n' "$1" "${2:-1}" > "$WORK/osr"; printf '2\n1\n7\n' | SIMPLESETUP_OSRELEASE="$WORK/osr" SIMPLESETUP_LOG="$WORK/log" timeout 60 bash setup.sh dry-run 2>&1; }
while IFS='|' read -r name expect; do
    [[ -z "$name" ]] && continue
    out=$(runFake "$name")
    if grep -q "DRY-RUN: sudo $expect" <<<"$out"; then ok "$name -> sudo $expect"
    else bad "$name did not emit 'sudo $expect'"; grep -m2 'DRY-RUN\|not supported' <<<"$out" | sed 's/^/        /'; fi
done <<'FAMILIES'
Fedora Linux|dnf
Debian GNU/Linux|apt
Ubuntu|apt
Linux Mint|apt
Arch Linux|pacman
Manjaro Linux|pacman
openSUSE Tumbleweed|zypper
CentOS Stream|dnf
Rocky Linux|dnf
Red Hat Enterprise Linux|dnf
Amazon Linux|dnf
FAMILIES

head2 "4. Declined distributions run nothing at all"
while read -r name; do
    [[ -z "$name" ]] && continue
    out=$(runFake "$name")
    n=$(grep -c 'DRY-RUN:' <<<"$out")
    if [[ "$n" -eq 0 ]] && grep -q 'not supported' <<<"$out"; then ok "$name refuses and runs 0 commands"
    elif [[ "$n" -ne 0 ]]; then bad "$name ran $n command(s) despite being unsupported"; grep -m2 'DRY-RUN:' <<<"$out" | sed 's/^/        /'
    else bad "$name ran nothing but never said why"; fi
done <<'DECLINED'
Gentoo
NixOS
Slackware
Alpine Linux
Void Linux
SteamOS
openSUSE MicroOS
Solus
Qubes OS
Clear Linux OS
Guix System
Artix Linux
Mageia
OpenMandriva Lx
Chimera Linux
DECLINED
out=$(runFake "Definitely Not A Real Distro")
if [[ $(grep -c 'DRY-RUN:' <<<"$out") -eq 0 ]]; then ok "an unknown distribution runs 0 commands"; else bad "an unknown distribution ran a command"; fi

head2 "5. Documented arguments exist, and implemented ones are documented"
impl=$(awk '/^detectArgument/,/^}/' setup.sh | grep -oE '^\s{8}[a-z][a-z-]*\)' | tr -d ' )' | sort -u)
doc=$(grep -oE '^- [a-z][a-z-]*\\?$' README.md | sed 's/^- //; s/\\$//' | sort -u)
missing=$(comm -13 <(echo "$impl") <(echo "$doc")); extra=$(comm -23 <(echo "$impl") <(echo "$doc"))
[[ -z "$missing" ]] && ok "every documented argument is implemented" || bad "documented but not implemented: $(echo $missing)"
[[ -z "$extra" ]]   && ok "every implemented argument is documented" || bad "implemented but not documented: $(echo $extra)"

head2 "6. Desktop package list exists for every family the script claims"
fams=$(awk '/^identifyDistro/,/^}/' setup.sh | grep -oP 'family=\K"?\w+' | tr -d '"' | sort -u)
for f in $fams; do
    miss=""
    for d in gnome xfce kde mate cinnamon lxqt i3 openbox budgie sway hyprland niri; do
        v=$(grep -m1 "^${f}${d}Packages=" setup.sh | cut -d= -f2- | tr -d '"')
        [[ -z "$v" ]] && miss="$miss $d"
    done
    if [[ -z "$miss" ]]; then ok "$f has all 12 desktop lists"
    else echo -e "  ${YELLOW}note${ENDCOLOR}  $f has no list for:$miss (installDesktopEnvironment refuses by name, it does not install nothing silently)"; fi
done

if [[ "$NETWORK" == 1 ]]; then
    head2 "7. Network: published URLs and Flathub identifiers"
    for u in $(grep -ohE 'https?://[a-zA-Z0-9./_-]+' README.md index.html | sort -u); do
        c=$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 15 "$u")
        [[ "$c" == 200 ]] && ok "$c $u" || bad "$c $u"
    done
    for id in $(grep -oE '\b[a-z][a-z0-9_]*(\.[A-Za-z][A-Za-z0-9_-]*){2,}\b' setup.sh | grep -vE '\.(sh|ps1|com|org|net|io|us|systems|conf|repo|list|asc|json|target|service|rpm|deb|gz|bz2|zst|d)$' | grep -vE '^org\.gnome\.desktop' | sort -u); do
        c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://flathub.org/api/v2/appstream/$id")
        [[ "$c" == 200 ]] && ok "flathub $id" || bad "flathub $id returned $c"
    done
else
    echo -e "\n${YELLOW}Skipping the network checks. Re-run with --network to verify URLs and Flathub identifiers.${ENDCOLOR}"
fi

echo -e "\n${BLUE}-------------------------------------${ENDCOLOR}"
if [[ "$FAIL" -eq 0 ]]; then echo -e "${GREEN}$PASS passed, 0 failed.${ENDCOLOR}"; exit 0
else echo -e "${RED}$PASS passed, $FAIL FAILED.${ENDCOLOR}"; exit 1; fi
