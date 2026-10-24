#!/usr/bin/env bash
# Checks that the package names in setup.sh (section 4, arrays <group>_<family>) still resolve.
# Usage: tools/check-packages.sh [coverage|flathub|arch|slackware|fedora|debian|ubuntu|opensuse|el|alpine|void|void-musl|cheap|containers|all]
#   cheap      = coverage + flathub + arch + slackware (HTTP only)
#   containers = fedora debian ubuntu opensuse el alpine void void-musl
# A single unknown name used to abort a whole transaction; setup.sh now skips unknown names, so a
# name that rots silently drops a feature instead. This script is how that is noticed.
cd "$(dirname "$0")/.." || exit 1
WHAT=${1:-all}
MISSING=0 CHECKED=0 UNPROVEN=0
gone() { MISSING=$((MISSING + 1)); printf '  MISSING   %s\n' "$1"; }
here() { CHECKED=$((CHECKED + 1)); }
skip() { UNPROVEN=$((UNPROVEN + 1)); printf '  unproven  %s\n' "$1"; }
want() { [[ $WHAT == all || " $2 " == *" $WHAT "* || $WHAT == "$1" ]]; }   # want <leg> "<groups that include it>"
# names known to be absent from the release a leg checks; setup.sh skips them there, so they are not failures
declare -A EXPECTED=([ubuntu]="fastfetch" [slackware]="jq intel-microcode" [void-musl]="nvidia nvidia-libs-32bit")
SENTINEL=carino-setup-sentinel-not-a-package   # every container query must report this one missing, or it proved nothing
CRT=''; have() { command -v "$1" >/dev/null 2>&1; }
have podman && CRT=podman; [[ -z $CRT ]] && have docker && CRT=docker

# shellcheck source=/dev/null  # section 4 of setup.sh is plain data: arrays only
source <(awk '/^# ==== 4\./,/^# ==== 5\./' setup.sh)
FAMILIES="fedora atomic rhel debian ubuntu arch opensuse solus alpine void gentoo slackware mageia"
RX="^([a-z0-9_]+)_(${FAMILIES// /|})$"
arrays() { compgen -A arrayvar | grep -E "$RX"; }
names() { # names <family> [fallback family]: every checkable name the family installs (URLs, @groups, atoms dropped)
    local a g; local -A seen=()
    for a in $(arrays | grep -E "_($1${2:+|$2})$"); do
        g=${a%_*}
        [[ $a == *_"${2:-none}" ]] && declare -p "${g}_$1" >/dev/null 2>&1 && continue   # the family's own list wins
        [[ $a == *_"${2:-none}" && $g == drivers_nvidia?* ]] && continue   # the fallback family's legacy NVIDIA lists are not used
        local -n l=$a; for n in "${l[@]}"; do seen[$n]=1; done; unset -n l
    done
    printf '%s\n' "${!seen[@]}" | grep -vE '/|^@|^-' | sort
}
inContainer() { # inContainer <image> <script> <names...>: prints the names the image cannot find
    local img=$1 script=$2; shift 2
    $CRT pull -q "$img" >/dev/null 2>&1 || return 1
    $CRT run --rm "$img" sh -c "$script" _ "$@" 2>/dev/null
}
leg() { # leg <label> <image> <script> <family> [fallback]
    local label=$1 img=$2 script=$3 miss p; local -a all
    mapfile -t all < <(names "$4" "${5:-}")
    printf '\n%s (%s): %d names\n' "$label" "$img" "${#all[@]}"
    if [[ -z $CRT ]]; then skip "$label: no podman or docker"; return 0; fi
    miss=$(inContainer "$img" "$script" "${all[@]}" "$SENTINEL") || { skip "$label: $img could not be pulled or run"; return 0; }
    grep -qxF "$SENTINEL" <<<"$miss" || { skip "$label: the query did not report $SENTINEL missing, so it proved nothing"; return 0; }
    for p in "${all[@]}"; do
        if ! grep -qxF -- "$p" <<<"$miss"; then here
        elif [[ " ${EXPECTED[$label]:-} " == *" $p "* ]]; then printf '  expected  %s  %s (absent in this release)\n' "$label" "$p"; here
        else gone "$label  $p"; fi
    done
}

DNF_FEDORA='dnf -y -q install dnf5-plugins "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" >/dev/null 2>&1
dnf -y -q copr enable lionheartp/Hyprland >/dev/null 2>&1; dnf -y -q config-manager setopt fedora-cisco-openh264.enabled=1 >/dev/null 2>&1
dnf install --assumeno "$@" 2>&1 | sed -n "s/^No match for argument: //p"'
DNF_EL='dnf -y -q install epel-release dnf-plugins-core almalinux-release-nvidia-driver >/dev/null 2>&1; dnf -q config-manager --set-enabled crb >/dev/null 2>&1
dnf -y -q install "https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm" >/dev/null 2>&1
dnf install --assumeno "$@" 2>&1 | sed -n "s/^No match for argument: //p"'
APT_AVAIL='for p; do apt-cache show "$p" >/dev/null 2>&1 || apt-cache showpkg "$p" 2>/dev/null | awk "/^Reverse Provides:/{f=1;next} f&&NF{x=1} END{exit !x}" || echo "$p"; done'
APT_DEBIAN='sed -i "s/^Components: main.*/Components: main contrib non-free non-free-firmware/" /etc/apt/sources.list.d/debian.sources
printf "Types: deb\nURIs: http://deb.debian.org/debian\nSuites: trixie-backports\nComponents: main contrib non-free non-free-firmware\nSigned-By: /usr/share/keyrings/debian-archive-keyring.pgp\n" > /etc/apt/sources.list.d/backports.sources
apt-get update -qq >/dev/null 2>&1; '$APT_AVAIL
APT_UBUNTU='sed -i "s/^Components: .*/Components: main restricted universe multiverse/" /etc/apt/sources.list.d/ubuntu.sources
echo "deb [trusted=yes] http://ppa.launchpadcontent.net/cppiber/hyprland/ubuntu noble main" > /etc/apt/sources.list.d/hyprland-ppa.list
apt-get update -qq >/dev/null 2>&1; '$APT_AVAIL
ZYPPER='zypper -n -q install openSUSE-repos-Tumbleweed-NVIDIA >/dev/null 2>&1
zypper -n -q ar -cfp 90 https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/ packman >/dev/null 2>&1
zypper -n -q --gpg-auto-import-keys refresh >/dev/null 2>&1
for p; do zypper -n -q --no-refresh search -x --provides "$p" >/dev/null 2>&1 || echo "$p"; done'
APK='apk update -q >/dev/null 2>&1; for p; do apk search -e "$p" 2>/dev/null | grep -q . || echo "$p"; done'
XBPS='xbps-install -Syu xbps >/dev/null 2>&1; xbps-install -Sy void-repo-nonfree >/dev/null 2>&1
case $(xbps-uhelper arch) in x86_64) xbps-install -Sy void-repo-multilib void-repo-multilib-nonfree >/dev/null 2>&1 ;; esac
xbps-install -S >/dev/null 2>&1; for p; do xbps-query -R "$p" >/dev/null 2>&1 || echo "$p"; done'

if want coverage "cheap"; then
    printf '\nCoverage: every array in section 4 names a known family\n'
    for a in $(compgen -A arrayvar | grep -E '_[a-z]+$'); do
        [[ $a =~ $RX || $a == flatpak_* || $a == FALLBACK || $a == DONE_* ]] && { here; continue; }
        grep -qE "^$a=\(" setup.sh && gone "coverage  $a is not <group>_<family> or flatpak_<group>"
    done
    for f in atomic solus gentoo mageia; do
        n=$(names "$f" | grep -c .)
        (( n )) && skip "$f: $n names have no automated leg here (no official container or index to ask)"
    done
fi

if want flathub "cheap"; then
    printf '\nFlathub application ids\n'
    for id in $(for a in $(compgen -A arrayvar | grep '^flatpak_'); do declare -n l=$a; printf '%s\n' "${l[@]}"; unset -n l; done | sort -u); do
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://flathub.org/api/v2/appstream/$id")
        if [[ $code == 200 ]]; then here; else gone "flathub  $id (HTTP $code)"; fi
    done
fi

if want arch "cheap"; then
    printf '\nArch official repositories (archlinux.org)\n'
    for p in $(names arch); do
        n=$(curl -s --max-time 20 "https://archlinux.org/packages/search/json/?name=$p" | python3 -c 'import sys,json
try: print(len(json.load(sys.stdin)["results"]))
except Exception: print(-1)')
        if (( n > 0 )); then here
        elif (( n < 0 )); then skip "arch  $p (lookup failed)"
        elif [[ $(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://archlinux.org/groups/x86_64/$p/") == 200 ]]; then here   # groups (xfce4, plasma-meta's members)
        else gone "arch  $p"; fi
    done
fi

if want slackware "cheap"; then
    rel=${SLACKWARE_RELEASE:-15.0}
    printf '\nSlackware %s (PACKAGES.TXT from mirrors.slackware.com)\n' "$rel"
    idx=$(curl -sL --max-time 120 "https://mirrors.slackware.com/slackware/slackware64-$rel/PACKAGES.TXT" |
        sed -n 's/^PACKAGE NAME: *//p' | sed -E 's/-[^-]+-[^-]+-[^-]+\.t[gx]z$//' | sort -u)
    if (( $(grep -c . <<<"$idx") < 1000 )); then skip "slackware: the package index could not be read"
    else
        for p in $(names slackware); do
            if grep -qxF -- "$p" <<<"$idx"; then here
            elif [[ " ${EXPECTED[slackware]} " == *" $p "* ]]; then printf '  expected  slackware  %s (absent in %s)\n' "$p" "$rel"; here
            else gone "slackware  $p"; fi
        done
    fi
fi

want fedora   "containers" && leg fedora   "docker.io/library/fedora:${FEDORA_RELEASE:-44}"      "$DNF_FEDORA" fedora
want debian   "containers" && leg debian   "docker.io/library/debian:${DEBIAN_SUITE:-trixie}"    "$APT_DEBIAN" debian
want ubuntu   "containers" && leg ubuntu   "docker.io/library/ubuntu:${UBUNTU_SUITE:-24.04}"     "$APT_UBUNTU" ubuntu debian
want opensuse "containers" && leg opensuse "docker.io/opensuse/${OPENSUSE_RELEASE:-tumbleweed}"  "$ZYPPER" opensuse
want el       "containers" && leg el       "${EL_IMAGE:-docker.io/library/almalinux:10}"         "$DNF_EL" rhel
want alpine   "containers" && leg alpine   "docker.io/library/alpine:${ALPINE_RELEASE:-latest}"  "$APK" alpine
want void     "containers" && leg void     "ghcr.io/void-linux/void-glibc-full:latest"           "$XBPS" void
want void-musl "containers" && leg void-musl "ghcr.io/void-linux/void-musl-full:latest"          "$XBPS" void

printf '\n%d names resolve, %d missing, %d unproven\n' "$CHECKED" "$MISSING" "$UNPROVEN"
(( MISSING == 0 ))
