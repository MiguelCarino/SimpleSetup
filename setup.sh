#!/usr/bin/env bash
# shellcheck disable=SC2034  # the package arrays in section 4 are read by name ("${!ref}"), which shellcheck cannot follow
# ==== 0. Header ====
# Carino SimpleSetup: checks a Linux system, installs the base packages, codecs, firmware and drivers,
# offers a desktop and purpose profiles, and can install the Carino Hyprland desktop configuration.
#
# Usage:
#   bash <(curl -s https://setup.carino.systems/setup.sh)           interactive
#   bash setup.sh dry-run [argument]                                 print every command, change nothing
#   bash setup.sh <argument>       quick simple server drivers nvidia amd intel desktop hyprland
#                                  distrobox anydesk librewolf share proton update
#   CARINO_SETUP_PLAN=technical,desktop=kde,purpose=gaming,reboot=no bash setup.sh      unattended
# Environment: CARINO_SETUP_DRYRUN=1, CARINO_SETUP_PLAN, CARINO_SETUP_LOG=<file>, CARINO_SETUP_OSRELEASE=<file>.
# Test hooks: CARINO_SETUP_ATOMIC=0|1, CARINO_SETUP_GPU="nvidia amd intel", CARINO_SETUP_NVGEN=open|580|470,
#             CARINO_SETUP_VIRT=none|kvm|vmware|..., CARINO_SETUP_NET=0 (skip the internet check),
#             CARINO_SETUP_UNAME=Linux|Darwin|FreeBSD|... (pretend to be another kernel).
# Licence: AGPL-3.0-or-later, see LICENSE. Source: https://github.com/MiguelCarino/SimpleSetup

# ==== 1. Settings & args ====
set -uo pipefail
UNAME=${CARINO_SETUP_UNAME:-$(uname -s)}
if [[ $UNAME != Linux ]]; then   # checked before anything that needs bash 4 (macOS ships bash 3.2)
    case $UNAME in
        Darwin) echo "setup.sh is for Linux. On macOS run macos.sh instead: bash <(curl -s https://setup.carino.systems/macos.sh)" ;;
        *BSD|DragonFly) echo "setup.sh is for Linux only, and $UNAME is not supported. Install software with the system's own tool: pkg on FreeBSD and DragonFly, pkg_add on OpenBSD, pkgin on NetBSD." ;;
        *) echo "setup.sh is for Linux only, and this system reports '$UNAME'. Windows has setup.ps1 and macOS has macos.sh." ;;
    esac
    echo "Nothing was installed."; exit 1
fi
DRYRUN=0
if [[ ${1:-} == dry-run || ${1:-} == --dry-run ]]; then DRYRUN=1; shift; fi
[[ ${CARINO_SETUP_DRYRUN:-0} == 1 ]] && DRYRUN=1
ARG=${1:-}
NARGS=$#
PLAN=${CARINO_SETUP_PLAN:-}
OSRELEASE=${CARINO_SETUP_OSRELEASE:-/etc/os-release}
NONINTERACTIVE=0
[[ -n $PLAN || ! -t 0 ]] && NONINTERACTIVE=1
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
BUNDLE_URL=https://codeload.github.com/MiguelCarino/SimpleSetup/tar.gz/refs/heads/main
LOG=''
OS_ID='' OS_LIKE='' OS_NAME='' OS_VER='' OS_CODE='' UBU_CODE='' DEB_CODE=''
FAMILY='' PM='' ATOMIC=0 CPU=other GPUS='' NVGEN=open VIRT=none LAPTOP=no SECUREBOOT=unknown
HAS_DESKTOP=no TARGET_USER='' TARGET_HOME='' HYPR_HOW='' HYPR_WHY='' HYPR_SRC='' REBOOT='' NEED_REBOOT=0
REFRESHED=0 FLATHUB_READY=0 PKG_NOTE='' SLACK_READY='' SLACK_KERNEL=0
SUDO=() PM_INSTALL=() PM_UPGRADE=() PM_REFRESH=() PM_TARGET=() RESULTS=()
declare -A DONE_GROUP=() DONE_FLATPAK=()
declare -A FALLBACK=([ubuntu]=debian [rhel]=fedora)   # where a family has no list of its own (EL: not for desktops)

# ==== 2. Helpers ====
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    C_B=$'\e[1;94m' C_G=$'\e[32m' C_Y=$'\e[33m' C_R=$'\e[31m' C_D=$'\e[2m' C_0=$'\e[0m'
else
    C_B='' C_G='' C_Y='' C_R='' C_D='' C_0=''
fi
say()    { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
ok()     { printf '%s ok%s %s\n' "$C_G" "$C_0" "$*"; }
warn()   { printf '%s !!%s %s\n' "$C_Y" "$C_0" "$*"; }
fail()   { printf '%s xx%s %s\n' "$C_R" "$C_0" "$*"; }
die()    { fail "$*"; exit 1; }
banner() { printf '\n%s==== %s ====%s\n' "$C_B" "$*" "$C_0"; }
record() { RESULTS+=("$1|$2"); }   # record ok|fail|skip "what"
have()   { command -v "$1" >/dev/null 2>&1; }
verGe()  { [[ $(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1) == "$2" ]]; }   # verGe 0.56.2 0.55

run() { # run <command...>: prints the command, runs it unless this is a dry run
    local tag='$' line='' a
    (( DRYRUN )) && tag='(dry-run) $'
    for a in "$@"; do   # plain words as they are, anything else shell-quoted
        if [[ $a =~ ^[A-Za-z0-9_@%+=:,./~-]+$ ]]; then line+="$a "
        elif [[ $a != *"'"* ]]; then line+="'$a' "
        else line+="$(printf '%q' "$a") "; fi
    done
    printf '%s   %s %s%s\n' "$C_D" "$tag" "${line% }" "$C_0"
    (( DRYRUN )) && return 0
    "$@"
}
root() { run "${SUDO[@]}" "$@"; }
asUser() { # runs a command as the real user when the script itself runs as root
    if (( EUID == 0 )) && [[ $TARGET_USER != root ]] && have runuser; then run runuser -u "$TARGET_USER" -- "$@"
    else run "$@"; fi
}
writeRootFile() { # writeRootFile <path> <content>
    printf '%s   %s write %s:%s\n%s\n' "$C_D" "$( (( DRYRUN )) && echo '(dry-run)')" "$1" "$C_0" "$2"
    (( DRYRUN )) && return 0
    printf '%s\n' "$2" | "${SUDO[@]}" tee "$1" >/dev/null
}

ask() { # ask "question" default -> REPLY; takes the default under a plan or without a terminal
    if (( NONINTERACTIVE )); then REPLY=$2; say "$1 -> ${2:-<empty>} (default, non-interactive)"; return 0; fi
    read -r -p "$1 [$2] " REPLY || REPLY=$2
    [[ -n $REPLY ]] || REPLY=$2
}
confirm() { ask "$1 (y/n)" "$2"; [[ $REPLY =~ ^[Yy] ]]; }

setPackageManager() { # the pacman refresh is a full upgrade on purpose: -Sy then -S is an unsupported partial upgrade
    case $FAMILY in
        fedora)  PM=dnf; PM_INSTALL=(dnf -y install --skip-unavailable); PM_UPGRADE=(dnf -y upgrade --refresh); PM_REFRESH=(dnf -y makecache) ;;
        atomic)  PM=rpm-ostree; PM_INSTALL=(rpm-ostree install --idempotent --allow-inactive); PM_UPGRADE=(rpm-ostree upgrade); PM_REFRESH=(rpm-ostree refresh-md) ;;
        rhel|mageia) PM=dnf; PM_INSTALL=(dnf -y install --setopt=strict=0); PM_UPGRADE=(dnf -y upgrade --refresh); PM_REFRESH=(dnf -y makecache) ;;
        debian|ubuntu) PM=apt-get; PM_INSTALL=(env DEBIAN_FRONTEND=noninteractive apt-get -y install)
                 PM_UPGRADE=(env DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade); PM_REFRESH=(apt-get update) ;;
        arch)    PM=pacman; PM_INSTALL=(pacman -S --needed --noconfirm); PM_UPGRADE=(pacman -Syu --noconfirm); PM_REFRESH=(pacman -Syu --noconfirm) ;;
        opensuse) PM=zypper; PM_INSTALL=(zypper -n install --auto-agree-with-licenses); PM_UPGRADE=(zypper -n update); PM_REFRESH=(zypper -n refresh) ;;
        solus)   PM=eopkg; PM_INSTALL=(eopkg -y it); PM_UPGRADE=(eopkg -y up); PM_REFRESH=(eopkg -y ur) ;;
        alpine)  PM=apk; PM_INSTALL=(apk add); PM_UPGRADE=(apk upgrade); PM_REFRESH=(apk update) ;;
        void)    PM=xbps-install; PM_INSTALL=(xbps-install -y); PM_UPGRADE=(xbps-install -y -Su); PM_REFRESH=(xbps-install -S) ;;
        gentoo)  PM=emerge; PM_INSTALL=(emerge --noreplace --quiet-build); PM_UPGRADE=(emerge --update --deep --newuse @world); PM_REFRESH=(emerge --sync) ;;
        slackware) PM=slackpkg; PM_INSTALL=(slackpkg -batch=on -default_answer=y install)
                 PM_UPGRADE=(slackpkg -batch=on -default_answer=y upgrade-all); PM_REFRESH=(slackpkg -batch=on -default_answer=y update) ;;
    esac
    [[ $OS_ID == *tumbleweed* || $OS_ID == *slowroll* ]] && PM_UPGRADE=(zypper -n dup --auto-agree-with-licenses)
    [[ $OS_ID == openmandriva ]] && PM_UPGRADE=(dnf -y distro-sync)
    return 0
}
pkgAvail() { # pkgAvail <name>: true when the package manager can find it (for managers that abort on one unknown name)
    case $PM in
        apt-get) apt-cache show "$1" >/dev/null 2>&1 || apt-cache showpkg "$1" 2>/dev/null | awk '/^Reverse Provides:/{f=1;next} f&&NF{x=1} END{exit !x}' ;;
        pacman)  pacman -Si "$1" >/dev/null 2>&1 || pacman -Sg "$1" >/dev/null 2>&1 ;;
        zypper)  zypper -n -q --no-refresh search -x --provides "$1" >/dev/null 2>&1 ;;
        apk)     apk search -e "$1" 2>/dev/null | grep -q . ;;
        xbps-install) xbps-query -R "$1" >/dev/null 2>&1 ;;
        slackpkg) awk -v p="$1" '$2 == p {f=1} END {exit !f}' /var/lib/slackpkg/pkglist 2>/dev/null ;;
        *)       return 0 ;;
    esac
}
pmOk() { (( $1 == 0 )) || [[ $PM == slackpkg && $1 == 20 ]]; }   # slackpkg exits 20 when there is nothing to do
slackpkgReady() { # slackpkg exits 0 when it did nothing (no mirror, -current not confirmed), so check first
    [[ -n $SLACK_READY ]] && return "$SLACK_READY"
    SLACK_READY=1
    (( DRYRUN )) && { SLACK_READY=0; return 0; }
    local m; m=$(grep -m1 -E '^[[:space:]]*(https?|ftp|file|cdrom)://' /etc/slackpkg/mirrors 2>/dev/null)
    if [[ -z $m ]]; then
        warn "No slackpkg mirror is selected: uncomment one line in /etc/slackpkg/mirrors, then run this again."
        record fail "slackpkg mirror"; return 1
    fi
    if [[ $m == *-current/* && ! -e /var/lib/slackpkg/current ]]; then   # else slackpkg asks with a raw read
        if ! confirm "The slackpkg mirror is Slackware -current, the development tree. Use it?" n || ! root touch /var/lib/slackpkg/current; then
            record fail "slackpkg mirror (-current not confirmed)"; return 1
        fi
    fi
    SLACK_READY=0
}
slackKernels() { printf '%s\n' /var/log/packages/kernel-*; }
pkgRefresh() {
    local before=''
    REFRESHED=1
    if [[ $PM == slackpkg ]]; then slackpkgReady || return 1; before=$(stat -c %Y /var/lib/slackpkg/pkglist 2>/dev/null); fi
    root "${PM_REFRESH[@]}" || { warn "Refreshing the package index failed."; return 1; }
    if [[ $PM == slackpkg ]] && (( ! DRYRUN )) && [[ $(stat -c %Y /var/lib/slackpkg/pkglist 2>/dev/null) == "$before" ]]; then
        warn "slackpkg update did not write a new package list, so it did not run."; return 1
    fi
}
pkgUpgrade() {
    local rc kernels=''
    [[ $FAMILY == void ]] && root xbps-install -y -Su xbps   # xbps must update itself before the rest
    if [[ $PM == slackpkg ]]; then   # install-new first: -current adds packages that upgraded ones need
        slackpkgReady || return 1
        kernels=$(slackKernels)
        root slackpkg -batch=on -default_answer=y install-new; pmOk $? || return 1
    fi
    root "${PM_UPGRADE[@]}"; rc=$?
    if [[ $PM == slackpkg && $rc == 50 ]]; then   # 50: slackpkg upgraded itself and must run again
        say "slackpkg upgraded itself, running the upgrade again."; pkgRefresh; root "${PM_UPGRADE[@]}"; rc=$?
    fi
    if [[ $PM == slackpkg ]] && (( ! DRYRUN )) && [[ $(slackKernels) != "$kernels" ]]; then
        warn "The kernel was upgraded: run mkinitrd (if you use an initrd) and lilo, eliloconfig or grub-mkconfig before rebooting."
        SLACK_KERNEL=1
    fi
    pmOk "$rc"
}
dnfCheck() { # dnfCheck <names...>: dnf can exit 0 after skipping every name, so ask rpm what is really installed
    local p n=0 m=0; local -a miss=()
    (( DRYRUN )) && return 0
    for p in "$@"; do
        [[ $p == @* || $p == */* ]] && continue   # groups and URLs: dnf's own result is trusted
        m=$((m + 1))
        if rpm -q --whatprovides "$p" >/dev/null 2>&1; then n=$((n + 1)); else miss+=("$p"); fi
    done
    (( n == m )) && return 0
    (( n )) || { warn "dnf reported success, but none of the $m packages is installed."; return 3; }
    warn "Installed $n of $m; not available: ${miss[*]}"; PKG_NOTE=" ($n of $m)"
}
pkgInstall() { # pkgInstall <names...>: installs what this system can find, lists and skips the rest
    local p rc bad=0; local -a want=() gone=()
    PKG_NOTE=''
    (( $# )) || return 0
    (( REFRESHED )) || pkgRefresh
    for p in "$@"; do
        if (( DRYRUN )) || [[ $p == */* ]] || pkgAvail "$p"; then want+=("$p"); else gone+=("$p"); fi
    done
    (( ${#gone[@]} )) && warn "Not available here, skipped: ${gone[*]}"
    (( ${#want[@]} )) || return 3   # 3 = none of the names exists here
    root "${PM_INSTALL[@]}" "${PM_TARGET[@]}" "${want[@]}"; rc=$?
    if pmOk "$rc"; then [[ $PM == dnf ]] && { dnfCheck "${want[@]}"; return; }; return 0; fi
    [[ $PM == dnf ]] && return 1   # dnf already skipped the unknown names, a failure here is real
    warn "The batch install failed, retrying one package at a time."
    for p in "${want[@]}"; do root "${PM_INSTALL[@]}" "${PM_TARGET[@]}" "$p"; pmOk $? || bad=1; done
    return "$bad"
}
arrayFor() { # arrayFor <group>: prints <group>_<family> (or the fallback family's) when it exists
    local f fb=${FALLBACK[$FAMILY]:-}
    [[ $FAMILY == rhel && $1 == desktop* ]] && fb=''   # EL has only its own desktops, never Fedora's
    for f in "$FAMILY" $fb; do
        declare -p "${1}_$f" >/dev/null 2>&1 && { printf '%s\n' "${1}_$f"; return 0; }
    done
    return 1
}
installGroup() { # installGroup <group> [label]: installs the package array for this family, once per run
    local g=$1 label=${2:-$1} name ref rc
    [[ -n ${DONE_GROUP[$g]:-} ]] && return 0
    DONE_GROUP[$g]=1
    name=$(arrayFor "$g") || { say "No $label list for $FAMILY, nothing to install."; return 2; }
    ref="${name}[@]"; local -a list=("${!ref}")
    say "Installing $label (${#list[@]} packages, $name)"
    pkgInstall "${list[@]}"; rc=$?
    case $rc in
        0) record ok "$label$PKG_NOTE" ;;
        3) record skip "$label (none available)"; return 3 ;;
        *) record fail "$label"; return 1 ;;
    esac
}
flatpakSetup() {
    (( FLATHUB_READY )) && return 0
    if [[ $FAMILY == slackware ]] && ! have flatpak; then warn "Slackware: build desktop/flatpak from SlackBuilds.org first."; return 1; fi
    have flatpak || pkgInstall flatpak
    root flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo && FLATHUB_READY=1
}
flatpakInstall() { # flatpakInstall <Flathub ids...>, each id once per run
    local id bad=0; local -a ids=()
    for id in "$@"; do [[ -n ${DONE_FLATPAK[$id]:-} ]] || { ids+=("$id"); DONE_FLATPAK[$id]=1; }; done
    (( ${#ids[@]} )) || return 0
    flatpakSetup || return 1
    root flatpak install -y --noninteractive flathub "${ids[@]}" && return 0
    warn "The Flatpak batch failed, retrying one at a time."
    for id in "${ids[@]}"; do root flatpak install -y --noninteractive flathub "$id" || bad=1; done
    return "$bad"
}
enableService() { # enableService <unit>: systemd, OpenRC or runit
    if have systemctl; then root systemctl enable --now "$1"
    elif have rc-update; then root rc-update add "${1%.*}" default
    elif [[ -d /etc/sv/${1%.*} ]]; then root ln -sf "/etc/sv/${1%.*}" /var/service/
    elif [[ -e /etc/rc.d/rc.${1%.*} ]]; then root chmod +x "/etc/rc.d/rc.${1%.*}"   # Slackware: starts at the next boot
    else warn "No service manager found to enable $1."; fi
}

# ==== 3. checkSystem ====
NIXOS_SNIPPET='  # /etc/nixos/configuration.nix, then: sudo nixos-rebuild switch
  programs.hyprland.enable = true;
  hardware.graphics.enable = true;
  services.flatpak.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];   # NVIDIA only
  hardware.nvidia.open = true;                     # Turing (RTX 20 / GTX 16) or newer'
GUIX_SNIPPET='  ;; /etc/config.scm, then: sudo guix system reconfigure /etc/config.scm
  ;; Merge into the existing packages and services fields (add to their lists), never add a second field.
  (use-service-modules desktop)                     ; at the top, next to use-modules
  (packages (append (list (specification->package "flatpak")
                          (specification->package "hyprland"))
                    %base-packages))
  (services (append (list (service gnome-desktop-service-type))
                    %desktop-services))
  ;; Non-free firmware and NVIDIA: add the nonguix channel, https://gitlab.com/nonguix/nonguix'
SLACKWARE_VERSION=/etc/slackware-version

readOsRelease() {
    local k v name=''
    if [[ -r $OSRELEASE ]]; then
        while IFS='=' read -r k v; do
            v=${v%\"}; v=${v#\"}; v=${v%\'}; v=${v#\'}
            case $k in
                ID) OS_ID=$v ;; ID_LIKE) OS_LIKE=$v ;; NAME) name=$v ;; PRETTY_NAME) OS_NAME=$v ;; VERSION_ID) OS_VER=$v ;;
                VERSION_CODENAME) OS_CODE=$v ;; UBUNTU_CODENAME) UBU_CODE=$v ;; DEBIAN_CODENAME) DEB_CODE=$v ;;
            esac
        done < "$OSRELEASE"
    elif [[ ! -r $SLACKWARE_VERSION ]]; then
        die "Cannot read $OSRELEASE, so the distribution is unknown. Nothing was installed."
    fi
    if [[ -z $OS_ID && -r $SLACKWARE_VERSION ]]; then   # old Slackware releases have no os-release
        OS_ID=slackware; name=$(<"$SLACKWARE_VERSION"); OS_VER=${name##* }
    fi
    OS_NAME=${OS_NAME:-${name:-$OS_ID}}
}
familyOf() { # familyOf <os-release id>
    case $1 in
        nixos) echo nixos ;; guix) echo guix ;;
        steamos|holo) echo steamos ;;
        fedora|nobara|ultramarine|bazzite|bluefin|aurora|risi) echo fedora ;;
        rhel|centos|almalinux|rocky|ol|amzn|eurolinux|circle|cloudlinux|navy) echo rhel ;;
        ubuntu|linuxmint|pop|elementary|zorin|neon|tuxedo) echo ubuntu ;;
        debian|kali|parrot|mx|raspbian|devuan|pureos|deepin) echo debian ;;
        arch|archarm|manjaro|manjaro-arm|endeavouros|cachyos|garuda|arcolinux|rebornos|archcraft) echo arch ;;
        opensuse*|suse|sles|sled) echo opensuse ;;
        solus) echo solus ;; alpine|postmarketos) echo alpine ;; void) echo void ;; gentoo|funtoo) echo gentoo ;;
        slackware) echo slackware ;;
        mageia|openmandriva|mandriva) echo mageia ;;
        *) return 1 ;;
    esac
}
detectFamily() { # ID first, then each ID_LIKE entry; SteamOS and NixOS have their own ID so they win over arch
    local x
    FAMILY=$(familyOf "$OS_ID") || for x in $OS_LIKE; do FAMILY=$(familyOf "$x") && break; done
    [[ $FAMILY == ubuntu && $OS_ID == linuxmint && -z $UBU_CODE ]] && FAMILY=debian   # LMDE
    [[ -e /run/ostree-booted ]] && ATOMIC=1
    ATOMIC=${CARINO_SETUP_ATOMIC:-$ATOMIC}
    [[ $FAMILY == fedora && $ATOMIC == 1 ]] && FAMILY=atomic
    return 0
}
refuse() { fail "$1"; [[ -n ${2:-} ]] && printf '%s\n' "$2"; fail "This system was refused and nothing was installed."; exit 1; }

nvGeneration() { # reads the NVIDIA codename lspci prints (AD102, GP104, ...)
    case $1 in
        *' TU1'*|*' GA1'*|*' AD1'*|*' GB1'*|*' GB2'*|*' GH1'*) NVGEN=open ;;
        *' GP1'*|*' GM1'*|*' GM2'*|*' GV1'*) NVGEN=580 ;;
        *' GK1'*|*' GK2'*) NVGEN=470 ;;
        *) NVGEN=unknown ;;   # no codename in the lspci line: nvidiaSetup asks
    esac
}
detectGpu() {
    local line d v; local -A g=()
    if have lspci; then   # display classes only (VGA 0300, 3D 0302, other 0380), never the chipset lines
        while IFS= read -r line; do
            case $line in *'[10de:'*) g[nvidia]=1; nvGeneration "$line" ;; *'[1002:'*) g[amd]=1 ;; *'[8086:'*) g[intel]=1 ;; esac
        done < <(lspci -nn 2>/dev/null | grep -E '\[03(00|02|80)\]')
    fi
    if (( ${#g[@]} == 0 )); then
        for d in /sys/class/drm/card[0-9]*/device/vendor; do
            [[ -r $d ]] || continue
            case $(<"$d") in 0x10de) g[nvidia]=1; NVGEN=unknown ;; 0x1002) g[amd]=1 ;; 0x8086) g[intel]=1 ;; esac
        done
    fi
    for v in nvidia amd intel; do [[ -n ${g[$v]:-} ]] && GPUS+="$v "; done
    GPUS=${CARINO_SETUP_GPU:-${GPUS% }}
    NVGEN=${CARINO_SETUP_NVGEN:-$NVGEN}
}
detectHardware() {
    if grep -q GenuineIntel /proc/cpuinfo 2>/dev/null; then CPU=intel; elif grep -q AuthenticAMD /proc/cpuinfo 2>/dev/null; then CPU=amd; fi
    detectGpu
    compgen -G '/sys/class/power_supply/BAT*' >/dev/null && LAPTOP=yes
    if have systemd-detect-virt; then VIRT=$(systemd-detect-virt --vm 2>/dev/null); VIRT=${VIRT:-none}
    elif grep -qw hypervisor /proc/cpuinfo 2>/dev/null; then VIRT=vm; fi
    VIRT=${CARINO_SETUP_VIRT:-$VIRT}
    if have mokutil; then
        if mokutil --sb-state 2>/dev/null | grep -qi enabled; then SECUREBOOT=on; else SECUREBOOT=off; fi
    fi
    [[ -n ${XDG_CURRENT_DESKTOP:-} || -e /etc/systemd/system/display-manager.service ]] && HAS_DESKTOP=yes
    return 0
}
setPrivilege() {
    if (( EUID == 0 )); then SUDO=()
    elif have sudo; then SUDO=(sudo)
    elif have doas; then SUDO=(doas)
    elif have run0; then SUDO=(run0)
    elif (( DRYRUN )); then SUDO=(sudo); warn "No sudo, doas or run0 found; the dry run prints sudo anyway."
    else refuse "Not running as root and no sudo, doas or run0 was found."; fi
    TARGET_USER=${SUDO_USER:-${DOAS_USER:-$(id -un)}}
    TARGET_HOME=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
    TARGET_HOME=${TARGET_HOME:-$HOME}
}
printFacts() {
    local net='not checked' disk='' model _ free
    model=$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2); model=${model# }
    { read -r _; read -r _ _ _ free _; } < <(df -Pk / 2>/dev/null) && [[ $free =~ ^[0-9]+$ ]] && disk="$((free / 1048576)) GiB free"
    have curl || net='unknown (no curl)'
    if [[ ${CARINO_SETUP_NET:-1} != 0 ]] && have curl; then
        if curl -sI --max-time 6 https://flathub.org >/dev/null 2>&1; then net=yes; else net=no; fi
    fi
    banner "System"
    printf '  %-17s %s\n' "Distribution" "$OS_NAME (ID=$OS_ID${OS_VER:+, version $OS_VER})" \
        "Family" "$FAMILY" "Package manager" "${PM_INSTALL[*]}" "Kernel" "$(uname -r)" "Architecture" "$(uname -m)" \
        "CPU" "$CPU${model:+ ($model)}" \
        "GPU" "${GPUS:-none found}$([[ $GPUS == *nvidia* ]] && echo " (NVIDIA branch: $NVGEN)")" \
        "Laptop" "$LAPTOP" "Virtual machine" "$VIRT" "Secure Boot" "$SECUREBOOT" "Atomic" "$ATOMIC" \
        "Desktop session" "$HAS_DESKTOP${XDG_CURRENT_DESKTOP:+ ($XDG_CURRENT_DESKTOP)}" "Disk /" "${disk:-unknown}" \
        "Internet" "$net" "Run as" "$(id -un) -> files for $TARGET_USER ($TARGET_HOME)"
}
checkSystem() {
    readOsRelease
    detectFamily
    case $FAMILY in
        nixos)   refuse "NixOS is configured declaratively, so this script does not install anything on it. Add this instead:" "$NIXOS_SNIPPET" ;;
        guix)    refuse "Guix System is configured declaratively, so this script does not install anything on it. Add this instead:" "$GUIX_SNIPPET" ;;
        steamos) refuse "SteamOS is an immutable image: system packages are reset on update. Use Flatpaks from Discover (desktop mode)." ;;
        '')      refuse "Unknown distribution: ID=${OS_ID:-none}, ID_LIKE=${OS_LIKE:-none}, name '${OS_NAME:-none}'${OS_VER:+, version $OS_VER}." \
                     "Supported: Fedora (and Atomic), RHEL/Alma/Rocky, Debian, Ubuntu, Arch, openSUSE, Solus, Alpine, Void, Gentoo, Slackware, Mageia.
If this distribution is based on one of them, report it with the line above: https://github.com/MiguelCarino/SimpleSetup/issues" ;;
    esac
    [[ $FAMILY == opensuse && $OS_ID =~ micro|aeon|kalpa ]] && refuse "$OS_ID is a transactional openSUSE: use transactional-update and Flatpaks there."
    setPrivilege
    setPackageManager
    (( DRYRUN )) || have "$PM" || refuse "The package manager '$PM' expected for $FAMILY is not installed."
    detectHardware
    printFacts
    case $OS_ID in kali|parrot) warn "$OS_ID is a security distribution: it is treated as Debian, but its own tools may conflict." ;; esac
    [[ $FAMILY == atomic ]] && warn "Atomic system: packages are layered with rpm-ostree and apply after a reboot."
    [[ $FAMILY == gentoo ]] && warn "Gentoo: only the base packages are emerged; drivers and profiles depend on your USE flags (guidance is printed)."
    [[ $FAMILY == slackware ]] && warn "Slackware: base packages, codecs and firmware are installed with slackpkg; the rest comes from SlackBuilds.org (guidance is printed)."
    return 0
}

# ==== 4. Packages ====
# Arrays are named <group>_<family>. A missing array means nothing for that family; ubuntu falls back to
# debian and rhel to fedora, except for desktops (see FALLBACK). Flatpaks are flatpak_<group> (Flathub ids).

# -- base: installed by the technical setup on every system
base_fedora=( pciutils git cmake wget nano curl jq elinks nasm lshw lm_sensors rsync rclone mediainfo cifs-utils ntfs-3g lsof xinput procps-ng git-lfs gnupg2 openssh-clients blktrace iotop smartmontools NetworkManager NetworkManager-tui xkill tigervnc-server dhcp-server fastfetch flatpak fwupd unzip )
base_atomic=( fastfetch lm_sensors smartmontools iotop )
base_rhel=( pciutils git cmake wget nano curl jq elinks nasm lshw lm_sensors rsync rclone mediainfo cifs-utils ntfs-3g lsof procps-ng git-lfs gnupg2 openssh-clients blktrace iotop smartmontools NetworkManager NetworkManager-tui fastfetch flatpak fwupd unzip kea )
base_debian=( pciutils git cmake wget nano curl jq elinks nasm lshw lm-sensors rsync rclone mediainfo cifs-utils ntfs-3g lsof xinput procps git-lfs gnupg openssh-client blktrace iotop smartmontools network-manager build-essential manpages-dev net-tools x11-utils tigervnc-standalone-server tigervnc-common isc-dhcp-server fastfetch flatpak fwupd unzip )
base_ubuntu=( pciutils git cmake wget nano curl jq elinks nasm lshw lm-sensors rsync rclone mediainfo cifs-utils ntfs-3g lsof xinput procps git-lfs gnupg openssh-client blktrace iotop smartmontools network-manager build-essential manpages-dev net-tools x11-utils tigervnc-standalone-server tigervnc-common isc-dhcp-server fastfetch flatpak fwupd unzip software-properties-common )
base_arch=( pciutils git cmake wget nano curl jq elinks nasm lshw lm_sensors rsync rclone mediainfo cifs-utils ntfs-3g lsof xorg-xinput procps-ng git-lfs gnupg openssh iotop smartmontools networkmanager xorg-xkill tigervnc fastfetch flatpak fwupd unzip )
base_opensuse=( pciutils git cmake wget nano curl jq elinks nasm lshw sensors rsync rclone mediainfo cifs-utils ntfs-3g lsof xinput procps git-lfs gpg2 openssh-clients blktrace iotop smartmontools fastfetch flatpak fwupd unzip )
base_alpine=( bash pciutils git cmake wget nano curl jq nasm lshw lm-sensors rsync rclone mediainfo cifs-utils ntfs-3g lsof procps git-lfs gnupg openssh-client iotop smartmontools networkmanager fastfetch flatpak fwupd unzip )
base_void=( pciutils git cmake wget nano curl jq nasm lshw lm_sensors rsync rclone mediainfo cifs-utils ntfs-3g lsof procps-ng git-lfs gnupg openssh iotop smartmontools NetworkManager fastfetch flatpak fwupd unzip )
base_solus=( git curl wget nano jq rsync lsof flatpak )
# unverified on solus: pciutils lshw smartmontools fastfetch rclone
base_gentoo=( sys-apps/pciutils dev-vcs/git dev-build/cmake net-misc/wget app-editors/nano net-misc/curl app-misc/jq net-misc/rsync sys-process/lsof sys-apps/smartmontools sys-apps/flatpak )
base_mageia=( pciutils git cmake wget nano curl jq rsync lsof smartmontools lm_sensors flatpak )
# a full Slackware install already has most of these; jq is in -current only (15.0 skips it)
# slackpkg matches names as words: cmake also takes extra-cmake-modules, NetworkManager NetworkManager-openvpn
base_slackware=( pciutils usbutils git cmake wget nano curl jq nasm lm_sensors rsync cifs-utils ntfs-3g lsof procps-ng gnupg2 openssh smartmontools NetworkManager htop infozip dmidecode hdparm ethtool mc )

# -- codecs (Fedora also swaps ffmpeg-free and mesa-va-drivers, see codecsSetup)
codecs_fedora=( gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly gstreamer1-plugin-openh264 libavcodec-freeworld )
codecs_rhel=( ffmpeg gstreamer1-plugins-ugly )
codecs_debian=( ffmpeg libavcodec-extra gstreamer1.0-plugins-ugly gstreamer1.0-plugins-bad gstreamer1.0-libav )
codecs_arch=( ffmpeg gst-plugins-ugly gst-plugins-bad gst-libav )
codecs_opensuse=( ffmpeg gstreamer-plugins-ugly gstreamer-plugins-bad gstreamer-plugins-libav )
codecs_alpine=( ffmpeg gst-plugins-ugly gst-plugins-bad gst-libav )
codecs_void=( ffmpeg gst-plugins-ugly1 gst-plugins-bad1 gst-libav )
codecs_slackware=( ffmpeg gst-plugins-good gst-plugins-bad-free gst-plugins-libav )

# -- firmware and CPU microcode (microcode is skipped inside a VM)
firmware_fedora=( linux-firmware )
firmware_rhel=( linux-firmware )
firmware_debian=( firmware-linux firmware-misc-nonfree )
firmware_ubuntu=( linux-firmware )
firmware_arch=( linux-firmware )
firmware_opensuse=( kernel-firmware-all )
firmware_alpine=( linux-firmware )
firmware_void=( linux-firmware )
firmware_slackware=( kernel-firmware )
microcode_intel_fedora=( microcode_ctl )
microcode_amd_fedora=( amd-ucode-firmware )
microcode_intel_rhel=( microcode_ctl )
microcode_intel_debian=( intel-microcode )
microcode_amd_debian=( amd64-microcode )
microcode_intel_arch=( intel-ucode )
microcode_amd_arch=( amd-ucode )
microcode_intel_opensuse=( ucode-intel )
microcode_amd_opensuse=( ucode-amd )
microcode_intel_alpine=( intel-ucode )
microcode_amd_alpine=( amd-ucode )
microcode_intel_void=( intel-ucode )
microcode_amd_void=( linux-firmware-amd )
# Slackware: intel-microcode is in -current only; AMD microcode comes with firmware_slackware (kernel-firmware)
microcode_intel_slackware=( intel-microcode )

# -- graphics drivers. nvidia = Turing or newer (open module), nvidia580 = Maxwell/Pascal, nvidia470 = Kepler
drivers_nvidia_fedora=( akmod-nvidia xorg-x11-drv-nvidia-cuda libva-nvidia-driver libva-utils vdpauinfo vulkan-tools )
drivers_nvidia580_fedora=( akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx xorg-x11-drv-nvidia-580xx-cuda libva-nvidia-driver libva-utils vulkan-tools )
drivers_nvidia470_fedora=( akmod-nvidia-470xx xorg-x11-drv-nvidia-470xx xorg-x11-drv-nvidia-470xx-cuda )
drivers_nvidia_atomic=( akmod-nvidia xorg-x11-drv-nvidia )
drivers_nvidia_rhel=( nvidia-open-kmod nvidia-driver )
drivers_nvidia_debian=( nvidia-open-kernel-dkms nvidia-driver firmware-nvidia-gsp nvidia-settings nvidia-smi nvidia-vaapi-driver linux-headers-amd64 vainfo vdpau-driver-all va-driver-all vulkan-tools )
drivers_nvidia580_debian=( nvidia-kernel-dkms nvidia-driver nvidia-settings nvidia-smi nvidia-vaapi-driver linux-headers-amd64 vainfo vdpau-driver-all va-driver-all vulkan-tools )
drivers_nvidia_ubuntu=( ubuntu-drivers-common linux-headers-generic nvidia-vaapi-driver vainfo vdpau-driver-all va-driver-all vulkan-tools )
drivers_nvidia_arch=( nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland libva-nvidia-driver vulkan-icd-loader )
drivers_nvidia_opensuse=( nvidia-open-driver-G07-signed-kmp-default nvidia-video-G07 nvidia-gl-G07 nvidia-compute-G07 )
drivers_nvidia580_opensuse=( nvidia-driver-G06-kmp-default nvidia-video-G06 nvidia-gl-G06 nvidia-compute-G06 )
drivers_nvidia_solus=( nvidia-glx-driver-current )
drivers_nvidia_void=( nvidia nvidia-libs-32bit )
drivers_amd_fedora=( mesa-dri-drivers mesa-vulkan-drivers xorg-x11-drv-amdgpu ocl-icd-devel opencl-headers libdrm-devel systemd-devel rocm-opencl rocminfo rocm-smi )
drivers_amd_rhel=( mesa-dri-drivers mesa-vulkan-drivers ocl-icd-devel opencl-headers libdrm-devel )
drivers_amd_debian=( mesa-vulkan-drivers mesa-va-drivers firmware-amd-graphics xserver-xorg-video-amdgpu libsystemd-dev ocl-icd-opencl-dev opencl-headers libdrm-dev rocminfo )
drivers_amd_arch=( mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon xf86-video-amdgpu ocl-icd opencl-headers )
drivers_amd_opensuse=( Mesa-dri libdrm_amdgpu1 Mesa-libva libvulkan_radeon xf86-video-amdgpu ocl-icd-devel opencl-headers vulkan-tools libva-utils )
drivers_amd_alpine=( mesa-dri-gallium mesa-va-gallium mesa-vulkan-ati linux-firmware-amdgpu )
drivers_amd_void=( mesa-dri vulkan-loader mesa-vulkan-radeon mesa-vaapi )
drivers_intel_fedora=( intel-media-driver libva-intel-driver mesa-vulkan-drivers libva-utils )
drivers_intel_rhel=( mesa-dri-drivers mesa-vulkan-drivers )
drivers_intel_debian=( intel-media-va-driver-non-free i965-va-driver mesa-vulkan-drivers vainfo )
drivers_intel_arch=( mesa vulkan-intel intel-media-driver libva-intel-driver )
drivers_intel_opensuse=( Mesa-dri libvulkan_intel intel-media-driver libva-utils )
drivers_intel_alpine=( mesa-dri-gallium mesa-vulkan-intel intel-media-driver linux-firmware-i915 )
drivers_intel_void=( mesa-dri vulkan-loader mesa-vulkan-intel intel-media-driver )
# VM guest tools: the same names on every family that packages them
GUEST_KVM=( qemu-guest-agent spice-vdagent )
GUEST_VMWARE=( open-vm-tools )
GUEST_HYPERV=( hyperv-daemons )

# -- desktops (menu numbers follow DESKTOP_NAMES)
DESKTOP_NAMES=( gnome xfce kde lxqt cinnamon mate i3 openbox budgie sway hyprland niri none carino-hyprland )
desktop_gnome_fedora=( @workstation-product-environment )
desktop_xfce_fedora=( @xfce-desktop-environment )
desktop_kde_fedora=( @kde-desktop-environment )
desktop_lxqt_fedora=( @lxqt-desktop-environment )
desktop_cinnamon_fedora=( @cinnamon-desktop-environment )
desktop_mate_fedora=( @mate-desktop-environment )
desktop_i3_fedora=( @i3-desktop-environment )
desktop_openbox_fedora=( @basic-desktop-environment )
desktop_budgie_fedora=( budgie-desktop )
desktop_sway_fedora=( sway )
desktop_hyprland_fedora=( hyprland xorg-x11-server-Xwayland waybar xdg-desktop-portal-hyprland hyprpaper hyprshot )
desktop_niri_fedora=( niri waybar )
# EL10 dropped X11 and EPEL 10 has no i3, openbox or sway; ISC dhcp became kea
desktop_gnome_rhel=( @gnome )
desktop_xfce_rhel=( @xfce )
desktop_kde_rhel=( @kde )
desktop_lxqt_rhel=( @lxqt )
desktop_cinnamon_rhel=( @cinnamon )
desktop_mate_rhel=( @mate )
desktop_gnome_debian=( task-gnome-desktop )
desktop_xfce_debian=( task-xfce-desktop )
desktop_kde_debian=( task-kde-desktop )
desktop_lxqt_debian=( task-lxqt-desktop )
desktop_cinnamon_debian=( task-cinnamon-desktop )
desktop_mate_debian=( task-mate-desktop )
desktop_i3_debian=( i3 )
desktop_openbox_debian=( openbox )
desktop_budgie_debian=( budgie-desktop )
desktop_sway_debian=( sway )
desktop_hyprland_debian=( hyprland xdg-desktop-portal-hyprland waybar hyprpaper kitty )
# niri is not in Debian 13 (not even backports): no desktop_niri_debian
desktop_gnome_ubuntu=( ubuntu-desktop-minimal )
desktop_xfce_ubuntu=( xubuntu-desktop-minimal )
desktop_kde_ubuntu=( kubuntu-desktop )
desktop_lxqt_ubuntu=( lubuntu-desktop )
desktop_cinnamon_ubuntu=( cinnamon-desktop-environment )
desktop_mate_ubuntu=( ubuntu-mate-desktop )
desktop_budgie_ubuntu=( ubuntu-budgie-desktop )
desktop_gnome_arch=( gnome gnome-tweaks gdm )
desktop_xfce_arch=( xfce4 xfce4-goodies lightdm lightdm-gtk-greeter )
desktop_kde_arch=( plasma-meta sddm konsole dolphin )
desktop_lxqt_arch=( lxqt sddm breeze-icons )
desktop_cinnamon_arch=( cinnamon lightdm lightdm-gtk-greeter gnome-terminal )
desktop_mate_arch=( mate mate-extra lightdm lightdm-gtk-greeter )
desktop_i3_arch=( i3-wm i3status i3lock dmenu xorg-server xorg-xinit )
desktop_openbox_arch=( openbox obconf-qt xorg-server xorg-xinit )
desktop_budgie_arch=( budgie-desktop lightdm lightdm-gtk-greeter gnome-terminal )
desktop_sway_arch=( sway swaybg swayidle swaylock foot )
desktop_hyprland_arch=( hyprland xdg-desktop-portal-hyprland waybar hyprpaper kitty xorg-xwayland )
desktop_niri_arch=( niri waybar fuzzel )
desktop_gnome_opensuse=( patterns-gnome-gnome )
desktop_xfce_opensuse=( patterns-xfce-xfce )
desktop_kde_opensuse=( patterns-kde-kde )
desktop_lxqt_opensuse=( patterns-lxqt-lxqt )
desktop_cinnamon_opensuse=( patterns-cinnamon-cinnamon )
desktop_mate_opensuse=( patterns-mate-mate )
desktop_i3_opensuse=( i3 dmenu i3status )
desktop_openbox_opensuse=( openbox )
desktop_budgie_opensuse=( budgie-desktop )
desktop_sway_opensuse=( sway )
desktop_hyprland_opensuse=( hyprland xdg-desktop-portal-hyprland waybar hyprpaper kitty )
desktop_niri_opensuse=( niri waybar )
desktop_hyprland_solus=( hyprland )
# extras added to xfce, sway, hyprland, niri and i3; i3 also gets desktopi3extra
desktopextra_fedora=( nautilus fontawesome4-fonts )
desktopextra_debian=( nautilus fonts-font-awesome )
desktopextra_arch=( nautilus otf-font-awesome )
desktopextra_opensuse=( nautilus fontawesome-fonts )
desktopi3extra_fedora=( rofi i3blocks picom kitty nitrogen lxappearance )
desktopi3extra_debian=( rofi i3blocks picom kitty nitrogen lxappearance )
desktopi3extra_arch=( rofi i3blocks picom kitty lxappearance )
desktopi3extra_opensuse=( rofi i3blocks picom kitty nitrogen lxappearance )

# -- Carino Hyprland runtime (derived from hyprland/packages.txt, Fedora names there)
hypr_fedora=( hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent waybar hyprpaper hyprlock hypridle mako wofi kitty nautilus xdg-utils pavucontrol htop NetworkManager-tui procps-ng grim slurp wl-clipboard cliphist jq wireplumber pipewire-pulseaudio playerctl brightnessctl fontconfig ibm-plex-sans-fonts ibm-plex-mono-fonts fontawesome-6-free-fonts fontawesome-6-brands-fonts google-noto-color-emoji-fonts python3 )
hypr_arch=( hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent waybar hyprpaper hyprlock hypridle mako wofi kitty nautilus xdg-utils pavucontrol htop networkmanager procps-ng grim slurp wl-clipboard cliphist jq wireplumber pipewire-pulse playerctl brightnessctl fontconfig ttf-ibm-plex otf-font-awesome noto-fonts-emoji python )
hypr_opensuse=( hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent waybar hyprpaper hyprlock hypridle mako wofi kitty nautilus xdg-utils pavucontrol htop NetworkManager procps grim slurp wl-clipboard cliphist jq wireplumber pipewire-pulseaudio playerctl brightnessctl fontconfig fontawesome-fonts google-noto-coloremoji-fonts python3 )
# unverified on opensuse: ibm-plex-sans-fonts ibm-plex-mono-fonts
hypr_debian=( hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent waybar hyprpaper hyprlock hypridle mako-notifier wofi kitty nautilus xdg-utils pavucontrol htop network-manager procps grim slurp wl-clipboard cliphist jq wireplumber pipewire-pulse playerctl brightnessctl fontconfig fonts-ibm-plex fonts-font-awesome fonts-noto-color-emoji python3 )
# names unverified on solus except hyprland; one that is missing fails alone in the one-at-a-time retry
hypr_solus=( hyprland xdg-desktop-portal-hyprland waybar hyprpaper hyprlock hypridle mako wofi kitty grim slurp wl-clipboard cliphist jq playerctl brightnessctl )

# -- purpose profiles: profile_basic is installed with every purpose, profile_<name> on top
profile_basic_fedora=( gedit yt-dlp ffmpeg tumbler libreoffice pavucontrol vnstat feh wine xrdp htop powertop gtkglext-libs xdotool ncdu scrot xclip tldr xxd )
profile_basic_debian=( gedit yt-dlp ffmpeg tumbler libreoffice pavucontrol vnstat feh wine xrdp htop powertop xdotool ncdu scrot xclip tealdeer xxd )
profile_basic_arch=( gedit yt-dlp ffmpeg tumbler libreoffice-fresh pavucontrol vnstat feh wine htop powertop tealdeer ncdu scrot xclip xdotool )
profile_basic_opensuse=( gedit yt-dlp ffmpeg tumbler libreoffice pavucontrol vnstat feh wine xrdp htop powertop xdotool ncdu scrot xclip tealdeer vim )
# not in alpine: tealdeer, wine (x86_64 only, left out)
profile_basic_alpine=( gedit yt-dlp ffmpeg tumbler libreoffice pavucontrol vnstat feh htop powertop xdotool ncdu scrot xclip xxd )
profile_basic_void=( gedit yt-dlp ffmpeg tumbler libreoffice pavucontrol vnstat feh wine htop powertop xdotool ncdu scrot xclip tealdeer )
profile_development_alpine=( gcc cargo npm py3-pip nodejs go ncurses-dev podman distrobox )
profile_gaming_fedora=( goverlay mangohud gamemode )
profile_gaming_debian=( goverlay mangohud gamemode )
profile_gaming_arch=( goverlay mangohud gamemode )
profile_gaming_opensuse=( goverlay mangohud gamemode )
profile_corporate_fedora=( https://binaries.webex.com/WebexDesktop-CentOS-Official-Package/Webex.rpm vpnc )
profile_corporate_debian=( vpnc )
profile_corporate_arch=( vpnc )
profile_corporate_opensuse=( vpnc )
profile_development_fedora=( gcc cargo npm python3-pip nodejs golang conda ncurses-devel podman distrobox bridge-utils virt-manager virt-top @virtualization libvirt libvirt-devel virt-install qemu-kvm qemu-img )
profile_development_debian=( gcc cargo npm python3-pip nodejs golang libncurses-dev podman distrobox bridge-utils virt-manager virt-top libvirt-daemon-system libvirt-clients virtinst )
profile_development_arch=( gcc rust npm python-pip nodejs go ncurses podman distrobox virt-manager libvirt virt-install qemu-full qemu-img )
profile_development_opensuse=( gcc cargo npm python3-pip nodejs golang make podman distrobox bridge-utils virt-manager virt-top )
profile_astronomy_fedora=( python3-astropy )
profile_astronomy_debian=( python3-astropy )
profile_astronomy_arch=( python-astropy )
profile_compneuro_fedora=( nest python3-nest python3-nibabel python3-networkx python3-numpy python3-scipy python3-matplotlib python3-pandas python3-scikit-learn python3-h5py jupyterlab )
profile_compneuro_debian=( neuron python3-brian python3-nibabel python3-networkx python3-numpy python3-scipy python3-matplotlib python3-pandas python3-sklearn python3-h5py jupyter-notebook )
# AUR only on arch (left out): python-nibabel wxmaxima gmsh
profile_compneuro_arch=( python-networkx python-numpy python-scipy python-matplotlib python-pandas python-scikit-learn python-h5py jupyterlab )
profile_design_fedora=( ImageMagick GraphicsMagick optipng fontforge gmic )
profile_design_debian=( imagemagick graphicsmagick optipng fontforge gmic )
profile_design_arch=( imagemagick graphicsmagick optipng fontforge gmic )
profile_music_fedora=( audacity lmms hydrogen mixxx qjackctl a2jmidid calf lsp-plugins guitarix fluidsynth qsynth )
profile_music_debian=( audacity lmms hydrogen mixxx qjackctl a2jmidid calf-plugins lsp-plugins x42-plugins guitarix fluidsynth qsynth )
profile_music_arch=( audacity lmms hydrogen mixxx qjackctl a2jmidid calf lsp-plugins x42-plugins guitarix fluidsynth qsynth )
profile_cybersecurity_fedora=( nmap wireshark tcpdump nmap-ncat john hydra aircrack-ng hashcat masscan binwalk yara whois bind-utils )
profile_cybersecurity_debian=( nmap zenmap wireshark tshark tcpdump netcat-openbsd john hydra aircrack-ng hashcat masscan binwalk yara whois bind9-dnsutils sqlmap )
profile_cybersecurity_arch=( nmap wireshark-qt tcpdump openbsd-netcat john hydra aircrack-ng hashcat masscan binwalk yara whois bind sqlmap )
profile_forensics_fedora=( sleuthkit testdisk foremost ewftools dc3dd ddrescue chkrootkit rkhunter perl-Image-ExifTool binwalk yara )
profile_forensics_debian=( sleuthkit autopsy testdisk foremost ewf-tools afflib-tools scalpel safecopy hashdeep dc3dd gddrescue chkrootkit rkhunter libimage-exiftool-perl binwalk yara )
profile_forensics_arch=( sleuthkit testdisk ddrescue perl-image-exiftool binwalk yara )
profile_scientific_fedora=( octave gnuplot maxima wxMaxima R-core python3-numpy python3-scipy python3-matplotlib python3-pandas python3-sympy python3-scikit-learn python3-h5py jupyterlab paraview gmsh texlive-collection-latexrecommended )
profile_scientific_debian=( octave gnuplot-qt maxima wxmaxima r-base python3-numpy python3-scipy python3-matplotlib python3-pandas python3-sympy python3-sklearn python3-h5py jupyter-notebook paraview gmsh texlive-latex-recommended )
profile_scientific_arch=( octave gnuplot maxima r python-numpy python-scipy python-matplotlib python-pandas python-sympy python-scikit-learn python-h5py jupyterlab paraview texlive-latexrecommended )
profile_robotics_fedora=( avr-gcc avr-libc avrdude stlink dfu-util minicom picocom python3-pyserial esptool openscad kicad platformio )
profile_robotics_debian=( gcc-avr avr-libc avrdude stlink-tools dfu-util minicom picocom python3-serial esptool openscad kicad )
profile_robotics_arch=( avr-gcc avr-libc avrdude stlink dfu-util minicom picocom python-pyserial esptool openscad kicad )
profile_imagenology_fedora=( dcmtk xmedcon dcm2niix python3-gdcm python3-pydicom python3-nibabel gdcm python3-pynetdicom )
profile_imagenology_debian=( dcmtk xmedcon dcm2niix python3-gdcm python3-pydicom python3-nibabel libgdcm-tools )
profile_imagenology_arch=( dcmtk python-pydicom )
# server: the server argument and plan token add these to base and the development tools
server_fedora=( nmap-ncat xorg-x11-drv-dummy openssh-server cockpit expect ftp vsftpd sshpass )
server_debian=( netcat-traditional xserver-xorg-video-dummy openssh-server cockpit expect ftp vsftpd sshpass )
server_arch=( openbsd-netcat xf86-video-dummy openssh cockpit expect vsftpd sshpass )
server_opensuse=( netcat-openbsd xf86-video-dummy openssh cockpit expect ftp vsftpd sshpass )

# -- Flatpaks (Flathub ids, the same on every family)
flatpak_basic=( org.mozilla.Thunderbird io.mpv.Mpv com.gitlab.davem.ClamTk com.obsproject.Studio com.transmissionbt.Transmission )
flatpak_google=( com.google.Chrome )
flatpak_microsoft=( com.microsoft.Edge com.visualstudio.code com.github.IsmaelMartinez.teams_for_linux )
flatpak_support=( com.github.tchx84.Flatseal org.keepassxc.KeePassXC org.remmina.Remmina com.github.afrantzis.Bless )
flatpak_remote=( com.anydesk.Anydesk com.rustdesk.RustDesk )
flatpak_corporate=( org.onlyoffice.desktopeditors )
flatpak_gaming=( com.valvesoftware.Steam net.davidotek.pupgui2 com.heroicgameslauncher.hgl com.discordapp.Discord net.lutris.Lutris )
flatpak_development=( io.podman_desktop.PodmanDesktop )
flatpak_astronomy=( org.kde.kstars org.siril.Siril org.stellarium.Stellarium )
flatpak_compneuro=( io.github.nest_desktop.nest-desktop org.spyder_ide.spyder )
flatpak_design=( org.gimp.GIMP org.inkscape.Inkscape org.kde.krita org.blender.Blender net.scribus.Scribus org.darktable.Darktable org.kde.kdenlive )
flatpak_music=( org.ardour.Ardour org.musescore.MuseScore )
flatpak_security=( org.zaproxy.ZAP org.ghidra_sre.Ghidra )
flatpak_scientific=( org.spyder_ide.spyder org.scilab.Scilab )
flatpak_robotics=( org.freecad.FreeCAD cc.arduino.IDE2 )
flatpak_imagenology=( io.github.nroduit.Weasis com.github.AlizaMedicalImaging.AlizaMS br.gov.cti.invesalius )
flatpak_librewolf=( io.gitlab.librewolf-community )

# -- purposes: "name|menu label|Flatpak groups"; the menu number is the position (1-15)
PURPOSES=(
    "basic|Basic|basic google microsoft support remote"
    "gaming|Gaming|basic gaming google microsoft support remote"
    "corporate|Corporate|google microsoft support remote corporate"
    "corporate-microsoft|Corporate (Microsoft only)|basic microsoft support remote corporate"
    "corporate-google|Corporate (Google only)|basic google support remote corporate"
    "development|Development|basic google development support remote"
    "astronomy|Astronomy|basic google astronomy support remote"
    "compneuro|Computational Neuroscience|basic compneuro support remote"
    "design|Design|basic design support remote"
    "music|Music Production|basic music support remote"
    "cybersecurity|Cybersecurity|basic security support remote"
    "forensics|Forensics|basic support remote"
    "scientific|Scientific|basic scientific support remote"
    "robotics|Robotics|basic robotics development support remote"
    "imagenology|Medical Imaging (Imagenologia)|basic imagenology support remote"
)

# ==== 5. Repositories ====
rpmfusionUrls() { # prints the two RPM Fusion release package URLs for <fedora|el> <version>
    printf 'https://mirrors.rpmfusion.org/free/%s/rpmfusion-free-release-%s.noarch.rpm\n' "$1" "$2"
    [[ $1 == fedora ]] && printf 'https://mirrors.rpmfusion.org/nonfree/%s/rpmfusion-nonfree-release-%s.noarch.rpm\n' "$1" "$2"
}
fedoraVersion() { local v; v=$(rpm -E %fedora 2>/dev/null); [[ $v =~ ^[0-9]+$ ]] || v=${OS_VER%%.*}; printf '%s\n' "$v"; }
repoFedora() {
    local -a urls
    if [[ ! -e /etc/yum.repos.d/rpmfusion-free.repo || ! -e /etc/yum.repos.d/rpmfusion-nonfree.repo ]]; then
        mapfile -t urls < <(rpmfusionUrls fedora "$(fedoraVersion)")
        root dnf -y install "${urls[@]}" && record ok "RPM Fusion free + nonfree"
    else ok "RPM Fusion is already enabled."; fi
    root dnf -y config-manager setopt fedora-cisco-openh264.enabled=1 || warn "Could not enable the Cisco OpenH264 repository."
}
repoRhel() {
    local v=${OS_VER%%.*} epel=1
    case $OS_ID in
        amzn) say "Amazon Linux has no EPEL or CRB; its repositories are left as they are."; record skip "EPEL + CRB"; return 0 ;;
        rhel) root subscription-manager repos --enable "codeready-builder-for-rhel-$v-$(uname -m)-rpms" &&
                  root dnf -y install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-$v.noarch.rpm" || epel=0 ;;
        ol)   root dnf -y install dnf-plugins-core "oracle-epel-release-el$v" &&
                  root dnf config-manager --set-enabled "ol${v}_codeready_builder" || epel=0 ;;
        *)    root dnf -y install dnf-plugins-core epel-release &&
                  { root dnf config-manager --set-enabled crb || root dnf config-manager --set-enabled powertools; } || epel=0 ;;
    esac
    (( epel )) || { record fail "EPEL + CRB (EL $v)"; return 1; }
    root dnf -y install "$(rpmfusionUrls el "$v")" && record ok "CRB + EPEL + RPM Fusion free (EL $v)"
}
repoDebian() { # contrib + non-free on the existing suites (no duplicate source files)
    [[ $OS_ID == debian ]] || { say "$OS_ID: its repository components are left as they are."; return 0; }
    local f=/etc/apt/sources.list.d/debian.sources
    [[ -e $f ]] && root sed -i -E 's/^Components: main( non-free-firmware)?$/Components: main contrib non-free non-free-firmware/' "$f"
    f=/etc/apt/sources.list
    [[ -e $f ]] && root sed -i -E '/^deb(-src)? .*debian/ s/ main( non-free-firmware)?$/ main contrib non-free non-free-firmware/' "$f"
    REFRESHED=0
}
repoUbuntu() {
    have add-apt-repository || pkgInstall software-properties-common
    root add-apt-repository -y universe && root add-apt-repository -y multiverse && root add-apt-repository -y restricted
    REFRESHED=0
}
repoArch() {
    if grep -q '^\[multilib\]' /etc/pacman.conf 2>/dev/null; then ok "multilib is enabled."; return 0; fi
    [[ $(uname -m) == x86_64 ]] || return 0
    confirm "Enable [multilib] (32-bit libraries for Wine, Steam and lib32 drivers)?" y || return 0
    root sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf && REFRESHED=0
}
repoOpensuse() {
    [[ $OS_ID == opensuse* ]] || { say "$OS_ID: Packman is for openSUSE only, skipped."; return 0; }
    local dist=openSUSE_Tumbleweed
    case $OS_ID in *slowroll*) dist=openSUSE_Slowroll ;; *leap*) dist=openSUSE_Leap_$OS_VER ;; esac
    if zypper -n lr 2>/dev/null | grep -qi packman; then ok "Packman is already added."; return 0; fi
    confirm "Add Packman for full codecs (multimedia packages switch vendor to Packman)?" y || return 0
    root zypper -n ar -cfp 90 "https://ftp.gwdg.de/pub/linux/misc/packman/suse/$dist/" packman
    root zypper -n --gpg-auto-import-keys refresh packman
    root zypper -n dup --from packman --allow-vendor-change --auto-agree-with-licenses
}
repoVoid() {
    root xbps-install -y void-repo-nonfree
    [[ $(xbps-uhelper arch 2>/dev/null) == x86_64 ]] && root xbps-install -y void-repo-multilib void-repo-multilib-nonfree
    REFRESHED=0
}
repoSlackware() { # slackpkg needs one mirror picked by hand, then the Slackware key once
    slackpkgReady || return 1
    root "${PM_REFRESH[@]}" gpg
}
repositoriesSetup() {
    [[ -n ${DONE_GROUP[repos]:-} ]] && return 0
    DONE_GROUP[repos]=1
    say "Repositories needed for codecs and drivers"
    case $FAMILY in
        fedora) repoFedora ;; rhel) repoRhel ;; debian) repoDebian ;; ubuntu) repoUbuntu ;; arch) repoArch ;;
        opensuse) repoOpensuse ;; void) repoVoid ;; slackware) repoSlackware ;;
        alpine) root sed -i -E '/edge/! s|^#(.*/community)$|\1|' /etc/apk/repositories; REFRESHED=0 ;;
        # repository ids unverified: Mageia 9/10 name them mageia-<arch>-nonfree / -tainted
        mageia) if [[ $OS_ID == mageia ]]; then
                    root dnf config-manager --set-enabled "mageia-$(uname -m)-nonfree" "mageia-$(uname -m)-tainted"
                else say "$OS_ID: enable the non-free repository yourself in om-repo-picker."; fi ;;
        *) say "No extra repositories for $FAMILY." ;;
    esac
}

# ==== 6. baseSetup ====
codecsSetup() {
    if [[ $FAMILY == fedora ]]; then
        root dnf -y swap ffmpeg-free ffmpeg --allowerasing
        root dnf -y swap mesa-va-drivers mesa-va-drivers-freeworld --allowerasing
    fi
    [[ $FAMILY == atomic ]] && { say "Atomic: codecs come from the image or from Flatpak runtimes."; return 0; }
    installGroup codecs "multimedia codecs"
}
gentooNote() {
    say "Gentoo next steps (not automated, they depend on your USE flags and kernel):"
    printf '  %s\n' 'VIDEO_CARDS in /etc/portage/make.conf: "nvidia", "amdgpu radeonsi" or "intel"' \
        'NVIDIA: emerge x11-drivers/nvidia-drivers (USE=kernel-open for Turing or newer)' \
        'Firmware and microcode: emerge sys-kernel/linux-firmware sys-firmware/intel-microcode' \
        'Hyprland: eselect repository enable hyproverlay && emaint sync -r hyproverlay && emerge gui-wm/hyprland'
}
slackwareNote() {
    say "Slackware next steps (not automated, they are built from SlackBuilds.org):"
    printf '  %s\n' 'A kernel upgrade: rebuild the initrd if you use one (mkinitrd) and run lilo or update GRUB before rebooting' \
        'SlackBuilds.org tools: sbopkg (sbopkg.org) or slpkg (on SlackBuilds.org); add desktop/flatpak for Flatpaks' \
        'CPU microcode loads early only when the initrd or the bootloader carries it (see mkinitrd -P)' \
        'NVIDIA: system/nvidia-kernel + system/nvidia-driver (nvidia-legacy580-* for Maxwell/Pascal, legacy470 for Kepler)' \
        'Mesa, Vulkan and VA-API for AMD and Intel ship with a full install'
}
baseSetup() {
    banner "Base setup"
    repositoriesSetup
    [[ ${PM_REFRESH[*]} == "${PM_UPGRADE[*]}" ]] || pkgRefresh   # pacman: the upgrade below is the refresh
    REFRESHED=1
    say "Upgrading the system"
    if pkgUpgrade; then record ok "system upgrade"; else record fail "system upgrade"; fi
    installGroup base "base packages"
    codecsSetup
    if [[ $VIRT == none ]]; then
        installGroup firmware "firmware"
        [[ $CPU != other ]] && installGroup "microcode_$CPU" "$CPU CPU microcode"
    fi
    if [[ $FAMILY == slackware ]]; then say "Slackware: Flatpak is not in the distribution, it is skipped (see the notes below)."
    else flatpakSetup || record fail "Flathub"; fi
    driversSetup
    [[ $FAMILY == gentoo ]] && gentooNote
    [[ $FAMILY == slackware ]] && slackwareNote
    [[ $FAMILY == atomic ]] && NEED_REBOOT=1
    return 0
}

# ==== 7. driversSetup ====
secureBootNote() {
    warn "Secure Boot is ON: the NVIDIA kernel module must be signed with a key you enroll (MOK) or it will not load."
    case $FAMILY in
        fedora) say "After the install: sudo kmodgenca -a; sudo mokutil --import /etc/pki/akmods/certs/public_key.der; reboot and pick 'Enroll MOK'." ;;
        atomic) say "Atomic: layer the silverblue-akmods-keys package (its README has the steps) so the module is signed with an enrolled key." ;;
        debian|ubuntu) say "DKMS signs with /var/lib/dkms/mok.pub: sudo mokutil --import /var/lib/dkms/mok.pub; reboot and pick 'Enroll MOK'." ;;
        opensuse) say "The -signed-kmp packages are signed by SUSE; accept the key at the next boot if asked." ;;
        *) say "Sign the module yourself, or turn Secure Boot off in the firmware (this script never does that)." ;;
    esac
}
nvidiaAtomic() {
    if [[ $OS_ID == bazzite || $OS_ID == bluefin || $OS_ID == aurora ]]; then
        warn "$OS_ID: rebase to its -nvidia image instead of layering the driver."; record skip "NVIDIA driver"; return 0
    fi
    if [[ ! -e /etc/yum.repos.d/rpmfusion-nonfree.repo ]]; then
        local -a urls; mapfile -t urls < <(rpmfusionUrls fedora "$(fedoraVersion)")
        root rpm-ostree install --idempotent "${urls[@]}"
        warn "RPM Fusion is layered. Reboot, then run 'setup.sh nvidia' again to layer the driver."
        NEED_REBOOT=1; record skip "NVIDIA driver (after reboot)"; return 0
    fi
    installGroup drivers_nvidia "NVIDIA driver"
    root rpm-ostree kargs --append=rd.driver.blacklist=nouveau,nova_core --append=modprobe.blacklist=nouveau,nova_core
    NEED_REBOOT=1
}
nvidiaRhel() {
    local v=${OS_VER%%.*}
    [[ $NVGEN == open ]] || { warn "Pre-Turing NVIDIA on EL: use ELRepo's kmod-nvidia-580xx."; record skip "NVIDIA driver"; return 0; }
    if [[ $OS_ID == almalinux ]]; then pkgInstall almalinux-release-nvidia-driver; installGroup drivers_nvidia "NVIDIA driver (open)"; return; fi
    warn "Add NVIDIA's repository first: https://developer.download.nvidia.com/compute/cuda/repos/rhel$v/$(uname -m)/cuda-rhel$v.repo, then install nvidia-open."
    record skip "NVIDIA driver (manual on $OS_ID)"
}
nvidiaSetup() {
    local g=drivers_nvidia
    if [[ -z ${CARINO_SETUP_GPU:-} ]] && have nvidia-smi && nvidia-smi >/dev/null 2>&1; then ok "The NVIDIA driver is already working."; return 0; fi
    if [[ $NVGEN == unknown ]]; then
        warn "lspci does not name this NVIDIA card's generation."
        if confirm "Is it a Turing (RTX 20 / GTX 16) or newer card?" y; then NVGEN=open; else NVGEN=580; fi
    fi
    [[ $NVGEN != open ]] && g=drivers_nvidia$NVGEN
    say "NVIDIA GPU, driver branch '$NVGEN' (open = Turing or newer, 580 = Maxwell/Pascal, 470 = Kepler)."
    [[ $SECUREBOOT == on ]] && secureBootNote
    confirm "Install the NVIDIA driver?" y || { record skip "NVIDIA driver"; return 0; }
    case $FAMILY in
        fedora)   installGroup "$g" "NVIDIA driver ($NVGEN)" && nvidiaAkmods ;;
        atomic)   nvidiaAtomic ;;
        rhel)     nvidiaRhel ;;
        ubuntu)   installGroup drivers_nvidia "NVIDIA helpers"
                  if [[ $OS_ID == pop ]]; then pkgInstall system76-driver-nvidia; else root ubuntu-drivers install; fi ;;
        opensuse) nvidiaOpensuse "$g" ;;
        debian|arch|solus|void) nvidiaPackaged "$g" ;;
        alpine)   warn "Alpine (musl) has no NVIDIA driver package; Mesa's nouveau/NVK drives the card."; record skip "NVIDIA driver" ;;
        gentoo)   warn "Gentoo: emerge x11-drivers/nvidia-drivers yourself (see the notes below)."; record skip "NVIDIA driver" ;;
        slackware) warn "Slackware: build nvidia-kernel and nvidia-driver from SlackBuilds.org (see the notes below)."; record skip "NVIDIA driver" ;;
        *)        warn "$FAMILY: install the NVIDIA driver with the distribution's own tool (Mageia: the Control Center)."; record skip "NVIDIA driver" ;;
    esac
}
nvidiaAkmods() { # Fedora: build the module now so the reboot finds it, only when an akmod really installed
    if (( ! DRYRUN )) && ! rpm -qa 'akmod-nvidia*' | grep -q .; then
        warn "No akmod-nvidia package is installed (is RPM Fusion nonfree enabled?)."; record fail "NVIDIA kernel module"; return 1
    fi
    say "Building the kernel module now (akmods), so the reboot finds it."
    root akmods --force
}
nvidiaOpensuse() { # NVIDIA's openSUSE repository, then the G07/G06 packages
    [[ $OS_ID == opensuse* ]] || { warn "$OS_ID: the openSUSE NVIDIA repository is for openSUSE only."; record skip "NVIDIA driver"; return 0; }
    local d=Tumbleweed
    case $OS_ID in *slowroll*) d=Slowroll ;; *leap*) d=Leap ;; esac
    pkgInstall "openSUSE-repos-$d-NVIDIA"
    root zypper -n --gpg-auto-import-keys refresh
    installGroup "$1" "NVIDIA driver ($NVGEN)"
}
nvidiaPackaged() { # debian, arch, solus, void: the driver is a plain package list
    if [[ $FAMILY == void && $(xbps-uhelper arch 2>/dev/null) == *musl ]]; then
        warn "Void musl: NVIDIA ships glibc only (nouveau/NVK instead)."; record skip "NVIDIA driver"; return 0
    fi
    if ! arrayFor "$1" >/dev/null; then
        warn "No packaged $NVGEN NVIDIA driver on $FAMILY (Arch: AUR only, e.g. nvidia-580xx-dkms)."; record skip "NVIDIA driver"; return 0
    fi
    [[ $FAMILY == arch ]] && pkgInstall "$(archHeaders)"
    installGroup "$1" "NVIDIA driver ($NVGEN)"
}
archHeaders() { # the headers for the running kernel package (linux, linux-lts, linux-zen, linux612, linux-cachyos, ...)
    local k; k=$(pacman -Qqo "/usr/lib/modules/$(uname -r)/vmlinux" 2>/dev/null)
    printf '%s-headers\n' "${k:-linux}"
}
guestTools() {
    case $VIRT in
        kvm|qemu) pkgInstall "${GUEST_KVM[@]}" ;; vmware) pkgInstall "${GUEST_VMWARE[@]}" ;; microsoft) pkgInstall "${GUEST_HYPERV[@]}" ;;
        oracle) say "VirtualBox: install the Guest Additions from the VirtualBox Devices menu." ;;
        *) say "No guest tools known for '$VIRT'." ;;
    esac
}
driversSetup() {
    banner "Graphics drivers"
    if [[ $VIRT != none ]]; then say "Virtual machine ($VIRT): guest tools instead of GPU drivers and microcode."; guestTools; return 0; fi
    [[ -n $GPUS ]] || { say "No GPU was detected (no lspci and nothing in /sys/class/drm)."; return 0; }
    local v
    for v in $GPUS; do
        if [[ $FAMILY == slackware && $v != nvidia ]]; then say "Slackware: Mesa, Vulkan and VA-API for $v ship with a full install."; continue; fi
        case $v in
            nvidia) nvidiaSetup ;;
            amd)    installGroup drivers_amd "AMD graphics (Mesa, Vulkan, VA-API, OpenCL)" ;;
            intel)  installGroup drivers_intel "Intel graphics (Mesa, Vulkan, VA-API)" ;;
        esac
    done
    return 0
}

# ==== 8. desktopSetup ====
enableDisplayManager() {
    have systemctl || return 0
    local dm
    if [[ ! -e /etc/systemd/system/display-manager.service ]]; then
        for dm in gdm sddm lightdm; do
            [[ -e /usr/lib/systemd/system/$dm.service || -e /lib/systemd/system/$dm.service ]] && { root systemctl enable "$dm"; break; }
        done
    fi
    root systemctl set-default graphical.target
}
installDesktop() { # installDesktop <name from DESKTOP_NAMES>
    local de=$1
    if [[ $FAMILY == slackware && $de != none && $de != *hyprland ]]; then   # the Hyprland choices give their own reason
        say "Desktops are not for Slackware here: a full install has KDE Plasma and Xfce, others come from SlackBuilds.org."; record skip "$de desktop"; return 0
    fi
    case $de in
        none) say "No desktop installed."; return 0 ;;
        carino-hyprland) carinoHyprland; return ;;
        hyprland) hyprSupported || { warn "Hyprland is not available here: $HYPR_WHY"; record skip "Hyprland"; return 0; }; hyprRepo ;;
    esac
    installGroup "desktop_$de" "$de desktop"; local rc=$?
    PM_TARGET=()   # trixie-backports is for the Hyprland packages only
    (( rc == 0 )) || return 0
    case $de in
        xfce|sway|hyprland|niri) installGroup desktopextra "desktop extras" ;;
        i3) installGroup desktopi3extra "i3 extras"; installGroup desktopextra "desktop extras" ;;
    esac
    enableDisplayManager
}
desktopMenu() { # desktopMenu [force]: only offered when no desktop session is present
    if [[ $HAS_DESKTOP == yes && ${1:-} != force ]]; then say "A desktop is already present, the desktop menu is skipped."; return 0; fi
    banner "Desktop"
    local i
    for i in "${!DESKTOP_NAMES[@]}"; do printf '  %2d) %s\n' $((i + 1)) "${DESKTOP_NAMES[i]}"; done
    ask "Desktop number" 13
    if [[ $REPLY =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#DESKTOP_NAMES[@]} )); then installDesktop "${DESKTOP_NAMES[REPLY - 1]}"
    else warn "'$REPLY' is not a desktop number, nothing installed."; fi
}

# ==== 9. Profiles ====
purposeEntry() { # purposeEntry <name>: prints "name|label|flatpak groups"
    local e
    for e in "${PURPOSES[@]}"; do [[ ${e%%|*} == "$1" ]] && { printf '%s\n' "$e"; return 0; }; done
    return 1
}
installPurpose() {
    local entry name label groups g ref; local -a ids=()
    entry=$(purposeEntry "$1") || { fail "Unknown purpose '$1'."; return 1; }
    IFS='|' read -r name label groups <<<"$entry"
    banner "Purpose: $name ($label)"
    if [[ $FAMILY == slackware ]]; then
        say "Purpose profiles are not for Slackware: build the applications from SlackBuilds.org (sbopkg or slpkg)."; record skip "$label (not for Slackware)"; return 0
    fi
    [[ $name == cybersecurity ]] && warn "Dual-use tools: use them only where you are allowed to. Packet capture: sudo usermod -aG wireshark $TARGET_USER"
    if [[ $FAMILY == atomic ]]; then say "Atomic: native profile packages are skipped (use toolbox or distrobox); Flatpaks follow."
    else
        installGroup profile_basic "basic applications"
        installGroup "profile_${name//-/_}" "$label packages"
    fi
    for g in $groups; do ref="flatpak_${g}[@]"; ids+=("${!ref}"); done
    if flatpakInstall "${ids[@]}"; then record ok "$label Flatpaks"; else record fail "$label Flatpaks"; fi
    if [[ $name == development ]] && confirm "Create Fedora, Ubuntu and Debian distrobox containers?" y; then distroboxSetup; fi
    return 0
}
profileMenu() {
    banner "Purpose profiles"
    local i n
    for i in "${!PURPOSES[@]}"; do IFS='|' read -r _ n _ <<<"${PURPOSES[i]}"; printf '  %2d) %s\n' $((i + 1)) "$n"; done
    ask "Profile numbers, several allowed, e.g. '2 6' (0 = none)" 1
    for n in $REPLY; do
        [[ $n == 0 ]] && return 0
        if [[ $n =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#PURPOSES[@]} )); then installPurpose "${PURPOSES[n - 1]%%|*}"
        else warn "'$n' is not a profile number, skipped."; fi
    done
}

# ==== 10. carinoHyprland ====
hyprSupported() { # sets HYPR_HOW (copr|repo|backports|ppa) or HYPR_WHY; Carino Hyprland needs Hyprland >= 0.55 (Lua)
    local c=${UBU_CODE:-$OS_CODE} d=${DEB_CODE:-$OS_CODE}   # derivatives name their base release
    HYPR_HOW='' HYPR_WHY=''
    case $FAMILY in
        fedora)   HYPR_HOW=copr ;;
        arch|solus) HYPR_HOW=repo ;;
        opensuse)
            if [[ $OS_ID == *tumbleweed* || $OS_ID == *slowroll* ]]; then HYPR_HOW=repo
            else HYPR_WHY="$OS_ID does not package Hyprland; openSUSE Tumbleweed or Slowroll do."; fi ;;
        debian)
            case $d in
                trixie) HYPR_HOW=backports ;;
                forky|sid) HYPR_HOW=repo ;;
                *) HYPR_WHY="Debian ${d:-$OS_VER} has no Hyprland 0.55+; Debian 13 (backports) or newer does." ;;
            esac ;;
        ubuntu)
            if [[ $c == noble || $c == resolute ]]; then HYPR_HOW=ppa
            elif [[ $OS_ID == ubuntu ]] && verGe "$OS_VER" 26.10; then HYPR_HOW=repo
            else HYPR_WHY="Ubuntu base '${c:-$OS_VER}' has no Hyprland 0.55+; 24.04 and 26.04 (PPA) or 26.10+ do."; fi ;;
        atomic)   HYPR_WHY="Fedora Atomic: use a package-based Fedora or a Hyprland image." ;;
        rhel)     HYPR_WHY="EPEL has no Hyprland and the EL libraries are too old." ;;
        alpine)   HYPR_WHY="Alpine ships Hyprland 0.54, older than the 0.55 the Lua configuration needs." ;;
        void)     HYPR_WHY="Void does not package Hyprland (only a third-party repository exists)." ;;
        gentoo)   HYPR_WHY="Gentoo: emerge gui-wm/hyprland from hyproverlay yourself, then copy the hyprland/ bundle." ;;
        slackware) HYPR_WHY="Slackware does not package Hyprland 0.55 or newer." ;;
        *)        HYPR_WHY="$FAMILY ships no Hyprland 0.55+ in its stable release." ;;
    esac
    [[ -z $HYPR_WHY ]]
}
hyprRepo() {
    case $HYPR_HOW in
        copr) pkgInstall dnf5-plugins; root dnf -y copr enable lionheartp/Hyprland ;;
        ppa)  have add-apt-repository || pkgInstall software-properties-common
              root add-apt-repository -y ppa:cppiber/hyprland && pkgRefresh ;;
        backports)
            if ! grep -rqsE '^[^#]*trixie-backports' /etc/apt/sources.list /etc/apt/sources.list.d/; then
                writeRootFile /etc/apt/sources.list.d/carino-backports.sources "Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp"
                pkgRefresh
            fi
            PM_TARGET=(-t trixie-backports) ;;
    esac
}
hyprVersionCheck() {
    (( DRYRUN )) && return 0
    local v; v=$(Hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    if [[ -z $v ]]; then warn "Hyprland did not report a version; check that it installed."
    elif verGe "$v" 0.55.0; then ok "Hyprland $v (0.55 or newer, the Lua configuration loads)."
    else warn "Hyprland $v is older than 0.55: the Lua configuration will not load."; fi
}
hyprBundle() { # sets HYPR_SRC to the bundle: beside this script, else downloaded from GitHub
    if [[ -d $SCRIPT_DIR/hyprland/.config/hypr ]]; then HYPR_SRC=$SCRIPT_DIR/hyprland; return 0; fi
    local tmp=/tmp/carino-hyprland-dry-run
    (( DRYRUN )) || tmp=$(mktemp -d) || return 1
    run curl -fsSL -o "$tmp/simplesetup.tar.gz" "$BUNDLE_URL" &&
        run tar -xzf "$tmp/simplesetup.tar.gz" -C "$tmp" SimpleSetup-main/hyprland || return 1
    HYPR_SRC=$tmp/SimpleSetup-main/hyprland
}
hyprCopy() { # backs up the folders the bundle replaces, then copies it into the real user's home
    local src=$1 home=$TARGET_HOME d moved=0 backup
    backup=$home/.config/carino-backup-$(date +%Y%m%d-%H%M%S)
    asUser mkdir -p "$home/.config" "$home/.local/share" "$home/Pictures/Screenshots"   # as the user, never root-owned
    for d in "$src"/.config/*/; do   # every ~/.config folder the bundle ships
        d=$(basename "$d")
        [[ -e $home/.config/$d ]] || continue
        (( moved )) || asUser mkdir -p "$backup" || return 1
        moved=1
        run mv "$home/.config/$d" "$backup/" || { fail "Could not move ~/.config/$d aside, nothing was copied."; return 1; }
    done
    (( moved )) && say "Your previous configuration was moved to $backup"
    for d in .config .local Pictures; do
        [[ -e $src/$d ]] && run cp -a --no-preserve=ownership "$src/$d" "$home/"
    done
    if (( EUID == 0 )) && [[ $TARGET_USER != root ]]; then
        run chown -R "$TARGET_USER:" "$home/.config" "$home/.local/share/fonts" "$home/Pictures"
    fi
    if have fc-cache || (( DRYRUN )); then asUser fc-cache -f; fi
}
carinoHyprland() {
    [[ -n ${DONE_GROUP[carino]:-} ]] && return 0
    DONE_GROUP[carino]=1
    banner "Carino Hyprland"
    if ! hyprSupported; then warn "Carino Hyprland is not available here: $HYPR_WHY"; record skip "Carino Hyprland"; return 0; fi
    hyprRepo
    installGroup hypr "Carino Hyprland packages"
    PM_TARGET=()
    hyprVersionCheck
    hyprBundle || { fail "The Carino Hyprland bundle could not be found or downloaded."; record fail "Carino Hyprland bundle"; return 1; }
    hyprCopy "$HYPR_SRC" || { record fail "Carino Hyprland configuration"; return 1; }
    record ok "Carino Hyprland configuration for $TARGET_USER"
    say "Log out and choose Hyprland at the login screen (no login screen: type Hyprland on a text console)."
    say "Main keys (ALT is the main modifier):"
    printf '  %s\n' "ALT+Q terminal    ALT+E app launcher    ALT+C close window" \
        "ALT+1..9 workspaces    ALT+S screenshot    SUPER+Escape power menu (SUPER+ALT+L locks)" \
        "Every key: https://github.com/MiguelCarino/SimpleSetup/tree/main/hyprland"
}

# ==== 11. Extras ====
distroboxSetup() {
    have distrobox-create || pkgInstall distrobox podman
    local b
    for b in fedora=quay.io/fedora/fedora:latest ubuntu=docker.io/library/ubuntu:latest debian=docker.io/library/debian:latest; do
        asUser distrobox-create --name "${b%%=*}" --image "${b#*=}" -Y || record fail "distrobox ${b%%=*}"
    done
}
anydeskSetup() { if flatpakInstall "${flatpak_remote[@]}"; then record ok "AnyDesk + RustDesk"; else record fail "AnyDesk + RustDesk"; fi; }
librewolfSetup() {
    case $FAMILY in
        fedora|rhel) root curl -fsSL -o /etc/yum.repos.d/librewolf.repo https://repo.librewolf.net/librewolf.repo && pkgInstall librewolf ;;
        debian|ubuntu) pkgInstall extrepo && root extrepo enable librewolf && pkgRefresh && pkgInstall librewolf ;;
        *) flatpakInstall "${flatpak_librewolf[@]}" ;;
    esac
}
shareSetup() {
    confirm "Mount a Windows (SMB) shared folder at ~/WinFiles?" n || { say "No shared folder was mounted."; return 0; }
    local server share user
    ask "Server name or address" ""; server=$REPLY
    ask "Shared folder name" ""; share=$REPLY
    ask "User name on $server" "$TARGET_USER"; user=$REPLY
    [[ -n $server && -n $share ]] || { warn "A server and a folder are needed, nothing was mounted."; return 0; }
    have mount.cifs || pkgInstall cifs-utils
    asUser mkdir -p "$TARGET_HOME/WinFiles"
    root mount.cifs "//$server/$share" "$TARGET_HOME/WinFiles" -o "user=$user,uid=$(id -u "$TARGET_USER")"
}
protonSetup() { # latest GE-Proton into Steam's compatibilitytools.d (Flatpak Steam path when present)
    local dir=$TARGET_HOME/.steam/root/compatibilitytools.d tag=GE-Proton-latest tmp=/tmp/carino-proton-dry-run
    [[ -d $TARGET_HOME/.var/app/com.valvesoftware.Steam ]] && dir=$TARGET_HOME/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d
    if (( ! DRYRUN )); then
        tag=$(curl -fsSL https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep -oE '"tag_name": *"[^"]+"' | cut -d'"' -f4)
        [[ -n $tag ]] || { fail "Could not find the latest GE-Proton release."; record fail "GE-Proton"; return 1; }
        [[ -d $dir/$tag ]] && { ok "$tag is already installed."; return 0; }
        tmp=$(mktemp -d) && chmod 755 "$tmp"   # the user's tar must read what root downloads
    fi
    asUser mkdir -p "$dir"
    if run curl -fsSL -o "$tmp/$tag.tar.gz" "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$tag/$tag.tar.gz" &&
        asUser tar -xzf "$tmp/$tag.tar.gz" -C "$dir"; then record ok "$tag"; else record fail "GE-Proton"; fi
    (( DRYRUN )) || rm -rf "$tmp"
}
serverSetup() {
    banner "Server"
    pkgRefresh
    pkgUpgrade || record fail "system upgrade"
    installGroup base "base packages"
    installGroup server "server packages"
    installGroup profile_development "development tools"
    local ssh=sshd
    [[ $FAMILY == debian || $FAMILY == ubuntu ]] && ssh=ssh
    confirm "Enable SSH and Cockpit now (and open them in firewalld if it runs)?" y || return 0
    enableService "$ssh"
    enableService cockpit.socket
    if have firewall-cmd; then root firewall-cmd --permanent --add-service=ssh --add-service=cockpit && root firewall-cmd --reload; fi
}
updateSetup() {
    banner "Update"
    pkgRefresh
    if pkgUpgrade; then record ok "system upgrade"; else record fail "system upgrade"; fi
    if have flatpak; then root flatpak update -y --noninteractive || record fail "Flatpak update"; fi
    [[ $FAMILY == atomic ]] && NEED_REBOOT=1
    return 0
}

# ==== 12. Plan ====
PLAN_TOKENS=()
planParse() { # validates every CARINO_SETUP_PLAN token before anything runs; one bad token refuses the plan
    local t bad=0 action=0; local -a parts
    [[ -n $ARG ]] && { fail "CARINO_SETUP_PLAN cannot be combined with the argument '$ARG'. Nothing was run."; exit 2; }
    IFS=',' read -r -a parts <<<"${PLAN//$'\n'/,}"
    for t in "${parts[@]}"; do
        t=${t//[[:space:]]/}
        [[ -n $t ]] || continue
        case $t in
            technical|drivers|update|server|hyprland) action=1 ;;
            desktop=*) if printf '%s\n' "${DESKTOP_NAMES[@]}" | grep -qxF -- "${t#desktop=}"; then action=1
                       else fail "Unknown desktop in '$t'. Valid desktops: ${DESKTOP_NAMES[*]}"; bad=1; fi ;;
            purpose=*) if purposeEntry "${t#purpose=}" >/dev/null; then action=1
                       else fail "Unknown purpose in '$t'. Valid purposes: $(printf '%s ' "${PURPOSES[@]%%|*}")"; bad=1; fi ;;
            reboot=yes|reboot=no) ;;
            reboot=*) fail "reboot takes yes or no, not '${t#reboot=}'."; bad=1 ;;
            *) fail "Unknown plan token '$t'. Valid tokens: technical drivers update server hyprland desktop=<name> purpose=<name> reboot=yes|no"; bad=1 ;;
        esac
        PLAN_TOKENS+=("$t")
    done
    (( action || bad )) || { fail "The plan has nothing to do."; bad=1; }
    (( bad )) && { fail "The plan was refused; nothing was run."; exit 2; }
    say "Plan accepted: ${PLAN_TOKENS[*]}"
}
planRun() {
    local t
    for t in "${PLAN_TOKENS[@]}"; do
        say "Plan step: $t"
        case $t in
            technical) baseSetup; desktopMenu ;;
            drivers)   repositoriesSetup; driversSetup ;;
            update)    updateSetup ;;
            server)    serverSetup ;;
            hyprland)  carinoHyprland ;;
            desktop=*) installDesktop "${t#desktop=}" ;;
            purpose=*) installPurpose "${t#purpose=}" ;;
            reboot=*)  REBOOT=${t#reboot=} ;;
        esac
    done
    say "CARINO_SETUP_PLAN has finished."
}

# ==== 13. Main ====
usage() {
    cat <<'EOF'
Usage: setup.sh [dry-run] [argument]
  (none)      interactive: check the system, base setup, desktop, purpose profiles, Carino Hyprland
  quick       base setup + Basic profile (native apps, basic and Google Flatpaks)
  simple      base setup only (repositories, upgrade, base packages, codecs, firmware, drivers)
  server      base + server + development packages, enables SSH and Cockpit
  drivers     repositories + GPU drivers (nvidia, amd and intel are the same: the GPU is detected)
  desktop     desktop menu, even when a desktop is present
  hyprland    the Carino Hyprland desktop configuration only
  distrobox   Fedora, Ubuntu and Debian distrobox containers
  anydesk     AnyDesk and RustDesk (Flatpak)
  librewolf   LibreWolf browser
  share       mount a Windows shared folder
  proton      latest GE-Proton for Steam
  update      refresh and upgrade packages and Flatpaks
Unattended: CARINO_SETUP_PLAN=technical,desktop=<name>,purpose=<name>,hyprland,drivers,update,server,reboot=yes|no
EOF
}
openLog() {
    (( DRYRUN )) && [[ -z ${CARINO_SETUP_LOG:-} ]] && return 0
    LOG=${CARINO_SETUP_LOG:-carino-setup-$(date +%Y%m%d-%H%M%S).log}
    { : >>"$LOG"; } 2>/dev/null || LOG=/tmp/${LOG##*/}
    exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' >>"$LOG")) 2>&1
}
interactive() {
    if confirm "Run the base setup (repositories, upgrade, base packages, codecs, firmware, drivers)?" y; then baseSetup; else record skip "base setup"; fi
    desktopMenu
    profileMenu
    if [[ -n ${DONE_GROUP[carino]:-} ]]; then :   # already chosen in the desktop menu
    elif hyprSupported; then
        if confirm "Install the Carino Hyprland desktop configuration?" n; then carinoHyprland; fi
    else say "Carino Hyprland is not offered here: $HYPR_WHY"; fi
}
finish() {
    banner "Summary"
    local r
    for r in "${RESULTS[@]}"; do printf '  %-5s %s\n' "${r%%|*}" "${r#*|}"; done
    (( ${#RESULTS[@]} )) || say "Nothing was installed."
    [[ -n $LOG ]] && say "Log: $LOG"
    (( DRYRUN )) && say "Dry run: nothing was changed."
    (( NEED_REBOOT )) && warn "A reboot is needed to apply the layered packages."
    if (( SLACK_KERNEL )); then warn "No reboot from here: update the initrd and the bootloader for the new kernel first."; return 0; fi
    case $REBOOT in
        yes) root reboot ;;
        no)  say "Reboot: no (plan)." ;;
        *)   if confirm "Reboot now?" n; then root reboot; fi ;;
    esac
}
main() {
    (( NARGS <= 1 )) || { fail "Only one argument is accepted (dry-run comes first)."; usage; exit 2; }
    case $ARG in
        ''|quick|simple|server|nvidia|amd|intel|drivers|desktop|hyprland|distrobox|anydesk|librewolf|share|proton|update) ;;
        help|-h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
    [[ -n $PLAN ]] && planParse
    openLog
    (( DRYRUN )) && say "Dry run: every system-changing command is printed and nothing is run."
    checkSystem
    if [[ -n $PLAN ]]; then planRun; finish; return; fi
    case $ARG in
        '')        interactive ;;
        quick)     baseSetup; installGroup profile_basic "basic applications"; flatpakInstall "${flatpak_basic[@]}" "${flatpak_google[@]}" ;;
        simple)    baseSetup ;;
        server)    serverSetup ;;
        nvidia|amd|intel|drivers) repositoriesSetup; driversSetup ;;
        desktop)   desktopMenu force ;;
        hyprland)  carinoHyprland ;;
        distrobox) distroboxSetup ;;
        anydesk)   anydeskSetup ;;
        librewolf) librewolfSetup ;;
        share)     shareSetup ;;
        proton)    protonSetup ;;
        update)    updateSetup ;;
    esac
    finish
}
main
