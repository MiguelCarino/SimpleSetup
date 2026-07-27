#!/bin/bash
# Carino Setup test harness. Run from the repository root: ./test.sh [--network]
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
for f in setup.sh macos.sh test.sh tools/check-packages.sh; do
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

osr()        { printf 'NAME="%s"\nVERSION_ID="%s"\n' "$1" "${2:-1}" > "$WORK/osr"; }
runFake()    { osr "$1" "$2"; printf '2\n1\n7\n' | CARINO_SETUP_OSRELEASE="$WORK/osr" CARINO_SETUP_LOG="$WORK/log" timeout 90 bash setup.sh dry-run 2>&1; }
runArg()     { osr "$1"; CARINO_SETUP_OSRELEASE="$WORK/osr" CARINO_SETUP_LOG="$WORK/log" timeout 90 bash setup.sh dry-run "$2" </dev/null 2>&1; } # stdin is closed on purpose, an argument that still reads a prompt has to end rather than hang
runPlanned() { osr "$1"; CARINO_SETUP_PLAN="$2" CARINO_SETUP_OSRELEASE="$WORK/osr" CARINO_SETUP_LOG="$WORK/log" timeout 120 bash setup.sh dry-run </dev/null 2>&1; }
installLine ()
{
    local pkgm=$1 verb=$2 best="" bestn=-1 line n x; local -a t # the longest "sudo <package manager>" command in the run is the package install, picking it by length rather than by the verb keeps a misspelled verb detectable instead of silently unmatched
    while IFS= read -r line; do
        [[ "$line" == *"DRY-RUN: sudo "* ]] || continue
        line="${line#*DRY-RUN: sudo }"
        read -r -a t <<< "$line"
        [[ "${t[0]}" == "$pkgm" ]] || continue
        n=0; for x in "${t[@]:1}"; do [[ "$x" == -* || "$x" == "$verb" ]] && continue; n=$((n+1)); done
        [[ "$n" -gt "$bestn" ]] && { bestn=$n; best="$line"; }
    done
    echo "$bestn $best"
}

head2 "3. Supported distributions emit an install command of the right shape"
while IFS='|' read -r name pkgm verb flag min; do
    [[ -z "$name" ]] && continue
    res=$(runFake "$name" 1 | installLine "$pkgm" "$verb"); n="${res%% *}"; line="${res#* }"
    why=""
    [[ "$n" -lt 0 ]] && why=" it never ran 'sudo $pkgm' at all;"
    if [[ "$n" -ge 0 ]]; then
        [[ " $line " == *" $verb "* ]] || why="$why the install verb '$verb' is not in it;"
        [[ " $line " == *" $flag "* ]] || why="$why '$flag' is missing, so the transaction would stop and ask;"
        [[ "$n" -ge "$min" ]]          || why="$why only $n package operand(s), at least $min were expected;"
    fi
    if [[ -z "$why" ]]; then ok "$name -> sudo $pkgm ... $verb ... $flag, $n operands"
    else bad "$name emitted a malformed install:$why"; [[ "$n" -ge 0 ]] && echo "        sudo $line" | cut -c1-160; fi
done <<'FAMILIES'
Fedora Linux|dnf|install|-y|12
Debian GNU/Linux|apt|install|-y|12
Ubuntu|apt|install|-y|12
Linux Mint|apt|install|-y|12
Arch Linux|pacman|-S|--noconfirm|10
Manjaro Linux|pacman|-S|--noconfirm|10
openSUSE Tumbleweed|zypper|install|-n|12
CentOS Stream|dnf|install|-y|12
Rocky Linux|dnf|install|-y|12
Red Hat Enterprise Linux|dnf|install|-y|12
Amazon Linux|dnf|install|-y|12
FAMILIES

head2 "4. Declined distributions run nothing at all"
while read -r name; do
    [[ -z "$name" ]] && continue
    out=$(runFake "$name" 1)
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
out=$(runFake "Definitely Not A Real Distro" 1)
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

ARGTABLE='quick|install
nvidia|any
amd|any
intel|any
svp|run
simple|install
server|install
distrobox|run
desktop|any
anydesk|install
anydesk-repo|any
librewolf|run
share|any
proton|run' # "install" has to reach the package manager, "run" has to run something privileged or mutating, "any" only has to end and say something rather than hang or crash, because graphicDrivers reads the real lspci and the repo arms write through a redirect the shims cannot print past
head2 "7. Every implemented argument runs to completion"
for a in $impl; do grep -q "^$a|" <<<"$ARGTABLE" || bad "the argument '$a' is dispatched by setup.sh but nothing here drives it"; done
while IFS='|' read -r arg expect; do
    out=$(runArg "Fedora Linux" "$arg"); rc=$?
    why=""
    [[ "$rc" -eq 124 ]] && why="$why it never ended, something is still waiting on stdin;"
    grep -qE 'command not found|syntax error|unbound variable|bad substitution|: line [0-9]+:' <<<"$out" && why="$why the shell reported an error;"
    case "$expect" in
        install) grep -qE 'DRY-RUN: sudo dnf (install|update|config-manager)' <<<"$out" || why="$why it never asked dnf for anything;" ;;
        run)     grep -q 'DRY-RUN:' <<<"$out" || why="$why it ran no command at all;" ;;
    esac
    [[ -z "$why" ]] && ok "argument $arg ($expect)" || bad "argument $arg:$why"
done <<<"$ARGTABLE"

head2 "8. CARINO_SETUP_PLAN runs instead of the menu, by name, and refuses what it does not know"
while IFS='|' read -r plan marker; do
    [[ -z "$plan" ]] && continue
    out=$(runPlanned "Fedora Linux" "$plan"); rc=$?
    clean=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$out")
    why=""
    [[ "$rc" -eq 0 ]] || why="$why it exited $rc;"
    grep -q "$marker" <<<"$clean" || why="$why '$marker' never appeared;"
    grep -qE '^[0-9]+\. ' <<<"$clean" && why="$why a numbered menu was drawn, the plan is supposed to replace it;" # P3 and P4, no menu is drawn and the run does not fall through into displayMenu afterwards
    grep -q 'CARINO_SETUP_PLAN has finished' <<<"$clean" || why="$why the plan never reported finishing;"
    [[ -z "$why" ]] && ok "PLAN=$plan" || bad "PLAN=$plan:$why"
done <<'PLANS'
technical|Plan step: technical
desktop=xfce|Plan step: desktop xfce
drivers|Plan step: drivers
update|Plan step: update
server|Plan step: server
purpose=gaming|Plan step: purpose gaming
purpose=corporate-microsoft|Plan step: purpose corporate-microsoft
technical,desktop=kde,purpose=gaming|Plan step: purpose gaming
PLANS
out=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$(runPlanned "Fedora Linux" "technical,desktop=kde,purpose=gaming")")
order=$(grep -oE 'Plan step: (technical|desktop kde|purpose gaming)' <<<"$out" | sed 's/^Plan step: //' | tr '\n' '/')
[[ "$order" == "technical/desktop kde/purpose gaming/" ]] && ok "a three directive plan runs strictly left to right" || bad "a three directive plan ran in the order [$order]"
while IFS='|' read -r plan token valids; do
    [[ -z "$plan" ]] && continue
    out=$(runPlanned "Fedora Linux" "$plan"); rc=$?
    clean=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$out")
    why=""
    [[ "$rc" -eq 0 ]] && why="$why it exited 0 instead of refusing;"
    [[ $(grep -c 'DRY-RUN:' <<<"$clean") -eq 0 ]] || why="$why it installed something before refusing;"
    grep -qF "$token" <<<"$clean" || why="$why it never named the bad token '$token';"
    grep -qF "$valids" <<<"$clean" || why="$why it never said what would have been accepted instead;"
    [[ -z "$why" ]] && ok "PLAN=$plan is refused before anything is installed" || bad "PLAN=$plan:$why"
done <<'BADPLANS'
frobnicate|frobnicate|Valid directives:
purpose=nope|nope|Valid purposes:
desktop=nope|nope|Valid desktops:
technical,purpose=gamming|gamming|Valid purposes:
reboot=maybe|reboot=maybe|reboot takes yes or no
reboot=yes|names no action|Valid directives:
BADPLANS
out=$(runPlanned "Fedora Linux" $'technical\npurpose=nope'); rc=$?
clean=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$out")
if [[ "$rc" -ne 0 ]] && [[ $(grep -c 'DRY-RUN:' <<<"$clean") -eq 0 ]] && grep -qF "'nope' is not a purpose name" <<<"$clean"; then ok "a plan wrapped across lines is parsed whole, not truncated at the first newline"
else bad "a newline in CARINO_SETUP_PLAN discarded everything after it (exit $rc, $(grep -c 'DRY-RUN:' <<<"$clean") commands)"; fi
out=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$(runPlanned "Fedora Linux" "update")")
grep -q 'Non-interactive run: reboot=no (default: no)' <<<"$out" && ! grep -q 'DRY-RUN: sudo reboot' <<<"$out" && ok "askReboot takes its documented default and says so" || bad "askReboot did not take the no-reboot default out loud"
out=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$(runPlanned "Fedora Linux" "update,reboot=yes")")
grep -q 'DRY-RUN: sudo reboot' <<<"$out" && ok "reboot=yes reboots at the end" || bad "reboot=yes did not reboot"
osr "Fedora Linux"; out=$(CARINO_SETUP_DRYRUN=1 CARINO_SETUP_PLAN=purpose=basic CARINO_SETUP_OSRELEASE="$WORK/osr" CARINO_SETUP_LOG="$WORK/log" timeout 120 bash setup.sh </dev/null 2>&1)
[[ $(grep -c 'DRY-RUN:' <<<"$out") -gt 0 ]] && ok "a plan composes with CARINO_SETUP_DRYRUN=1 and no dry-run argument" || bad "CARINO_SETUP_DRYRUN=1 did not intercept a plan"
osr "Gentoo"; out=$(CARINO_SETUP_PLAN=technical CARINO_SETUP_OSRELEASE="$WORK/osr" CARINO_SETUP_LOG="$WORK/log" timeout 120 bash setup.sh dry-run </dev/null 2>&1); rc=$?
if [[ "$rc" -ne 0 ]] && [[ $(grep -c 'DRY-RUN:' <<<"$out") -eq 0 ]] && grep -q 'was refused and nothing was installed' <<<"$out"; then ok "a declined distribution refuses the plan the same way it refuses the menu"
else bad "a declined distribution did not refuse the plan (exit $rc, $(grep -c 'DRY-RUN:' <<<"$out") commands)"; fi
osr "Fedora Linux"; out=$(CARINO_SETUP_PLAN=technical CARINO_SETUP_OSRELEASE="$WORK/osr" CARINO_SETUP_LOG="$WORK/log" timeout 120 bash setup.sh dry-run quick </dev/null 2>&1); rc=$?
[[ "$rc" -ne 0 ]] && [[ $(grep -c 'DRY-RUN:' <<<"$out") -eq 0 ]] && ok "a plan and an argument together are refused rather than half run" || bad "a plan plus an argument ran anyway (exit $rc)"
for name in basic gaming corporate corporate-microsoft corporate-google development astronomy compneuro design music cybersecurity forensics scientific robotics; do
    awk '/^planPurposeNumber/,/^}/' setup.sh | grep -qE "^\s*$name\)" || bad "the purpose name '$name' in the frozen contract has no entry in planPurposeNumber"
done
for name in gnome xfce kde lxqt cinnamon mate i3 openbox budgie sway hyprland niri none; do
    grep -m1 '^planDesktopNames=' setup.sh | grep -qw "$name" || bad "the desktop name '$name' in the frozen contract is not in planDesktopNames"
done
ok "every purpose and desktop name in the frozen contract is still spelled the same in setup.sh"

head2 "9. The index refresh in updateSystem uses flags its own package manager accepts"
while IFS='|' read -r name pkgm refresh want unwanted; do
    [[ -z "$name" ]] && continue
    out=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$(runPlanned "$name" update)")
    line=$(grep -m1 -E "DRY-RUN: sudo $pkgm( .*)? $refresh( |$)" <<<"$out"); line="${line#*DRY-RUN: sudo }"
    why=""
    [[ -n "$line" ]] || why="$why it never refreshed with 'sudo $pkgm ... $refresh';"
    [[ -z "$line" || "$want" == "-" || " $line " == *" $want "* ]] || why="$why '$want' is missing, so the refresh would stop and ask;"
    [[ -n "$line" && "$unwanted" != "-" && " $line " == *" $unwanted "* ]] && why="$why it passed '$unwanted' to $refresh, which $pkgm rejects outright, so the index is never refreshed;"
    [[ -z "$why" ]] && ok "$name refreshes with 'sudo $line'" || bad "$name refresh is malformed:$why"
done <<'REFRESH'
Fedora Linux|dnf|update|-y|-
Debian GNU/Linux|apt|update|-y|-f
Ubuntu|apt|update|-y|-f
Linux Mint|apt|update|-y|-f
Arch Linux|pacman|-Syu|--noconfirm|-
openSUSE Tumbleweed|zypper|refresh|-n|-y
CentOS Stream|dnf|update|-y|-
Red Hat Enterprise Linux|dnf|update|-y|-
REFRESH

if [[ "$NETWORK" == 1 ]]; then
    head2 "10. Network: published URLs and Flathub identifiers"
    for u in $(grep -ohE 'https?://[a-zA-Z0-9./_-]+' README.md index.html | sort -u); do
        c=$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 15 "$u")
        [[ "$c" == 200 ]] && ok "$c $u" || bad "$c $u"
    done
    for id in $(sed 's/#.*$//' setup.sh | grep -oE '\b[a-z][a-z0-9_]*(\.[A-Za-z][A-Za-z0-9_-]*){2,}\b' | grep -vE '\.(sh|ps1|com|org|net|io|us|systems|conf|repo|list|asc|json|target|service|rpm|deb|gz|bz2|zst|d)$' | grep -vE '^org\.gnome\.desktop' | sort -u); do # comments are stripped first, a trailing note naming the wrong identifier that was replaced would otherwise be looked up as if the script still installed it
        c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://flathub.org/api/v2/appstream/$id")
        [[ "$c" == 200 ]] && ok "flathub $id" || bad "flathub $id returned $c"
    done
else
    echo -e "\n${YELLOW}Skipping the network checks. Re-run with --network to verify URLs and Flathub identifiers.${ENDCOLOR}"
fi

echo -e "\n${BLUE}-------------------------------------${ENDCOLOR}"
if [[ "$FAIL" -eq 0 ]]; then echo -e "${GREEN}$PASS passed, 0 failed.${ENDCOLOR}"; exit 0
else echo -e "${RED}$PASS passed, $FAIL FAILED.${ENDCOLOR}"; exit 1; fi
