#!/bin/bash
# shellcheck shell=bash disable=SC2034  # the package arrays in section 4 are read by name ("${!ref}")
# ==== 0. Header ====
# Carino SimpleSetup for macOS: checks the Mac, installs Homebrew and the base tools, offers a few
# Finder tweaks and the purpose profiles, then lists macOS updates. Written for the stock /bin/bash 3.2.
#
# Usage:
#   bash <(curl -s https://setup.carino.systems/macos.sh)              interactive
#   bash macos.sh dry-run                                               print every command, change nothing
#   CARINO_SETUP_PLAN=technical,tweaks,purpose=design,reboot=no bash macos.sh    unattended
# Plan tokens: technical update tweaks purpose=<name> reboot=yes|no
# Environment: CARINO_SETUP_DRYRUN=1, CARINO_SETUP_PLAN, CARINO_SETUP_LOG=<file>.
# Test hook: CARINO_SETUP_FAKE=1 (implies dry run) skips the macOS probes so the script runs anywhere;
#            CARINO_SETUP_MACOS=<version>, CARINO_SETUP_ARCH=arm64|x86_64, CARINO_SETUP_ROOT=1 shape the fake Mac.
# Licence: AGPL-3.0-or-later, see LICENSE. Source: https://github.com/MiguelCarino/SimpleSetup

# ==== 1. Settings ====
set -uo pipefail
DRYRUN=0
if [[ ${1:-} == dry-run || ${1:-} == --dry-run ]]; then DRYRUN=1; shift; fi
[[ ${CARINO_SETUP_DRYRUN:-0} == 1 ]] && DRYRUN=1
FAKE=${CARINO_SETUP_FAKE:-0}
[[ $FAKE == 1 ]] && DRYRUN=1
ARG=${1:-}
NARGS=$#
PLAN=${CARINO_SETUP_PLAN:-}
NONINTERACTIVE=0
[[ -n $PLAN || ! -t 0 ]] && NONINTERACTIVE=1
MIN_MACOS=15   # MACOS_OLDEST_SUPPORTED in Homebrew's install.sh (checked 2026-10)
BREW_INSTALLER=https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
LOG='' REBOOT='' DONE=' ' BREW='' OS_VER='' ARCH='' ROSETTA=no HAVE_CLT=no TWEAK_BAD=''
INSTALLED_F='' INSTALLED_C=''
RESULTS=() PLAN_TOKENS=()
NL='
'

# ==== 2. Helpers ====
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    C_B=$'\033[1;94m' C_G=$'\033[32m' C_Y=$'\033[33m' C_R=$'\033[31m' C_D=$'\033[2m' C_0=$'\033[0m'
else
    C_B='' C_G='' C_Y='' C_R='' C_D='' C_0=''
fi
say()    { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
ok()     { printf '%s ok%s %s\n' "$C_G" "$C_0" "$*"; }
warn()   { printf '%s !!%s %s\n' "$C_Y" "$C_0" "$*"; }
fail()   { printf '%s xx%s %s\n' "$C_R" "$C_0" "$*"; }
banner() { printf '\n%s==== %s ====%s\n' "$C_B" "$*" "$C_0"; }
record() { RESULTS+=("$1|$2"); }   # record ok|fail|skip "what"
have()   { command -v "$1" >/dev/null 2>&1; }
refuse() { fail "$1"; fail "This Mac was refused and nothing was installed."; exit 1; }

PLAIN_WORD='^[A-Za-z0-9_@%+=:,./~-]+$'
run() { # run <command...>: prints the command, runs it unless this is a dry run
    local tag='$' line='' a
    (( DRYRUN )) && tag='(dry-run) $'
    for a in "$@"; do
        if [[ $a =~ $PLAIN_WORD ]]; then line="$line$a "
        else line="$line$(printf '%q' "$a") "; fi
    done
    printf '%s   %s %s%s\n' "$C_D" "$tag" "${line% }" "$C_0"
    (( DRYRUN )) && return 0
    "$@"
}
appendLine() { # appendLine <file> <line>: the one file write this script does (the shell profile)
    printf '%s   %s append to %s: %s%s\n' "$C_D" "$( (( DRYRUN )) && echo '(dry-run)')" "$1" "$2" "$C_0"
    (( DRYRUN )) && return 0
    printf '\n%s\n' "$2" >>"$1"
}
ask() { # ask "question" default -> REPLY; takes the default under a plan or without a terminal
    if (( NONINTERACTIVE )); then REPLY=$2; say "$1 -> ${2:-<empty>} (default, non-interactive)"; return 0; fi
    read -r -p "$1 [$2] " REPLY || REPLY=$2
    [[ -n $REPLY ]] || REPLY=$2
}
confirm() { ask "$1 (y/n)" "$2"; [[ $REPLY =~ ^[Yy] ]]; }
once() { [[ $DONE == *" $1 "* ]] && return 1; DONE="$DONE$1 "; }   # once <key>: true the first time only

# ==== 3. checkSystem ====
fact() { printf '  %-17s %s\n' "$1" "$2"; }
probe() { # probe <fake value> <command...>: the command's output, or the fake value under CARINO_SETUP_FAKE
    if [[ $FAKE == 1 ]]; then printf '%s\n' "$1"; else "${@:2}" 2>/dev/null; fi
}
checkSystem() {
    local name build cpu model gpu laptop=no vm=no fv sip disk='unknown' net='not checked' free _
    [[ $FAKE == 1 || $(uname -s) == Darwin ]] || refuse "This is not macOS ($(uname -s)). On Linux use setup.sh."
    name=$(probe macOS sw_vers -productName)
    OS_VER=$(probe "${CARINO_SETUP_MACOS:-15.6}" sw_vers -productVersion)
    build=$(probe 24G84 sw_vers -buildVersion)
    ARCH=$(probe "${CARINO_SETUP_ARCH:-arm64}" uname -m)
    [[ $(probe 0 sysctl -n sysctl.proc_translated) == 1 ]] && ROSETTA=yes
    cpu=$(probe 'Apple M2' sysctl -n machdep.cpu.brand_string)
    model=$(probe Mac14,2 sysctl -n hw.model)
    gpu=$(probe 'Chipset Model: Apple M2' system_profiler SPDisplaysDataType | awk -F': ' '/Chipset Model/{print $2}' | paste -sd, -)
    probe '' pmset -g batt | grep -q InternalBattery && laptop=yes
    [[ $(probe 0 sysctl -n kern.hv_vmm_present) == 1 ]] && vm=yes
    fv=$(probe 'FileVault is On.' fdesetup status | head -n1)
    sip=$(probe 'System Integrity Protection status: enabled.' csrutil status | sed 's/^System Integrity Protection status: //')
    { read -r _; read -r _ _ _ free _; } < <(df -Pk "$HOME" 2>/dev/null) && [[ $free =~ ^[0-9]+$ ]] && disk="$((free / 1048576)) GiB free"
    if [[ $FAKE != 1 ]] && have curl; then
        if curl -sI --max-time 6 https://formulae.brew.sh >/dev/null 2>&1; then net=yes; else net=no; fi
    fi
    [[ $FAKE != 1 ]] && xcode-select -p >/dev/null 2>&1 && HAVE_CLT=yes
    findBrew
    banner "System"
    fact "macOS" "${name:-macOS} $OS_VER (build ${build:-?})"
    fact "Architecture" "$ARCH ($([[ $ARCH == arm64 ]] && echo 'Apple Silicon' || echo Intel)), Rosetta shell: $ROSETTA"
    fact "CPU" "${cpu:-unknown}"
    fact "Model" "${model:-unknown}"
    fact "GPU" "${gpu:-unknown}"
    fact "Laptop" "$laptop"
    fact "Virtual machine" "$vm"
    fact "FileVault" "${fv:-unknown}"
    fact "SIP" "${sip:-unknown}"
    fact "Disk (home)" "$disk"
    fact "Internet" "$net"
    fact "Xcode CLT" "$HAVE_CLT"
    fact "Homebrew" "${BREW:-not installed}"
    checkRefusals
}
checkRefusals() {
    local major=${OS_VER%%.*} root=0
    if [[ $FAKE == 1 ]]; then root=${CARINO_SETUP_ROOT:-0}; elif (( EUID == 0 )); then root=1; fi
    (( root )) && refuse "Do not run this as root or with sudo: Homebrew refuses root. Run it as your normal user; the tools ask for your password when they need it."
    [[ $major =~ ^[0-9]+$ ]] || refuse "Could not read the macOS version ('$OS_VER')."
    (( major >= MIN_MACOS )) || refuse "macOS $OS_VER is older than macOS $MIN_MACOS, the oldest version Homebrew supports. Update macOS first."
    [[ $ROSETTA == yes ]] && refuse "This shell runs under Rosetta (x86_64 on Apple Silicon). Open a native Terminal and run it again, so Homebrew installs to /opt/homebrew."
    if [[ $ARCH == x86_64 ]]; then
        [[ -n $BREW ]] || refuse "Intel Mac: Homebrew's installer now runs only on Apple Silicon, so nothing can be installed here."
        warn "Intel Mac: Homebrew has no Intel bottles any more, so every formula builds from source (slow), and some (podman) are Apple Silicon only."
    fi
    return 0
}

# ==== 4. Packages ====
# brew_<group> are formulae and cask_<group> are casks; every name was checked on formulae.brew.sh.
# basic goes with every purpose; google, microsoft, support and remote are shared app groups (see PURPOSES).
brew_base=( git git-lfs wget jq rsync rclone media-info nano htop fastfetch smartmontools gnupg tree ncdu tealdeer cmake sevenzip )
cask_base=( the-unarchiver )
brew_basic=( yt-dlp ffmpeg mpv )
cask_basic=( firefox libreoffice thunderbird vlc obs transmission handbrake-app )
cask_google=( google-chrome google-drive )
cask_microsoft=( microsoft-edge visual-studio-code microsoft-teams )
cask_support=( keepassxc hex-fiend windows-app )
cask_remote=( anydesk rustdesk )
brew_corporate=( openconnect )
cask_corporate=( onlyoffice webex activitywatch )
cask_gaming=( steam heroic discord )
brew_development=( gcc rust node python@3.14 go podman qemu )
cask_development=( podman-desktop )
brew_astronomy=( siril )
cask_astronomy=( stellarium kstars )
brew_compneuro=( nest numpy scipy python-matplotlib jupyterlab hdf5 )
cask_compneuro=( spyder )
brew_design=( imagemagick graphicsmagick optipng fontforge gmic )
cask_design=( gimp inkscape krita blender scribus kdenlive )
brew_music=( fluid-synth )
cask_music=( audacity mixxx musescore )
brew_cybersecurity=( nmap netcat john hydra aircrack-ng hashcat masscan binwalk yara sqlmap ghidra )
cask_cybersecurity=( wireshark-app )
brew_forensics=( sleuthkit testdisk foremost ddrescue exiftool libewf chkrootkit rkhunter binwalk yara )
brew_scientific=( octave gnuplot maxima wxmaxima r numpy scipy python-matplotlib jupyterlab gmsh )
cask_scientific=( paraview scilab basictex )
brew_robotics=( avrdude stlink dfu-util minicom picocom esptool platformio )
cask_robotics=( kicad freecad arduino-ide openscad@snapshot )
brew_imagenology=( dcmtk dcm2niix gdcm )
cask_imagenology=( weasis horos slicer )
# not on Homebrew or disabled there (fails Gatekeeper): darktable lmms hydrogen ardour zap invesalius autopsy

# purposes: "name|menu label|extra groups"; basic and the purpose's own group always install, the menu number is the position
PURPOSES=(
    "basic|Basic|google microsoft support remote"
    "gaming|Gaming|google microsoft support remote"
    "corporate|Corporate|google microsoft support remote"
    "corporate-microsoft|Corporate (Microsoft only)|microsoft support remote corporate"
    "corporate-google|Corporate (Google only)|google support remote corporate"
    "development|Development|google support remote"
    "astronomy|Astronomy|google support remote"
    "compneuro|Computational Neuroscience|support remote"
    "design|Design|support remote"
    "music|Music Production|support remote"
    "cybersecurity|Cybersecurity|support remote"
    "forensics|Forensics|support remote"
    "scientific|Scientific|support remote"
    "robotics|Robotics|development support remote"
    "imagenology|Medical Imaging (Imagenologia)|support remote"
)

# ==== 5. baseSetup ====
findBrew() {
    local p
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ $FAKE != 1 && -x $p ]] && { BREW=$p; return 0; }
    done
    BREW=''
}
brewEnv() { # puts brew on PATH now and offers to add it to the login shell's profile for new terminals
    local sh=${SHELL:-/bin/zsh} rc; sh=${sh##*/}   # zsh is the macOS default when SHELL is unset
    (( DRYRUN )) || eval "$("$BREW" shellenv bash)"
    [[ -e /etc/paths.d/homebrew ]] && return 0   # the installer already put brew on every shell's PATH
    case $sh in
        zsh)  rc=${ZDOTDIR:-$HOME}/.zprofile ;;
        bash) rc=$HOME/.bash_profile ;;
        *)    say "Add Homebrew to your $sh startup file yourself: $BREW shellenv $sh"; return 0 ;;
    esac
    grep -qs 'brew shellenv' "$rc" && return 0
    confirm "Add Homebrew to $rc so new terminals find it?" y && appendLine "$rc" "eval \"\$($BREW shellenv $sh)\""
}
installBrew() {
    if [[ -n $BREW ]]; then ok "Homebrew is installed: $BREW"; brewEnv; return 0; fi
    say "Installing Homebrew (it also installs the Xcode Command Line Tools when they are missing)."
    local tmp=/tmp/carino-brew-dry-run
    (( DRYRUN )) || tmp=$(mktemp -d) || return 1
    run curl -fsSL -o "$tmp/install.sh" "$BREW_INSTALLER" || return 1
    if (( NONINTERACTIVE )); then run env NONINTERACTIVE=1 /bin/bash "$tmp/install.sh" || return 1
    else run /bin/bash "$tmp/install.sh" || return 1; fi
    (( DRYRUN )) || rm -rf "$tmp"
    findBrew
    [[ -z $BREW ]] && (( DRYRUN )) && BREW=/opt/homebrew/bin/brew   # Homebrew installs only on Apple Silicon now
    [[ -n $BREW ]] || return 1
    brewEnv
}
loadInstalled() { # what brew already has, so installed names are skipped
    [[ -n $BREW && -x $BREW ]] || return 0
    INSTALLED_F=$("$BREW" list --formula -1 2>/dev/null)
    INSTALLED_C=$("$BREW" list --cask -1 2>/dev/null)
}
brewOne() { # brewOne formula|cask <name>: 0 installed or present, 1 failed
    local list=$INSTALLED_F
    [[ $1 == cask ]] && list=$INSTALLED_C
    [[ "$NL$list$NL" == *"$NL${2##*/}$NL"* ]] && { ok "$2 is already installed."; return 0; }
    if [[ $1 == cask ]]; then run "$BREW" install --cask "$2" --adopt || return 1   # --adopt: take over an app already in /Applications
    else run "$BREW" install --formula "$2" || return 1; fi
    if [[ $1 == cask ]]; then INSTALLED_C="$INSTALLED_C$NL$2"; else INSTALLED_F="$INSTALLED_F$NL$2"; fi
}
hasGroup() { declare -p "brew_${1//-/_}" >/dev/null 2>&1 || declare -p "cask_${1//-/_}" >/dev/null 2>&1; }
installGroup() { # installGroup <group> [label]: brew_<group> then cask_<group>, one name at a time, once per run
    local g=${1//-/_} label=${2:-$1} kind ref n bad='' count=0
    once "group:$g" || return 0
    [[ -n $BREW ]] || { record fail "$label (no Homebrew)"; return 1; }
    for kind in brew cask; do
        declare -p "${kind}_$g" >/dev/null 2>&1 || continue
        ref="${kind}_${g}[@]"
        for n in "${!ref}"; do
            count=$((count + 1))
            if [[ $kind == brew ]]; then brewOne formula "$n" || bad="$bad $n"; else brewOne cask "$n" || bad="$bad $n"; fi
        done
    done
    if (( count == 0 )); then say "Nothing on Homebrew for $label on macOS."; record skip "$label (nothing for macOS)"
    elif [[ -n $bad ]]; then record fail "$label:$bad"
    else record ok "$label"; fi
}
cltSetup() {
    [[ $HAVE_CLT == yes ]] && { ok "Xcode Command Line Tools are installed."; return 0; }
    [[ -z $BREW ]] && return 0   # the Homebrew installer installs them itself
    say "Xcode Command Line Tools are missing: a macOS dialog opens, finish it there."
    run xcode-select --install
    (( NONINTERACTIVE )) && warn "The Command Line Tools dialog needs someone at the Mac; builds that need them fail until it finishes."
    (( DRYRUN )) || ask "Press Return once the Command Line Tools installer has finished" ''
    if [[ $FAKE != 1 ]] && xcode-select -p >/dev/null 2>&1; then HAVE_CLT=yes; record ok "Xcode Command Line Tools"
    else record skip "Xcode Command Line Tools (installer dialog opened; run this again once it finishes)"; fi
}
rosettaSetup() {
    [[ $ARCH == arm64 ]] || return 0
    if [[ $FAKE != 1 ]] && arch -x86_64 /usr/bin/true 2>/dev/null; then ok "Rosetta 2 is installed."; return 0; fi
    confirm "Install Rosetta 2 (only needed by Intel-only apps)?" n || { record skip "Rosetta 2"; return 0; }
    if run softwareupdate --install-rosetta --agree-to-license; then record ok "Rosetta 2"; else record fail "Rosetta 2"; fi
}
brewReady() { # Homebrew itself, without the base tools: all that the profiles and update need
    once brew || { [[ -n $BREW ]]; return; }
    cltSetup
    if installBrew; then record ok "Homebrew"; else record fail "Homebrew"; fail "Homebrew is not available, so no package can be installed."; return 1; fi
    loadInstalled
    run "$BREW" update || warn "brew update failed; the cached package list is used."
}
baseSetup() {
    once base || return 0
    banner "Base setup"
    brewReady || return 1
    installGroup base "base tools"
    rosettaSetup
    driversNote
}

# ==== 6. Drivers ====
driversNote() { say "macOS ships its own drivers and firmware through Software Update; there is nothing to install here."; }

# ==== 7. Tweaks ====
setDefault() { # setDefault <domain> <key> <bool|string> <value>: writes only when the value differs; 0 changed, 1 already set, 2 failed
    local now; now=$(defaults read "$1" "$2" 2>/dev/null)
    [[ $3 == bool && $4 == true && $now == 1 ]] && return 1
    [[ $3 == string && $now == "$4" ]] && return 1
    run defaults write "$1" "$2" "-$3" "$4" && return 0
    TWEAK_BAD="$TWEAK_BAD $2"; return 2
}
tweaksSetup() { # tweaksSetup <default answer>: y when a plan named tweaks
    banner "Finder tweaks"
    confirm "Apply the Finder tweaks (show file extensions, path bar, no .DS_Store on network drives, screenshots folder)?" "$1" || { record skip "Finder tweaks"; return 0; }
    local finder=0 shots=$HOME/Pictures/Screenshots; TWEAK_BAD=""
    setDefault NSGlobalDomain AppleShowAllExtensions bool true && finder=1
    setDefault com.apple.finder ShowPathbar bool true && finder=1
    setDefault com.apple.desktopservices DSDontWriteNetworkStores bool true
    [[ -d $shots ]] || run mkdir -p "$shots" || TWEAK_BAD="$TWEAK_BAD mkdir-Screenshots"
    if setDefault com.apple.screencapture location string "$shots"; then run killall SystemUIServer || TWEAK_BAD="$TWEAK_BAD killall-SystemUIServer"; fi
    if (( finder )); then run killall Finder || TWEAK_BAD="$TWEAK_BAD killall-Finder"; fi
    if [[ -n $TWEAK_BAD ]]; then record fail "Finder tweaks:$TWEAK_BAD"; else record ok "Finder tweaks"; fi
}

# ==== 8. Profiles ====
purposeEntry() { # purposeEntry <name>: prints "name|label|groups"
    local e
    for e in "${PURPOSES[@]}"; do [[ ${e%%|*} == "$1" ]] && { printf '%s\n' "$e"; return 0; }; done
    return 1
}
installPurpose() {
    local entry name label groups g
    entry=$(purposeEntry "$1") || { fail "Unknown purpose '$1'."; return 1; }
    IFS='|' read -r name label groups <<<"$entry"
    banner "Purpose: $name ($label)"
    brewReady || return 1
    [[ $name == cybersecurity ]] && warn "Dual-use tools: use them only where you are allowed to."
    installGroup basic "basic applications"
    if hasGroup "$name"; then installGroup "$name" "$label packages"
    else say "$label has no list of its own; its applications come from the shared groups below."; fi
    for g in $groups; do installGroup "$g" "$g applications"; done
    return 0
}
profileMenu() {
    banner "Purpose profiles"
    local i=0 e n
    for e in "${PURPOSES[@]}"; do i=$((i + 1)); IFS='|' read -r _ n _ <<<"$e"; printf '  %2d) %s\n' "$i" "$n"; done
    ask "Profile numbers, several allowed, e.g. '2 6' (0 = none)" 1
    for n in $REPLY; do
        [[ $n == 0 ]] && return 0
        if [[ $n =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#PURPOSES[@]} )); then installPurpose "${PURPOSES[n - 1]%%|*}"
        else warn "'$n' is not a profile number, skipped."; fi
    done
}

# ==== 9. Updates ====
osUpdates() { # osUpdates <default answer>: lists macOS updates, installs them only on a yes
    banner "macOS updates"
    run softwareupdate -l
    confirm "Install every available macOS update now (some need a restart afterwards)?" "$1" || { record skip "macOS updates"; return 0; }
    if run sudo softwareupdate -i -a; then record ok "macOS updates"; else record fail "macOS updates"; fi
}
updateSetup() {
    banner "Homebrew upgrade"
    brewReady || return 1
    if run "$BREW" upgrade; then record ok "brew upgrade"; else record fail "brew upgrade"; fi
    osUpdates y
}

# ==== 10. Plan ====
planParse() { # validates every CARINO_SETUP_PLAN token before anything runs; one bad token refuses the plan
    local t bad=0 action=0 parts
    [[ -n $ARG ]] && { fail "CARINO_SETUP_PLAN cannot be combined with the argument '$ARG'. Nothing was run."; exit 2; }
    IFS=',' read -r -a parts <<<"${PLAN//$NL/,}"
    for t in ${parts[@]+"${parts[@]}"}; do
        t=${t//[[:space:]]/}
        [[ -n $t ]] || continue
        case $t in
            technical|update|tweaks) action=1 ;;
            purpose=*) if purposeEntry "${t#purpose=}" >/dev/null; then action=1
                       else fail "Unknown purpose in '$t'. Valid purposes: $(printf '%s ' "${PURPOSES[@]%%|*}")"; bad=1; fi ;;
            reboot=yes|reboot=no) ;;
            reboot=*) fail "reboot takes yes or no, not '${t#reboot=}'."; bad=1 ;;
            *) fail "Unknown plan token '$t'. Valid tokens: technical update tweaks purpose=<name> reboot=yes|no"; bad=1 ;;
        esac
        PLAN_TOKENS+=("$t")
    done
    (( action || bad )) || { fail "The plan has nothing to do."; bad=1; }
    (( bad )) && { fail "The plan was refused; nothing was run."; exit 2; }
    say "Plan accepted: ${PLAN_TOKENS[*]}"
}
sudoAhead() { # pkg casks (Windows App, Teams, Google Drive, Wireshark, BasicTeX, Spyder, Weasis) and softwareupdate need sudo midway
    [[ $FAKE != 1 ]] && sudo -n true 2>/dev/null && return 0
    if [[ ! -t 0 ]]; then
        warn "No terminal: the casks that run a macOS installer (Windows App, Teams, Google Drive, Wireshark, BasicTeX, Spyder, Weasis), the Homebrew install and macOS updates need sudo and fail unless it asks no password."
        return 0
    fi
    say "Some installers need your password: sudo asks once now and is kept fresh until the script ends, so the plan does not stop midway."
    run sudo -v || { warn "sudo was not unlocked; the installers that need it will ask or fail."; return 0; }
    (( DRYRUN )) || { while kill -0 $$ 2>/dev/null; do sudo -n -v; sleep 50; done >/dev/null 2>&1 & }
}
planRun() {
    local t
    sudoAhead
    for t in "${PLAN_TOKENS[@]}"; do
        say "Plan step: $t"
        case $t in
            technical) baseSetup ;;
            update)    updateSetup ;;
            tweaks)    tweaksSetup y ;;
            purpose=*) installPurpose "${t#purpose=}" ;;
            reboot=*)  REBOOT=${t#reboot=} ;;
        esac
    done
    say "CARINO_SETUP_PLAN has finished."
}

# ==== 11. Main ====
usage() {
    cat <<'EOF'
Usage: macos.sh [dry-run]
  (none)      interactive: check the Mac, Homebrew + base tools, Finder tweaks, purpose profiles, macOS updates
  dry-run     print every command, change nothing (also --dry-run or CARINO_SETUP_DRYRUN=1)
Unattended: CARINO_SETUP_PLAN=technical,update,tweaks,purpose=<name>,reboot=yes|no
EOF
}
openLog() {
    (( DRYRUN )) && [[ -z ${CARINO_SETUP_LOG:-} ]] && return 0
    LOG=${CARINO_SETUP_LOG:-carino-setup-$(date +%Y%m%d-%H%M%S).log}
    { : >>"$LOG"; } 2>/dev/null || LOG=/tmp/${LOG##*/}
    exec > >(tee >(sed "s/$(printf '\033')\[[0-9;]*m//g" >>"$LOG")) 2>&1
}
interactive() {
    if confirm "Run the base setup (Homebrew and the base tools)?" y; then baseSetup; else record skip "base setup"; fi
    tweaksSetup n
    profileMenu
    osUpdates n
}
finish() {
    banner "Summary"
    local r
    for r in ${RESULTS[@]+"${RESULTS[@]}"}; do printf '  %-5s %s\n' "${r%%|*}" "${r#*|}"; done
    (( ${#RESULTS[@]} )) || say "Nothing was installed."
    [[ -n $LOG ]] && say "Log: $LOG"
    (( DRYRUN )) && say "Dry run: nothing was changed."
    case $REBOOT in
        yes) run sudo shutdown -r now ;;
        no)  say "Restart: no (plan)." ;;
        *)   if confirm "Restart now?" n; then run sudo shutdown -r now; fi ;;
    esac
}
main() {
    (( NARGS <= 1 )) || { fail "Only one argument is accepted."; usage; exit 2; }
    case $ARG in
        '') ;;
        help|-h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
    [[ -n $PLAN ]] && planParse
    openLog
    (( DRYRUN )) && say "Dry run: every system-changing command is printed and nothing is run."
    checkSystem
    if [[ -n $PLAN ]]; then planRun; else interactive; fi
    finish
}
main
