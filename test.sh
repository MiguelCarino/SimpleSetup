#!/usr/bin/env bash
# SimpleSetup test harness: syntax, family detection for every supported distribution, plan validation,
# purposes, desktops, legacy arguments and the package tables. Everything runs setup.sh as a dry run.
# Usage: ./test.sh [--network]     (--network also asks Flathub about every Flatpak id)
# shellcheck disable=SC2034  # PASS/FAIL/RC are read inside the check strings, which shellcheck cannot see
cd "$(dirname "$0")" || exit 1
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf '  pass  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
head2() { printf '\n== %s\n' "$1"; }
check() { if eval "$2"; then pass "$1"; else bad "$1"; fi; }   # check "label" 'condition'
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
NETWORK=0; [[ ${1:-} == --network ]] && NETWORK=1

# setup <os-release file> [extra env...] -- [setup.sh args]: dry run with test hooks, sets OUT and RC
setup() {
    local osr=$1; shift
    local -a envs=()
    while (( $# )) && [[ $1 != -- ]]; do envs+=("$1"); shift; done
    [[ ${1:-} == -- ]] && shift
    OUT=$(env CARINO_SETUP_OSRELEASE="$osr" CARINO_SETUP_NET=0 CARINO_SETUP_ATOMIC=0 CARINO_SETUP_VIRT=none \
        CARINO_SETUP_GPU="nvidia amd intel" CARINO_SETUP_NVGEN=open CARINO_SETUP_DRYRUN=1 XDG_CURRENT_DESKTOP= \
        "${envs[@]}" timeout 60 bash setup.sh "$@" </dev/null 2>&1)
    RC=$?
}
clean() { ! grep -qE 'unbound variable|command not found|syntax error|bad substitution|bad array subscript' <<<"$OUT"; }
commands() { grep -cE '^ +\(dry-run\) \$ ' <<<"$OUT"; }

head2 "1. Syntax and shellcheck"
for f in setup.sh test.sh tools/check-packages.sh macos.sh; do
    check "$f parses" 'bash -n "$f" 2>/dev/null'
done
SC=$(command -v shellcheck || echo ~/.local/bin/shellcheck)
if [[ -x $SC ]]; then check "shellcheck -S warning is clean" '"$SC" -S warning setup.sh test.sh tools/check-packages.sh >/dev/null'
else printf '  skip  shellcheck not installed\n'; fi

head2 "2. Every family: detection, package manager line, Carino Hyprland support"
fixture() { printf '%s\n' "${@:2}" > "$WORK/$1"; }
fixture fedora44     'NAME="Fedora Linux"' 'VERSION="44 (Workstation Edition)"' 'ID=fedora' 'VERSION_ID=44' 'PRETTY_NAME="Fedora Linux 44 (Workstation Edition)"'
fixture silverblue44 'NAME="Fedora Linux"' 'VERSION="44.20261001.0 (Silverblue)"' 'ID=fedora' 'VERSION_ID=44' 'VARIANT_ID=silverblue' 'PRETTY_NAME="Fedora Linux 44.20261001.0 (Silverblue)"'
fixture alma10       'NAME="AlmaLinux"' 'VERSION="10.0 (Purple Lion)"' 'ID="almalinux"' 'ID_LIKE="rhel centos fedora"' 'VERSION_ID="10.0"' 'PRETTY_NAME="AlmaLinux 10.0 (Purple Lion)"'
fixture debian13     'PRETTY_NAME="Debian GNU/Linux 13 (trixie)"' 'NAME="Debian GNU/Linux"' 'VERSION_ID="13"' 'VERSION="13 (trixie)"' 'VERSION_CODENAME=trixie' 'ID=debian'
fixture debian12     'PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"' 'NAME="Debian GNU/Linux"' 'VERSION_ID="12"' 'VERSION="12 (bookworm)"' 'VERSION_CODENAME=bookworm' 'ID=debian'
fixture ubuntu2404   'PRETTY_NAME="Ubuntu 24.04.3 LTS"' 'NAME="Ubuntu"' 'VERSION_ID="24.04"' 'VERSION_CODENAME=noble' 'ID=ubuntu' 'ID_LIKE=debian' 'UBUNTU_CODENAME=noble'
fixture mint22       'NAME="Linux Mint"' 'VERSION="22 (Wilma)"' 'ID=linuxmint' 'ID_LIKE="ubuntu debian"' 'PRETTY_NAME="Linux Mint 22"' 'VERSION_ID="22"' 'VERSION_CODENAME=wilma' 'UBUNTU_CODENAME=noble'
fixture pop2404      'NAME="Pop!_OS"' 'VERSION="24.04 LTS"' 'ID=pop' 'ID_LIKE="ubuntu debian"' 'PRETTY_NAME="Pop!_OS 24.04 LTS"' 'VERSION_ID="24.04"' 'VERSION_CODENAME=noble' 'UBUNTU_CODENAME=noble'
fixture arch         'NAME="Arch Linux"' 'PRETTY_NAME="Arch Linux"' 'ID=arch' 'BUILD_ID=rolling'
fixture manjaro      'NAME="Manjaro Linux"' 'PRETTY_NAME="Manjaro Linux"' 'ID=manjaro' 'ID_LIKE=arch' 'BUILD_ID=rolling'
fixture cachyos      'NAME="CachyOS Linux"' 'PRETTY_NAME="CachyOS"' 'ID=cachyos' 'ID_LIKE=arch' 'BUILD_ID=rolling'
fixture steamos      'NAME="SteamOS"' 'PRETTY_NAME="SteamOS"' 'VERSION_CODENAME=holo' 'ID=steamos' 'ID_LIKE=arch' 'VERSION_ID=3.7.13'
fixture tumbleweed   'NAME="openSUSE Tumbleweed"' 'ID="opensuse-tumbleweed"' 'ID_LIKE="opensuse suse"' 'VERSION_ID="20261015"' 'PRETTY_NAME="openSUSE Tumbleweed"'
fixture leap16       'NAME="openSUSE Leap"' 'VERSION="16.0"' 'ID="opensuse-leap"' 'ID_LIKE="suse opensuse"' 'VERSION_ID="16.0"' 'PRETTY_NAME="openSUSE Leap 16.0"'
fixture solus        'NAME="Solus"' 'VERSION="4.7"' 'ID="solus"' 'VERSION_ID="4.7"' 'PRETTY_NAME="Solus 4.7 Endurance"'
fixture alpine       'NAME="Alpine Linux"' 'ID=alpine' 'VERSION_ID=3.22.2' 'PRETTY_NAME="Alpine Linux v3.22"'
fixture void         'NAME="Void"' 'ID="void"' 'PRETTY_NAME="Void Linux"'
fixture gentoo       'NAME=Gentoo' 'ID=gentoo' 'PRETTY_NAME="Gentoo Linux"' 'VERSION_ID="2.18"'
fixture mageia9      'NAME="Mageia"' 'VERSION="9"' 'ID="mageia"' 'ID_LIKE="mandriva fedora"' 'VERSION_ID="9"' 'PRETTY_NAME="Mageia 9"'
fixture nixos        'NAME=NixOS' 'ID=nixos' 'VERSION_ID="25.11"' 'PRETTY_NAME="NixOS 25.11 (Xantusia)"'
# fixture|extra env|family|install command prefix|carino hyprland (yes/no)
while IFS='|' read -r fx extra fam pm hypr; do
    [[ -n $fx ]] || continue
    setup "$WORK/$fx" ${extra:+"$extra"} CARINO_SETUP_PLAN=technical,purpose=basic,hyprland
    check "$fx: exits 0 and prints no shell error" '(( RC == 0 )) && clean'
    check "$fx: family $fam" 'grep -qE "^ +Family +$fam\$" <<<"$OUT"'
    check "$fx: package manager '$pm'" 'grep -qF "Package manager   $pm" <<<"$OUT"'
    check "$fx: an install command is printed" 'grep -qE "^ +\(dry-run\) \\$ (sudo )?$(sed "s/[.]/\\\\./g" <<<"$pm") " <<<"$OUT"'
    if [[ $hypr == yes ]]; then check "$fx: Carino Hyprland is installed" 'grep -q "Installing Carino Hyprland packages" <<<"$OUT"'
    else check "$fx: Carino Hyprland is declined with a reason" 'grep -q "Carino Hyprland is not available here: ." <<<"$OUT"'; fi
done <<'FAMILIES'
fedora44||fedora|dnf -y install --skip-unavailable|yes
silverblue44|CARINO_SETUP_ATOMIC=1|atomic|rpm-ostree install --idempotent --allow-inactive|no
alma10||rhel|dnf -y install --setopt=strict=0|no
debian13||debian|env DEBIAN_FRONTEND=noninteractive apt-get -y install|yes
debian12||debian|env DEBIAN_FRONTEND=noninteractive apt-get -y install|no
ubuntu2404||ubuntu|env DEBIAN_FRONTEND=noninteractive apt-get -y install|yes
mint22||ubuntu|env DEBIAN_FRONTEND=noninteractive apt-get -y install|yes
pop2404||ubuntu|env DEBIAN_FRONTEND=noninteractive apt-get -y install|yes
arch||arch|pacman -S --needed --noconfirm|yes
manjaro||arch|pacman -S --needed --noconfirm|yes
cachyos||arch|pacman -S --needed --noconfirm|yes
tumbleweed||opensuse|zypper -n install --auto-agree-with-licenses|yes
leap16||opensuse|zypper -n install --auto-agree-with-licenses|no
solus||solus|eopkg -y it|yes
alpine||alpine|apk add|no
void||void|xbps-install -y|no
gentoo||gentoo|emerge --noreplace --quiet-build|no
mageia9||mageia|dnf -y install --setopt=strict=0|no
FAMILIES
setup "$WORK/debian13" CARINO_SETUP_PLAN=hyprland
check "debian13: Hyprland comes from trixie-backports" 'grep -qE "apt-get -y install -t trixie-backports hyprland" <<<"$OUT"'
setup "$WORK/ubuntu2404" CARINO_SETUP_PLAN=hyprland
check "ubuntu2404: the cppiber PPA is added" 'grep -q "add-apt-repository -y ppa:cppiber/hyprland" <<<"$OUT"'
setup "$WORK/fedora44" CARINO_SETUP_PLAN=hyprland
check "fedora44: the lionheartp COPR is enabled" 'grep -q "copr enable lionheartp/Hyprland" <<<"$OUT"'
setup "$WORK/fedora44" CARINO_SETUP_NVGEN=580 CARINO_SETUP_PLAN=drivers
check "fedora44 + Pascal: the 580xx akmod is chosen" 'grep -q "akmod-nvidia-580xx" <<<"$OUT"'
setup "$WORK/debian13" CARINO_SETUP_NVGEN=580 CARINO_SETUP_PLAN=drivers
check "debian13 + Pascal: the proprietary DKMS module, not the open one" 'grep -q "nvidia-kernel-dkms" <<<"$OUT" && ! grep -q "nvidia-open-kernel-dkms" <<<"$OUT"'
setup "$WORK/arch" CARINO_SETUP_NVGEN=580 CARINO_SETUP_PLAN=drivers
check "arch + Pascal: says AUR only and installs no NVIDIA package" 'grep -q "AUR only" <<<"$OUT" && ! grep -q "nvidia-open-dkms" <<<"$OUT"'
setup "$WORK/fedora44" CARINO_SETUP_VIRT=kvm CARINO_SETUP_PLAN=technical
check "fedora44 in a VM: guest tools, no GPU driver, no microcode" 'grep -q "qemu-guest-agent" <<<"$OUT" && ! grep -qE "akmod-nvidia|ucode" <<<"$OUT"'
for fx in nixos steamos; do
    setup "$WORK/$fx" CARINO_SETUP_PLAN=technical
    check "$fx: refused, exit 1, no command printed" '(( RC == 1 )) && grep -q "refused and nothing was installed" <<<"$OUT" && (( $(commands) == 0 ))'
done
check "nixos: the configuration.nix snippet is printed" 'grep -q "programs.hyprland.enable = true;" <<<"$OUT" || { setup "$WORK/nixos" CARINO_SETUP_PLAN=technical; grep -q "programs.hyprland.enable = true;" <<<"$OUT"; }'
fixture unknown 'NAME="Plan 9"' 'ID=plan9'
setup "$WORK/unknown" CARINO_SETUP_PLAN=technical
check "unknown distribution: refused and named" '(( RC == 1 )) && grep -q "ID=plan9" <<<"$OUT" && (( $(commands) == 0 ))'

head2 "3. Plan validation"
setup "$WORK/fedora44" CARINO_SETUP_PLAN=technical,desktop=kde,purpose=gaming,reboot=no
check "a good plan is accepted and finishes" '(( RC == 0 )) && grep -q "Plan accepted" <<<"$OUT" && grep -q "CARINO_SETUP_PLAN has finished" <<<"$OUT"'
check "plan steps run left to right" '[[ $(grep -oE "Plan step: [a-z=-]+" <<<"$OUT" | cut -d" " -f3 | tr "\n" ,) == technical,desktop=kde,purpose=gaming,reboot=no, ]]'
setup "$WORK/fedora44" "CARINO_SETUP_PLAN=technical
purpose=basic"
check "a newline-separated plan is accepted" '(( RC == 0 )) && grep -q "Plan step: purpose=basic" <<<"$OUT"'
for p in technical,bogus desktop=bogus purpose=bogus reboot=maybe reboot=yes 'purpose=gaming,,frobnicate'; do
    setup "$WORK/fedora44" "CARINO_SETUP_PLAN=$p"
    check "bad plan '$p' is refused before anything runs" '(( RC == 2 )) && grep -q "nothing was run" <<<"$OUT" && (( $(commands) == 0 ))'
done
setup "$WORK/fedora44" CARINO_SETUP_PLAN=technical -- quick
check "a plan plus an argument is refused" '(( RC == 2 )) && grep -q "cannot be combined" <<<"$OUT" && (( $(commands) == 0 ))'
setup "$WORK/fedora44" CARINO_SETUP_PLAN=purpose=basic,reboot=yes
check "reboot=yes reboots at the end" 'grep -qE "\\$ sudo reboot$" <<<"$OUT"'
setup "$WORK/fedora44" CARINO_SETUP_PLAN=purpose=basic
check "no reboot token: the reboot question defaults to no" 'grep -q "Reboot now? (y/n) -> n" <<<"$OUT" && ! grep -q "sudo reboot" <<<"$OUT"'
setup "$WORK/fedora44" CARINO_SETUP_PLAN=desktop=carino-hyprland
check "desktop=carino-hyprland installs Carino Hyprland" 'grep -q "Installing Carino Hyprland packages" <<<"$OUT"'

head2 "4. Every purpose maps to its packages and Flatpaks"
PURPOSES="basic gaming corporate corporate-microsoft corporate-google development astronomy compneuro design music cybersecurity forensics scientific robotics imagenology"
for p in $PURPOSES; do
    for fx in fedora44 debian13; do
        setup "$WORK/$fx" "CARINO_SETUP_PLAN=purpose=$p"
        check "$fx purpose=$p: banner, native install and Flatpak install" '(( RC == 0 )) && clean && grep -q "Purpose: $p " <<<"$OUT" && grep -q "flatpak install -y --noninteractive flathub" <<<"$OUT" && grep -qE "apt-get -y install|dnf -y install" <<<"$OUT"'
    done
done
check "the menu lists 15 purposes in order" '[[ $(bash -c "source <(awk \"/^PURPOSES=\\(/,/^\\)/\" setup.sh); printf \"%s \" \"\${PURPOSES[@]%%|*}\"") == "$PURPOSES " ]]'

head2 "5. Every desktop name is accepted"
for d in gnome xfce kde lxqt cinnamon mate i3 openbox budgie sway hyprland niri none carino-hyprland; do
    setup "$WORK/arch" "CARINO_SETUP_PLAN=desktop=$d"
    check "arch desktop=$d runs" '(( RC == 0 )) && clean && { [[ $d == none ]] || grep -q "pacman -S --needed --noconfirm" <<<"$OUT"; }'
done

head2 "6. Legacy arguments"
for a in quick simple server nvidia amd intel drivers desktop hyprland distrobox anydesk librewolf share proton update; do
    setup "$WORK/fedora44" -- "$a"
    check "argument '$a' runs to the end" '(( RC == 0 )) && clean && grep -q "Summary" <<<"$OUT"'
done
setup "$WORK/fedora44" -- frobnicate
check "an unknown argument prints the usage and exits 2" '(( RC == 2 )) && grep -q "^Usage:" <<<"$OUT"'
setup "$WORK/fedora44" -- help
check "help prints the usage and exits 0" '(( RC == 0 )) && grep -q "^Usage:" <<<"$OUT"'
OUT=$(CARINO_SETUP_OSRELEASE="$WORK/fedora44" CARINO_SETUP_NET=0 CARINO_SETUP_GPU=intel timeout 60 bash setup.sh --dry-run simple </dev/null 2>&1); RC=$?
check "--dry-run as the first argument works" '(( RC == 0 )) && grep -q "(dry-run) \\$" <<<"$OUT"'
OUT=$(CARINO_SETUP_OSRELEASE="$WORK/fedora44" CARINO_SETUP_NET=0 CARINO_SETUP_GPU=intel timeout 60 bash setup.sh dry-run </dev/null 2>&1); RC=$?
check "no argument, no terminal: interactive flow takes every default and ends" '(( RC == 0 )) && clean && grep -q "Purpose: basic " <<<"$OUT" && grep -q "Install the Carino Hyprland desktop configuration? (y/n) -> n" <<<"$OUT"'

head2 "7. Package tables"
RX='^([a-z0-9_]+)_(fedora|atomic|rhel|debian|ubuntu|arch|opensuse|solus|alpine|void|gentoo|mageia)=\('
TABLES=$(awk '/^# ==== 4\./,/^# ==== 5\./' setup.sh)
has() { grep -qE "^$1=\\(" <<<"$TABLES"; }   # has <array name>
check "section 4 holds only assignments and comments" '! grep -vE "^(#.*|[A-Za-z0-9_]+=\\(.*\\)|[A-Za-z0-9_]+=\\(|    \".*\"|\\)|)$" <<<"$TABLES" | grep -q .'
check "every package array follows <group>_<family> or is a known table" '! grep -oE "^[A-Za-z0-9_]+=\\(" <<<"$TABLES" | tr -d "=(" | grep -vE "^(flatpak_[a-z]+|GUEST_[A-Z]+|DESKTOP_NAMES|PURPOSES)$" | while read -r n; do grep -qE "$RX" <<<"$n=(" || echo "$n"; done | grep .'
check "no package name is a glob" '! grep -E "$RX" <<<"$TABLES" | grep -q "\\*"'
check "no array is empty" '! grep -qE "=\\( *\\)" <<<"$TABLES"'
dups=$(grep -E "$RX|^flatpak_" <<<"$TABLES" | while read -r l; do n=${l%%=*}; d=$(sed -E "s/^[^(]*\\(//; s/\\).*//" <<<"$l" | tr " " "\n" | sed "/^$/d" | sort | uniq -d | tr "\n" " "); [[ -n $d ]] && echo "$n: $d"; done)
check "no array names a package twice${dups:+ ($dups)}" '[[ -z $dups ]]'
for g in $(grep -oE 'installGroup [a-z0-9_]+' setup.sh | awk '{print $2}' | sort -u); do
    check "installGroup $g has at least one family array" 'grep -qE "^${g}_[a-z]+=\\(" <<<"$TABLES"'
done
for p in $PURPOSES; do
    n=profile_${p//-/_}
    case $p in corporate-microsoft|corporate-google) check "$p has no native list on purpose (Flatpaks only)" '! has ${n}_fedora' ;;
        *) check "$n exists for fedora and debian" 'has ${n}_fedora && has ${n}_debian' ;; esac
    for g in $(grep -E "^ +\"$p\|" <<<"$TABLES" | cut -d'|' -f3 | tr -d '"'); do check "$p Flatpak group flatpak_$g exists" 'has flatpak_$g'; done
done
for d in gnome xfce kde lxqt cinnamon mate i3 openbox budgie sway hyprland niri; do
    check "desktop_$d exists for fedora, debian (not niri), arch and opensuse" 'has desktop_${d}_fedora && { [[ $d == niri ]] || has desktop_${d}_debian; } && has desktop_${d}_arch && has desktop_${d}_opensuse'
done
for f in fedora arch opensuse debian solus; do check "hypr_$f exists (Carino Hyprland family)" 'has hypr_$f'; done
for g in nvidia nvidia580; do for f in fedora debian opensuse; do check "drivers_${g}_$f exists" 'has drivers_${g}_$f'; done; done
for f in fedora rhel debian arch opensuse alpine; do check "base, codecs or firmware exist for $f" 'has base_$f && has firmware_$f'; done
if [[ -r hyprland/packages.txt ]]; then
    missing=$(sed 's/#.*//' hyprland/packages.txt | xargs -n1 2>/dev/null | while read -r p; do grep -E "^hypr_fedora=\\(" <<<"$TABLES" | grep -qw -- "$p" || echo "$p"; done | tr "\n" " ")
    check "every name in hyprland/packages.txt is in hypr_fedora${missing:+ (missing: $missing)}" '[[ -z $missing ]]'
    extra=$(grep -E "^hypr_fedora=\\(" <<<"$TABLES" | sed -E "s/^[^(]*\\(//; s/\\).*//" | xargs -n1 | while read -r p; do sed 's/#.*//' hyprland/packages.txt | grep -qw -- "$p" || echo "$p"; done | tr "\n" " ")
    check "every name in hypr_fedora is in hyprland/packages.txt${extra:+ (extra: $extra)}" '[[ -z $extra ]]'
fi

if (( NETWORK )); then
    head2 "8. Flathub ids (network)"
    for id in $(grep -E '^flatpak_' setup.sh | sed -E 's/^[^(]*\(//; s/\).*//' | tr ' ' '\n' | sed '/^$/d' | sort -u); do
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://flathub.org/api/v2/appstream/$id")
        check "Flathub $id (HTTP $code)" '[[ $code == 200 ]]'
    done
fi

# ---- macOS (macos.sh) ---- runs macos.sh with CARINO_SETUP_FAKE=1 (a dry run that skips the macOS probes)
head2 "9. macOS: macos.sh under a fake Mac"
mac() { OUT=$(env CARINO_SETUP_FAKE=1 "$@" timeout 60 bash macos.sh </dev/null 2>&1); RC=$?; }   # mac [env...]
MAC_FORBIDDEN='declare -[aAgilrtux]*[An]|local -[a-z]*[An]|mapfile|readarray|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^|,|\^)\}|;;&|;&|\[-[0-9]+\]|\$\{[A-Za-z_][A-Za-z0-9_]*: -[0-9]|&>>|\|&|coproc|\$\{![A-Za-z_]+@\}'
mac_bad=$(sed 's/^[[:space:]]*#.*//' macos.sh | grep -nE "$MAC_FORBIDDEN")
check "macos.sh uses no bash 4+ construct${mac_bad:+ ($mac_bad)}" '[[ -z $mac_bad ]]'
if [[ -x $SC ]]; then check "macos.sh: shellcheck -S warning --shell=bash is clean" '"$SC" -S warning --shell=bash macos.sh >/dev/null'; fi
mac CARINO_SETUP_PLAN=technical,tweaks,update,reboot=no
check "a good plan is accepted and finishes" '(( RC == 0 )) && clean && grep -q "Plan accepted" <<<"$OUT" && grep -q "CARINO_SETUP_PLAN has finished" <<<"$OUT"'
check "technical installs Homebrew non-interactively, then the base tools" 'grep -q "env NONINTERACTIVE=1 /bin/bash" <<<"$OUT" && grep -q "brew install --formula git$" <<<"$OUT" && grep -q "brew install --cask the-unarchiver" <<<"$OUT"'
check "tweaks in a plan write the Finder defaults" 'grep -q "defaults write com.apple.finder ShowPathbar -bool true" <<<"$OUT" && grep -q "killall Finder" <<<"$OUT"'
check "update upgrades brew and lists macOS updates" 'grep -q "brew upgrade" <<<"$OUT" && grep -q "softwareupdate -l" <<<"$OUT"'
check "the Apple Silicon prefix is /opt/homebrew" 'grep -q "/opt/homebrew/bin/brew install" <<<"$OUT"'
mac CARINO_SETUP_ARCH=x86_64 CARINO_SETUP_PLAN=technical
check "Intel without Homebrew is refused (the installer runs only on Apple Silicon)" '(( RC == 1 )) && grep -q "Intel Mac" <<<"$OUT" && (( $(commands) == 0 ))'
mac CARINO_SETUP_PLAN=purpose=design
check "a purpose alone needs Homebrew, not the base tools; casks adopt existing apps" '(( RC == 0 )) && ! grep -q "install --formula git$" <<<"$OUT" && grep -q "install --cask gimp --adopt" <<<"$OUT"'
for p in technical,bogus purpose=bogus reboot=maybe drivers 'purpose=gaming,,frobnicate'; do
    mac "CARINO_SETUP_PLAN=$p"
    check "macOS: bad plan '$p' is refused before anything runs" '(( RC == 2 )) && grep -q "nothing was run" <<<"$OUT" && (( $(commands) == 0 ))'
done
OUT=$(CARINO_SETUP_FAKE=1 CARINO_SETUP_PLAN=technical timeout 60 bash macos.sh extra </dev/null 2>&1); RC=$?
check "macOS: a plan plus an argument is refused" '(( RC == 2 )) && (( $(commands) == 0 ))'
mac CARINO_SETUP_MACOS=14.7 CARINO_SETUP_PLAN=technical
check "macOS 14 is refused (older than Homebrew supports)" '(( RC == 1 )) && grep -q "older than macOS 15" <<<"$OUT" && (( $(commands) == 0 ))'
mac CARINO_SETUP_ROOT=1 CARINO_SETUP_PLAN=technical
check "running as root is refused" '(( RC == 1 )) && grep -q "Homebrew refuses root" <<<"$OUT" && (( $(commands) == 0 ))'
for p in $PURPOSES; do
    mac "CARINO_SETUP_PLAN=purpose=$p"
    check "macOS purpose=$p: banner and brew installs" '(( RC == 0 )) && clean && grep -q "Purpose: $p " <<<"$OUT" && grep -q "brew install --" <<<"$OUT" && ! grep -q "^  fail" <<<"$OUT"'
done
mac
check "macOS, no terminal: the interactive flow takes every default and ends" '(( RC == 0 )) && clean && grep -q "Purpose: basic " <<<"$OUT" && grep -q "screenshots folder)? (y/n) -> n" <<<"$OUT" && grep -q "Restart now? (y/n) -> n" <<<"$OUT"'
OUT=$(CARINO_SETUP_FAKE=1 timeout 60 bash macos.sh --bogus </dev/null 2>&1); RC=$?
check "macOS: an unknown argument prints the usage and exits 2" '(( RC == 2 )) && grep -q "^Usage:" <<<"$OUT"'
MAC_TABLES=$(awk '/^# ==== 4\./,/^# ==== 5\./' macos.sh)
MAC_GROUPS="base basic google microsoft support remote ${PURPOSES//-/_}"
mac_odd=$(grep -oE '^[a-z_]+=\(' <<<"$MAC_TABLES" | tr -d '=(' | while read -r n; do
    [[ $n == PURPOSES ]] && continue
    [[ $n =~ ^(brew|cask)_(.+)$ && " $MAC_GROUPS " == *" ${BASH_REMATCH[2]} "* ]] || echo "$n"; done | tr '\n' ' ')
check "every macOS array is brew_<group> or cask_<group>${mac_odd:+ ($mac_odd)}" '[[ -z $mac_odd ]]'
mac_dups=$(grep -E '^(brew|cask)_' <<<"$MAC_TABLES" | while read -r l; do d=$(sed -E 's/^[^(]*\(//; s/\).*//' <<<"$l" | tr ' ' '\n' | sed '/^$/d' | sort | uniq -d | tr '\n' ' '); [[ -n $d ]] && echo "${l%%=*}: $d"; done)
check "no macOS array names a package twice${mac_dups:+ ($mac_dups)}" '[[ -z $mac_dups ]]'
check "the macOS menu lists the same 15 purposes in order" '[[ $(bash -c "source <(awk \"/^PURPOSES=\\(/,/^\\)/\" macos.sh); printf \"%s \" \"\${PURPOSES[@]%%|*}\"") == "$PURPOSES " ]]'
if command -v podman >/dev/null && podman image exists docker.io/library/bash:3.2 2>/dev/null; then
    OUT=$(podman run --rm -v "$PWD:/r:ro,Z" -w /tmp -e CARINO_SETUP_FAKE=1 -e CARINO_SETUP_PLAN=technical,tweaks,update,purpose=robotics,purpose=corporate-google,reboot=no \
        docker.io/library/bash:3.2 bash /r/macos.sh </dev/null 2>&1); RC=$?
    check "macos.sh runs under bash 3.2 (container)" '(( RC == 0 )) && clean && grep -q "CARINO_SETUP_PLAN has finished" <<<"$OUT"'
else printf '  skip  bash 3.2 run (podman pull docker.io/library/bash:3.2 to enable)\n'; fi
# ---- end macOS ----

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
