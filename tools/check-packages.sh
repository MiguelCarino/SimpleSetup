#!/bin/bash
# Checks the package names in setup.sh against the distributions that have to provide them.
# Usage: tools/check-packages.sh [flathub|arch|fedora|debian|all]   (default: all)
# Package names rot silently. Nothing in the script notices when a name is renamed upstream,
# and a single unknown name aborts the whole transaction for every user on that distribution.
cd "$(dirname "$0")/.." || exit 1
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[94m"; ENDCOLOR="\e[0m"
MISSING=0; CHECKED=0
gone() { MISSING=$((MISSING+1)); echo -e "  ${RED}MISSING${ENDCOLOR}  $1"; }
here() { CHECKED=$((CHECKED+1)); }
skip() { echo -e "  ${YELLOW}skip${ENDCOLOR}     $1"; }
WHAT="${1:-all}"

names() { grep -hoE "^($1)=.*" setup.sh | cut -d= -f2- | sed 's/#.*$//' | tr -d '"' | tr ' ' '\n' | grep -vE '^\s*$|\*|^@|/|:|^-|\$|,' | sort -u; } # the trailing comment is stripped before the split, otherwise every prose word in it is looked up as a package name; globs, dnf groups, URLs and flags cannot be looked up either

if [[ "$WHAT" == "all" || "$WHAT" == "flathub" ]]; then
    echo -e "\n${BLUE}Flathub application identifiers${ENDCOLOR}"
    for id in $(sed 's/#.*$//' setup.sh | grep -ohE '\b[a-z][a-z0-9_]*(\.[A-Za-z][A-Za-z0-9_-]*){2,}\b' | grep -vE '\.(sh|ps1|com|org|net|io|us|systems|conf|repo|list|asc|json|target|service|rpm|deb|gz|bz2|zst|d)$' | grep -vE '^org\.gnome\.desktop' | sort -u); do # same comment stripping as names() above, the flathub leg reads the whole file rather than a variable
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://flathub.org/api/v2/appstream/$id")
        if [[ "$code" == 200 ]]; then here; else gone "flathub  $id (HTTP $code)"; fi
    done
fi

if [[ "$WHAT" == "all" || "$WHAT" == "arch" ]]; then
    echo -e "\n${BLUE}Arch official repositories${ENDCOLOR}"
    for p in $(names 'arch[a-zA-Z0-9]*Packages|[a-zA-Z]+PackagesArch|i3RicingPackagesArch'); do
        n=$(curl -s --max-time 15 "https://archlinux.org/packages/search/json/?name=$p" | python3 -c 'import sys,json
try: print(len(json.load(sys.stdin)["results"]))
except Exception: print(-1)')
        if [[ "$n" -gt 0 ]]; then here
        elif [[ "$n" -lt 0 ]]; then skip "arch     $p (lookup failed)"
        elif [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://archlinux.org/groups/x86_64/$p/")" == 200 ]]; then here # xfce4 and xfce4-goodies are groups rather than packages, pacman takes both so both count as present
        else gone "arch     $p"; fi
    done
fi

if [[ "$WHAT" == "all" || "$WHAT" == "fedora" ]]; then
    echo -e "\n${BLUE}Fedora repositories${ENDCOLOR}"
    rel=$(grep -oE 'f[0-9]{2}' <<<"${FEDORA_RELEASE:-f44}" | head -1); rel="${rel:-f44}"
    fedoraQuery="" # dnf resolves a name through Provides, so wget is satisfied by wget2-wget and gnupg by gnupg2, and a bare name lookup reports nine false failures that would train everyone to ignore this report
    if command -v dnf >/dev/null 2>&1; then fedoraQuery="local"
    elif command -v docker >/dev/null 2>&1; then fedoraQuery="docker"
    elif command -v podman >/dev/null 2>&1; then fedoraQuery="podman"; fi
    case "$fedoraQuery" in
        local) provides() { dnf repoquery --qf '%{name}' --whatprovides "$1" 2>/dev/null; } ;;
        docker|podman) $fedoraQuery pull -q fedora:latest >/dev/null 2>&1; provides() { $fedoraQuery run --rm fedora:latest dnf repoquery --qf '%{name}' --whatprovides "$1" 2>/dev/null; } ;;
        *) provides() { curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://mdapi.fedoraproject.org/$rel/pkg/$1" | grep -q 200 && echo "$1"; } ;; # last resort, exact names only, so treat a miss as unproven rather than missing
    esac
    for p in $(names 'essentialPackages|basicUserPackages|basicSystemPackages|supportPackages|developmentPackages|gamingPackages|[a-zA-Z]+PackagesRPM|serverPackagesRPM'); do
        if [[ -n "$(provides "$p")" ]]; then here
        elif [[ "$fedoraQuery" == "" ]]; then skip "fedora   $p (no dnf and no container available, a virtual provide cannot be ruled out)"
        else gone "fedora   $p (nothing in the enabled repositories provides it)"; fi
    done
fi

if [[ "$WHAT" == "all" || "$WHAT" == "debian" ]]; then
    echo -e "\n${BLUE}Debian ${DEBIAN_SUITE:-trixie}${ENDCOLOR}"
    suite="${DEBIAN_SUITE:-trixie}"
    for p in $(names 'essentialPackages|basicUserPackages|basicSystemPackages|supportPackages|developmentPackages|gamingPackages|[a-zA-Z]+PackagesDebian|debian[a-zA-Z0-9]*Packages|serverPackages'); do
        body=$(curl -s -L --max-time 20 "https://packages.debian.org/$suite/$p")
        if [[ -z "$body" ]]; then skip "debian   $p (no response)"
        elif grep -qi 'No such package' <<<"$body"; then gone "debian   $p"
        else here; fi
    done
fi

echo -e "\n${BLUE}-------------------------------------${ENDCOLOR}"
if [[ "$MISSING" -eq 0 ]]; then echo -e "${GREEN}$CHECKED names checked, all still present.${ENDCOLOR}"; exit 0
else echo -e "${RED}$CHECKED names checked, $MISSING no longer resolve.${ENDCOLOR}"; exit 1; fi
