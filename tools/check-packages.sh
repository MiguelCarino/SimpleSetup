#!/bin/bash
# Checks the package names in setup.sh against the distributions that have to provide them.
# Usage: tools/check-packages.sh [coverage|flathub|arch|fedora|debian|ubuntu|opensuse|el|cheap|containers|all]   (default: all)
# Package names rot silently. Nothing in the script notices when a name is renamed upstream,
# and a single unknown name aborts the whole transaction for every user on that distribution.
cd "$(dirname "$0")/.." || exit 1
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[94m"; ENDCOLOR="\e[0m"
MISSING=0; CHECKED=0; UNPROVEN=0; UNCLAIMED=0
gone()  { MISSING=$((MISSING+1)); echo -e "  ${RED}MISSING${ENDCOLOR}   $1"; }
here()  { CHECKED=$((CHECKED+1)); }
skip()  { UNPROVEN=$((UNPROVEN+1)); echo -e "  ${YELLOW}unproven${ENDCOLOR}  $1"; } # an unproven name is neither a pass nor a failure, it is a name nothing authoritative was asked about
orphan(){ UNCLAIMED=$((UNCLAIMED+1)); echo -e "  ${RED}UNWATCHED${ENDCOLOR} $1"; }
WHAT="${1:-all}"
SENTINEL="carino-setup-sentinel-not-a-package" # asked for alongside the real names in every container leg, a leg that does not report it as missing is broken rather than clean
CRT=""; command -v podman >/dev/null 2>&1 && CRT=podman
[[ -z "$CRT" ]] && command -v docker >/dev/null 2>&1 && CRT=docker

names() { grep -hoE "^($1)=.*" setup.sh | cut -d= -f2- | sed 's/#.*$//' | tr -d '"' | tr ' ' '\n' | grep -vE '^\s*$|\*|^@|/|:|^-|\$|,' | sort -u; } # the trailing comment is stripped before the split, otherwise every prose word in it is looked up as a package name; globs, dnf groups, URLs and flags cannot be looked up either

LEGS="flathub arch fedora debian ubuntu opensuse el" # the index every *Packages* variable in setup.sh has to map onto, the coverage leg below fails the run when one maps onto none
legVars ()
{
    case "$1" in # written out rather than derived, a leg claims a variable only if the distribution it queries is the one that actually reads that variable
        flathub)  echo '' ;; # reads the whole file for application identifiers, it claims no shell variable
        arch)     echo 'arch[a-z0-9]*Packages|[a-zA-Z0-9]+PackagesArch' ;;
        fedora)   echo 'essentialPackages|basicUserPackages|basicSystemPackages|basicDesktopEnvironmentPackages|supportPackages|developmentPackages|gamingPackages|multimediaPackages|virtconPackages|amdPackages|nvidiaPackages|intelPackages|i3RicingPackages|languagePackages|carinoPackages|ciscoPackages|astronomyPackages|compneuroPackages|designPackages|musicPackages|securityPackages|forensicsPackages|scientificPackages|roboticsPackages|fedora[a-z0-9]*Packages|[a-zA-Z0-9]+PackagesRPM' ;;
        debian)   echo 'essentialPackages|basicUserPackages|basicSystemPackages|supportPackages|developmentPackages|gamingPackages|virtconPackages|amdPackages|intelPackages|i3RicingPackages|serverPackages|astronomyPackages|compneuroPackages|designPackages|musicPackages|securityPackages|forensicsPackages|scientificPackages|roboticsPackages|debian[a-z0-9]*Packages|[a-zA-Z0-9]+PackagesDebian' ;; # nvidiaPackages is absent on purpose, the debian arm replaces it with nvidiaPackagesDebian or nvidiaPackagesUbuntu and never installs the shared RPM shaped value
        ubuntu)   echo '[a-zA-Z0-9]+PackagesUbuntu' ;;
        opensuse) echo 'opensuse[a-z0-9]*Packages|[a-zA-Z0-9]+PackagesOpenSUSE' ;;
        el)       echo 'rhel[a-z0-9]*Packages|centos[a-z0-9]*Packages' ;;
    esac
}
packageVars() { grep -oE '^[a-zA-Z][a-zA-Z0-9_]*Packages[a-zA-Z0-9]*=' setup.sh | tr -d '=' | sort -u; }

image ()
{
    case "$1" in # the suite each family's names have to resolve in, overridable so a new stable can be rehearsed before it ships
        debian)   echo "docker.io/library/debian:${DEBIAN_SUITE:-trixie}" ;;
        ubuntu)   echo "docker.io/library/ubuntu:${UBUNTU_SUITE:-24.04}" ;;
        fedora)   echo "docker.io/library/fedora:${FEDORA_RELEASE:-latest}" ;;
        opensuse) echo "docker.io/opensuse/${OPENSUSE_RELEASE:-tumbleweed}" ;;
        el)       echo "${EL_IMAGE:-quay.io/centos/centos:stream10}" ;;
    esac
}
inContainer ()
{
    local img=$1 inner=$2; shift 2
    $CRT pull -q "$img" >/dev/null 2>&1 || return 1
    $CRT run --rm "$img" bash -c "$inner" _ "$@" 2>/dev/null
}
APT='sed -i "s/^Components: main.*/Components: main contrib non-free non-free-firmware/" /etc/apt/sources.list.d/debian.sources 2>/dev/null; apt-get update -qq >/dev/null 2>&1; apt-get install -s -qq "$@" 2>&1 | sed -n "s/^E: Unable to locate package //p; s/^E: Package .\(.*\). has no installation candidate\$/\1/p"' # the authority is the resolver itself, which honours Provides and virtual packages exactly as the real install would; a web page is not an authority, packages.debian.org answers a missing name with two different error pages and the second one used to read as EXISTS. The extra components mirror what nvidiaRepoSetup enables, without them the five nvidiaPackagesDebian names read as missing when they are only hidden
DNF='dnf -q -y install "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" >/dev/null 2>&1; dnf -q install --assumeno "$@" 2>&1 | sed -n "s/^No match for argument: //p"' # RPM Fusion is enabled first because techSetup and nvidiaRepoSetup both enable it, and akmod-nvidia, the freeworld codecs and lpf-spotify-client are in no stock Fedora repository
EL='dnf -q -y install epel-release >/dev/null 2>&1; dnf -q config-manager --set-enabled crb >/dev/null 2>&1 || dnf -q config-manager setopt crb.enabled=1 >/dev/null 2>&1; dnf install --assumeno "$@" 2>&1 | sed -n "s/^No match for argument: //p"' # rhelRepo and centosRepo both enable CRB and EPEL before installing, so the check has to see the same repositories the user will, and the install is deliberately not quiet because the dnf4 the rebuilds still ship prints its per argument "No match" lines only when it is not
ZYP='zypper -n install openSUSE-repos-Tumbleweed-NVIDIA >/dev/null 2>&1; zypper -n --gpg-auto-import-keys refresh >/dev/null 2>&1; zypper -n install -D "$@" 2>&1 | sed -n "s/^No provider of .\(.*\). found\..*/\1/p"' # nvidiaRepoSetup installs exactly this package and refreshes, the G06 userspace libraries live in NVIDIA's own repository and read as missing without it; point OPENSUSE_RELEASE at a Leap image and this line needs the Leap spelling of the same package

checkLeg ()
{
    local leg=$1 inner=$2 img all miss p
    img=$(image "$leg")
    all=$(names "$(legVars "$leg")")
    [[ -z "$all" ]] && return 0
    if [[ -z "$CRT" ]]; then
        for p in $all; do skip "$leg  $p (no podman and no docker, nothing authoritative was asked, treat this leg as unproven)"; done
        return 0
    fi
    miss=$(inContainer "$img" "$inner" $all "$SENTINEL") || { for p in $all; do skip "$leg  $p ($img could not be pulled or run)"; done; return 0; }
    if ! grep -qxF "$SENTINEL" <<<"$miss"; then for p in $all; do skip "$leg  $p (the query did not even report $SENTINEL as missing, so it proved nothing)"; done; return 0; fi # a query that answers nothing looks exactly like a query that answers "all present", which is the false pass this whole tool exists to stop
    for p in $all; do
        if grep -qxF "$p" <<<"$miss"; then gone "$leg  $p (nothing in $img provides it)"; else here; fi
    done
}

if [[ "$WHAT" == all || "$WHAT" == cheap || "$WHAT" == coverage ]]; then
    echo -e "\n${BLUE}Coverage: every package list in setup.sh is claimed by a leg${ENDCOLOR}"
    for v in $(packageVars); do
        claim=""
        for leg in $LEGS; do
            rx=$(legVars "$leg"); [[ -z "$rx" ]] && continue
            [[ "$v" =~ ^($rx)$ ]] && claim="$claim $leg"
        done
        if [[ -z "$claim" ]]; then orphan "$v is claimed by no leg, a rename inside it would ship unnoticed"; else here; fi
    done
fi

if [[ "$WHAT" == all || "$WHAT" == cheap || "$WHAT" == flathub ]]; then
    echo -e "\n${BLUE}Flathub application identifiers${ENDCOLOR}"
    for id in $(sed 's/#.*$//' setup.sh | grep -ohE '\b[a-z][a-z0-9_]*(\.[A-Za-z][A-Za-z0-9_-]*){2,}\b' | grep -vE '\.(sh|ps1|com|org|net|io|us|systems|conf|repo|list|asc|json|target|service|rpm|deb|gz|bz2|zst|d)$' | grep -vE '^org\.gnome\.desktop' | sort -u); do # same comment stripping as names() above, the flathub leg reads the whole file rather than a variable
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://flathub.org/api/v2/appstream/$id")
        if [[ "$code" == 200 ]]; then here; else gone "flathub  $id (HTTP $code)"; fi
    done
fi

if [[ "$WHAT" == all || "$WHAT" == cheap || "$WHAT" == arch ]]; then
    echo -e "\n${BLUE}Arch official repositories${ENDCOLOR}"
    for p in $(names "$(legVars arch)"); do
        n=$(curl -s --max-time 15 "https://archlinux.org/packages/search/json/?name=$p" | python3 -c 'import sys,json
try: print(len(json.load(sys.stdin)["results"]))
except Exception: print(-1)')
        if [[ "$n" -gt 0 ]]; then here
        elif [[ "$n" -lt 0 ]]; then skip "arch      $p (lookup failed)"
        elif [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://archlinux.org/groups/x86_64/$p/")" == 200 ]]; then here # xfce4 and xfce4-goodies are groups rather than packages, pacman takes both so both count as present
        else gone "arch      $p"; fi
    done
fi

if [[ "$WHAT" == all || "$WHAT" == containers || "$WHAT" == fedora ]]; then
    echo -e "\n${BLUE}Fedora $(image fedora)${ENDCOLOR}"; checkLeg fedora "$DNF"
fi
if [[ "$WHAT" == all || "$WHAT" == containers || "$WHAT" == debian ]]; then
    echo -e "\n${BLUE}Debian $(image debian)${ENDCOLOR}"; checkLeg debian "$APT"
fi
if [[ "$WHAT" == all || "$WHAT" == containers || "$WHAT" == ubuntu ]]; then
    echo -e "\n${BLUE}Ubuntu $(image ubuntu)${ENDCOLOR}"; checkLeg ubuntu "$APT"
fi
if [[ "$WHAT" == all || "$WHAT" == containers || "$WHAT" == opensuse ]]; then
    echo -e "\n${BLUE}openSUSE $(image opensuse)${ENDCOLOR}"; checkLeg opensuse "$ZYP"
fi
if [[ "$WHAT" == all || "$WHAT" == containers || "$WHAT" == el ]]; then
    echo -e "\n${BLUE}Enterprise Linux $(image el)${ENDCOLOR}"; checkLeg el "$EL"
fi

echo -e "\n${BLUE}-------------------------------------${ENDCOLOR}"
[[ "$UNPROVEN" -gt 0 ]] && echo -e "${YELLOW}$UNPROVEN name(s) unproven: the leg above answered with no authority, so it proved nothing and must not be read as a pass.${ENDCOLOR}"
[[ "$UNCLAIMED" -gt 0 ]] && echo -e "${RED}$UNCLAIMED package list(s) are watched by no leg. Add them to legVars or the next rename in them ships silently.${ENDCOLOR}"
if [[ "$MISSING" -eq 0 && "$UNCLAIMED" -eq 0 ]]; then echo -e "${GREEN}$CHECKED names checked, all still present.${ENDCOLOR}"; exit 0
else echo -e "${RED}$CHECKED names checked, $MISSING no longer resolve.${ENDCOLOR}"; exit 1; fi
