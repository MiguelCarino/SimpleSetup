#!/bin/bash
# carino-probe.sh - Carino Systems fleet capability probe. Save this file as UTF-8.
#
# A general FACT PROVIDER for fleet shell scripts. It answers questions about the machine;
# it never acts on the answers. Sourced, self-contained, safe to source twice, and cheap to
# source: sourcing defines functions and nothing else, no network, no forks, no file writes.
#
#   . ./carino-probe.sh
#   carino_probe os.family                 # fedora
#   carino_probe_int mem.total.mb          # 31984
#   carino_probe_has boot.uefi             # exit 0 when the machine booted UEFI
#   carino_probe_load net.speed.bps        # resolve here, print nothing (see below)
#   carino_probe_report                    # every cheap fact, one per line
#   carino_probe_parallel_flags            # the dnf flags this link can actually sustain
#
# The one thing a caller has to know: $( ) is a SUBSHELL, so a fact resolved inside one is
# memoised into a variable that dies when the substitution closes. Reading four net.* keys as
# four $(carino_probe ...) calls therefore downloads 8 MiB four times. Call carino_probe_load
# once in your own shell first and every subsequent read of that key is free.
#
# Three tiers, so a caller never pays for a fact it did not ask for:
#   A  cheap + eager  - resolved on the first carino_probe call, one fork at most (uname)
#   B  cheap + lazy   - one fork on first query of that key, then memoised for the process
#   C  expensive      - the bandwidth measurement, only ever on an explicit key request
#
# Contract with the caller: values are bare tokens or bare integers, never units, never
# thousands separators, never colour. "unknown" is a first-class value and EVERY caller has
# to handle it. The probe REPORTS, the caller DECIDES - no helper in this file executes a
# package manager, writes a config file, prompts, or elevates.
#
# Dry-run safety, which is why several obvious implementations are not used below:
# setup.sh's enableDryRun puts a PATH shim in front of mkdir, rm, cp, mv, ln, tar, chmod,
# tee and sed that only echoes "DRY-RUN: ...". So this file never calls sed (a pipeline
# through it prints the shim banner instead of the value), never calls mkdir or tee, and
# keeps no disk cache at all - memoisation lives in shell variables only. Detection commands
# (curl, grep, cut, awk, tr, df, uname, lspci, nmcli) are deliberately left real by that
# shim, so everything this file does run behaves identically in a rehearsal.
#
# Environment knobs, all read at use time, none required:
#   CARINO_PROBE_NET=0|1        0 forbids the bandwidth probe outright, 1 permits it even
#                               under NONINTERACTIVE/DRYRUN (default: permitted only in a
#                               normal interactive run)
#   CARINO_PROBE_NET_MAXSEC     hard wall-clock ceiling for the whole Tier C operation (25)
#   CARINO_PROBE_MIRROR_URL     skip mirror discovery and measure this exact URL instead;
#                               for air-gapped mirrors and for testing the offline path
#   CARINO_SETUP_OSRELEASE      honoured for os.* so test harnesses can drive other families
#
# This file has NO dependency on carino-term.sh. If carino_kv happens to be defined,
# carino_probe_report uses it; otherwise it falls back to printf. The dependency is one-way
# and optional on purpose - two files that source each other is a trap.

CARINO_PROBE_LIB=1 # a marker for the caller, not a guard; re-sourcing this file is harmless because every definition is idempotent and the memoised CARINO_PROBE_* values survive it
: "${_CARINO_PROBE_TIERA:=0}"                  # every global this file touches is seeded HERE rather than on first use, because a sibling fleet script running under set -u aborts on the first unset read and "unbound variable" is one of the five strings test.sh:147 fails an entire run for
declare -p _CARINO_PROBE_KEYS >/dev/null 2>&1 || _CARINO_PROBE_KEYS=() # guarded so a second source does not wipe the registry of already-resolved facts
_cpVar=""; _cpOut=""; _cpStr=""; _cpNum=0; _cpUsec=0; _cpMirror=""; _cpBps=0; _cpRtt=""; _cpSize=0; _cpParN=0; _cpParWhy=""

# ---------------------------------------------------------------------------
# Internals: memoisation
# ---------------------------------------------------------------------------
# One shell variable per fact, plus a parallel _SET marker so a legitimately empty value is
# not re-probed forever. Never exported: a child re-run of setup.sh must re-probe, because
# the machine's state (a battery unplugged, a network changed) may have moved under it.

_carinoProbeKeyVar () # sets _cpVar to the memo variable name for KEY [ARG]; no fork, this runs on every single lookup
{
    local k="$1$2"
    k="${k//[^a-zA-Z0-9]/_}" # dots, slashes and dashes are all illegal in a shell identifier, so disk.free.mb /var becomes DISK_FREE_MB__VAR
    _cpVar="CARINO_PROBE_${k^^}"
}

_carinoProbeSet () # KEY ARG VALUE
{
    local key="$1" arg="${2-}" val="${3-}"
    _carinoProbeKeyVar "$key" "$arg"
    printf -v "$_cpVar" '%s' "$val"
    printf -v "${_cpVar}_SET" '%s' 1
    _CARINO_PROBE_KEYS+=("$key${arg:+ $arg}") # a registry, because the mangling above is lossy and carino_probe_all could not otherwise recover "disk.free.mb /var" from DISK_FREE_MB__VAR
}

_carinoProbeIsSet () # KEY ARG -> 0 when already resolved
{
    _carinoProbeKeyVar "$1" "${2-}"
    local m="${_cpVar}_SET"
    [[ "${!m-}" == 1 ]] # ${!m-} rather than ${!m}: an unresolved fact is by definition an unset variable, and a bare indirect read of one is fatal under set -u
}

_carinoProbeRaw () # KEY ARG -> sets _cpOut to the memoised value; no resolution, no fork
{
    _carinoProbeKeyVar "$1" "${2-}"
    _cpOut="${!_cpVar-}"
}

_carinoProbeFetch () # KEY [ARG] -> resolves if needed and sets _cpOut; 0 when known, 1 when unknown
{
    local key="$1" arg="${2-}"
    _carinoProbeTierA
    _carinoProbeIsSet "$key" "$arg" || _carinoProbeResolve "$key" "$arg"
    _carinoProbeKeyVar "$key" "$arg" # recomputed, because _carinoProbeResolve calls _carinoProbeSet which overwrites the shared _cpVar on its way through
    _cpOut="${!_cpVar-}"
    [[ -n "$_cpOut" ]] || _cpOut="unknown"
    [[ "$_cpOut" == "unknown" ]] && return 1
    return 0
}
# _carinoProbeFetch, not $(carino_probe KEY), is what every function in this file uses internally, and
# the reason is the whole memoisation story: a command substitution runs in a SUBSHELL, so a fact
# resolved inside $( ) is written to a variable that dies when the substitution closes. Measured:
# bps=$(carino_probe net.speed.bps) followed by $(carino_probe net.speed.reason) downloaded 8 MiB
# twice. Subshells INHERIT the parent's memo but can never write back to it, so anything expensive has
# to be resolved in the caller's own shell - which is what carino_probe_load exists for.

# ---------------------------------------------------------------------------
# Internals: small pure-bash parsers
# ---------------------------------------------------------------------------

_carinoProbeUnquote () # sets _cpStr to $1 with one layer of surrounding quotes removed
{
    local s="$1"
    case "$s" in
        \"*\") s="${s#\"}"; s="${s%\"}" ;;
        \'*\') s="${s#\'}"; s="${s%\'}" ;;
    esac
    _cpStr="$s"
}

_carinoProbeNum () # sets _cpNum to a bare integer parsed from a curl -w number, returns 1 when it is not a number at all
{
    local s="${1//,/.}" m e ip fp # some locales and some older curl builds print a comma decimal separator; normalise before anything else touches the string
    _cpNum=0
    [[ -n "$s" ]] || return 1
    if [[ "$s" == *[eE]* ]]; then
        m="${s%%[eE]*}"; e="${s#*[eE]}"; e="${e#+}"
        [[ "$e" =~ ^-?[0-9]+$ ]] || return 1
        ip="${m%%.*}"; fp=""; [[ "$m" == *.* ]] && fp="${m#*.}"
        [[ "$ip" =~ ^[0-9]+$ ]] || return 1
        [[ -z "$fp" || "$fp" =~ ^[0-9]+$ ]] || return 1
        while (( e > 0 )); do if [[ -n "$fp" ]]; then ip="$ip${fp:0:1}"; fp="${fp:1}"; else ip="${ip}0"; fi; (( e-- )); done
        while (( e < 0 )); do ip="${ip%?}"; (( e++ )); done
        [[ -n "$ip" ]] || ip=0
        s="$ip" # 5.4403e+06 has to become 5440300 HERE, because $((10#5.4403e+06)) is a fatal arithmetic error that aborts the whole probe mid-run rather than returning a bad value
    else
        s="${s%%.*}" # curl 8.18 prints a whole number, older builds print 5440315.0000; the fraction of a bytes-per-second reading is noise either way
    fi
    [[ "$s" =~ ^[0-9]+$ ]] || return 1
    _cpNum=$(( 10#$s )) # 10# because a zero-padded field such as 08 is an invalid octal constant and would abort the arithmetic
    return 0
}

_carinoProbeUsec () # sets _cpUsec to microseconds parsed from a curl -w seconds field such as 0.084547
{
    local s="${1//,/.}" ip fp
    _cpUsec=0
    [[ "$s" == *[eE]* ]] && return 1 # curl never prints a connect time in scientific notation, but refusing is cheaper than parsing it wrongly
    ip="${s%%.*}"; fp=""; [[ "$s" == *.* ]] && fp="${s#*.}"
    [[ "$ip" =~ ^[0-9]+$ ]] || return 1
    fp="${fp}000000"; fp="${fp:0:6}"
    [[ "$fp" =~ ^[0-9]+$ ]] || return 1
    _cpUsec=$(( 10#$ip * 1000000 + 10#$fp ))
    return 0
}

# ---------------------------------------------------------------------------
# Tier A - cheap and eager
# ---------------------------------------------------------------------------

_carinoProbeTierA ()
{
    [[ "${_CARINO_PROBE_TIERA-}" == 1 ]] && return 0
    _CARINO_PROBE_TIERA=1

    local osrel="${CARINO_SETUP_OSRELEASE:-/etc/os-release}" # the same override setup.sh uses, so test.sh can drive every supported family without those distributions being installed
    local oid="" olike="" over="" line k v
    if [[ -r "$osrel" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            case "$line" in ''|'#'*) continue ;; esac
            k="${line%%=*}"; v="${line#*=}"
            _carinoProbeUnquote "$v"; v="$_cpStr"
            case "$k" in
                ID)         oid="$v" ;;
                ID_LIKE)    olike="$v" ;;
                VERSION_ID) over="$v" ;;
            esac
        done < "$osrel" # a pure bash read loop rather than grep|cut, so the eagerly-resolved tier costs zero forks and stays safe to call from a log header
    fi
    [[ -n "$oid" ]]  || oid="unknown"
    [[ -n "$over" ]] || over="unknown"
    _carinoProbeSet os.id "" "$oid"
    _carinoProbeSet os.version "" "$over"

    local fam="unknown" hay=" $oid $olike "
    case "$oid" in
        amzn)                                             fam="amazon" ;;
        rhel)                                             fam="rhel" ;;
        centos|rocky|almalinux|ol|scientific|springdale)   fam="centos" ;; # the rebuilds are grouped with CentOS Stream because they share its repository layout and its release cadence, which is all this key is ever used to decide
        fedora|nobara|ultramarine|risiOS|bazzite|bluefin|aurora|silverblue|kinoite|sericea|onyx) fam="fedora" ;;
        debian|ubuntu|linuxmint|pop|elementary|zorin|kali|raspbian|devuan|neon|tuxedo) fam="debian" ;;
        arch|manjaro|endeavouros|garuda|cachyos|artix|arcolinux) fam="arch" ;;
        opensuse|opensuse-leap|opensuse-tumbleweed|opensuse-slowroll|sles|sled|sle_hpc|suse) fam="opensuse" ;; # the produced token is "opensuse" and not "suse" because setup.sh's own family arms and the FAMILIES table in index.html both key it that way, and a later patch comparing carino_probe os.family against setup.sh's $family would silently never match
        *)
            case "$hay" in
                *" amzn "*)                     fam="amazon" ;;
                *" centos "*|*" rocky "*|*" almalinux "*) fam="centos" ;;
                *" rhel "*)                     fam="rhel" ;; # checked AFTER centos, because CentOS Stream and every rebuild carry ID_LIKE="rhel fedora" and would otherwise all answer rhel
                *" fedora "*)                   fam="fedora" ;;
                *" debian "*|*" ubuntu "*)      fam="debian" ;;
                *" arch "*)                     fam="arch" ;;
                *" suse "*|*" opensuse "*)      fam="opensuse" ;; # both ID_LIKE tokens still match, only the answer is spelled the way the rest of the repository spells it
            esac
            ;;
    esac
    _carinoProbeSet os.family "" "$fam"

    local atomic=0
    if command -v rpm-ostree >/dev/null 2>&1 && [[ -e /run/ostree-booted ]]; then atomic=1; fi # both halves are needed: rpm-ostree is installable on a plain Fedora workstation, and /run/ostree-booted is what actually says the running deployment is an image
    _carinoProbeSet os.atomic "" "$atomic"

    local pm="unknown"
    if (( atomic )); then pm="rpm-ostree"
    elif command -v dnf5   >/dev/null 2>&1; then pm="dnf5"
    elif command -v dnf    >/dev/null 2>&1; then pm="dnf"
    elif command -v apt    >/dev/null 2>&1; then pm="apt"
    elif command -v pacman >/dev/null 2>&1; then pm="pacman"
    elif command -v zypper >/dev/null 2>&1; then pm="zypper"
    fi
    _carinoProbeSet pkg.manager "" "$pm"

    local arch; arch=$(uname -m 2>/dev/null) # the one fork this tier is allowed; lscpu is absent on minimal installs and setup.sh already learned that lesson in systemFacts
    [[ -n "$arch" ]] || arch="unknown"
    _carinoProbeSet cpu.arch "" "$arch"

    local cores=0 model="" seen=0
    if [[ -r /proc/cpuinfo ]]; then
        local cpulines=()
        mapfile -t cpulines < /proc/cpuinfo 2>/dev/null # slurped in one go rather than read line by line: procfs regenerates the whole file for every read(), so a "while read" loop over /proc/cpuinfo measured 117 ms on a 24-thread machine against 0.7 ms for mapfile, and this tier is supposed to be free
        for line in "${cpulines[@]}"; do
            case "$line" in
                processor*)    (( seen++ )) ;;
                "model name"*) [[ -n "$model" ]] || model="${line#*: }" ;;
                Hardware*)     [[ -n "$model" ]] || model="${line#*: }" ;; # arm boards have no "model name" line at all, Hardware is the closest equivalent
            esac
        done
    fi
    cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
    [[ "$cores" =~ ^[0-9]+$ && "$cores" -gt 0 ]] || cores=$seen
    (( cores > 0 )) || cores=1
    _carinoProbeSet cpu.cores "" "$cores"
    [[ -n "$model" ]] || model="unknown"
    model="${model//,/ }" # no commas, so a consumer can split carino_probe_all output on them if it wants to
    while [[ "$model" == *"  "* ]]; do model="${model//  / }"; done
    _carinoProbeSet cpu.model "" "$model"

    local memt=0 mema=0 swpt=0 num memlines=()
    if [[ -r /proc/meminfo ]]; then
        mapfile -t memlines < /proc/meminfo 2>/dev/null # same reason as /proc/cpuinfo above: one read() for the whole procfs file, not one per line
        for line in "${memlines[@]}"; do
            case "$line" in
                MemTotal:*)     num="${line//[!0-9]/}"; memt=$(( 10#0$num / 1024 )) ;;
                MemAvailable:*) num="${line//[!0-9]/}"; mema=$(( 10#0$num / 1024 )) ;;
                SwapTotal:*)    num="${line//[!0-9]/}"; swpt=$(( 10#0$num / 1024 )) ;;
            esac
        done
    fi
    _carinoProbeSet mem.total.mb "" "$memt"
    _carinoProbeSet mem.avail.mb "" "$mema"
    _carinoProbeSet swap.total.mb "" "$swpt"

    local flag # written this way rather than as "$([[ -d x ]] && echo 1 || echo 0)" because each of those is a fork, and three of them tripled the cost of a tier whose whole promise is that it is free
    flag=0; [[ -d /run/systemd/system ]] && flag=1
    _carinoProbeSet init.systemd "" "$flag"
    flag=0; [[ -d /sys/firmware/efi ]] && flag=1
    _carinoProbeSet boot.uefi "" "$flag"

    local ctr="none"
    if   [[ -e /.dockerenv ]];        then ctr="docker"
    elif [[ -e /run/.containerenv ]]; then ctr="podman"
    elif [[ -r /proc/1/cgroup ]]; then
        local cglines=(); mapfile -t cglines < /proc/1/cgroup 2>/dev/null
        for line in "${cglines[@]}"; do
            case "$line" in
                *lxc*)     ctr="lxc"; break ;;
                *docker*)  ctr="docker"; break ;;
                *libpod*)  ctr="podman"; break ;;
            esac
        done
    else
        ctr="unknown" # no /.dockerenv, no /run/.containerenv and an unreadable /proc/1/cgroup means there is genuinely nothing to go on, which is not the same as "none"
    fi
    _carinoProbeSet container "" "$ctr"

    local uid="${EUID:-}"
    [[ -n "$uid" ]] || uid=$(id -u 2>/dev/null)
    [[ "$uid" =~ ^[0-9]+$ ]] || uid=0
    _carinoProbeSet priv.uid "" "$uid"

    local ptool="none" # deliberately the same ladder, in the same order, as setup.sh's setupPrivilege, so the two can never disagree about how this run would elevate
    if   (( uid == 0 ));                       then ptool="root"
    elif command -v sudo >/dev/null 2>&1;      then ptool="sudo"
    elif command -v doas >/dev/null 2>&1;      then ptool="doas"
    elif command -v run0 >/dev/null 2>&1;      then ptool="run0"
    fi
    _carinoProbeSet priv.tool "" "$ptool"

    flag=0; [[ -t 0 ]] && flag=1 # fd 0, never fd 1: setup.sh:9 makes stdout a pipe for the whole run, so -t 1 is false even with a human sitting at the keyboard, and -t 1 is additionally false inside any $( ) regardless
    _carinoProbeSet tty.interactive "" "$flag"
    return 0
}

# ---------------------------------------------------------------------------
# Tier B - cheap and lazy
# ---------------------------------------------------------------------------

_carinoProbeVirt ()
{
    local v="" out
    out=$(systemd-detect-virt 2>/dev/null)
    case "$out" in
        kvm|qemu|amazon)  v="kvm" ;;
        vmware)           v="vmware" ;;
        oracle)           v="virtualbox" ;; # systemd calls VirtualBox by its vendor name, every human calls it virtualbox
        microsoft)        v="hyperv" ;;
        xen)              v="xen" ;;
        none)             v="none" ;;
        '')               v="" ;;
        *)                v="unknown" ;;
    esac
    if [[ -z "$v" ]]; then
        local pn=""
        [[ -r /sys/class/dmi/id/product_name ]] && read -r pn < /sys/class/dmi/id/product_name 2>/dev/null
        case "$pn" in
            *VirtualBox*)              v="virtualbox" ;;
            *VMware*)                  v="vmware" ;;
            *"Virtual Machine"*)       v="hyperv" ;;
            *KVM*|*"Standard PC"*)     v="kvm" ;;
            *HVM*|*Xen*)               v="xen" ;;
            *)
                v="none"
                if [[ -r /proc/cpuinfo ]]; then
                    local line cpulines=()
                    mapfile -t -n 60 cpulines < /proc/cpuinfo 2>/dev/null # -n 60 because the flags line of processor 0 is inside the first block, and a full read of procfs line by line costs 117 ms on a 24-thread machine
                    for line in "${cpulines[@]}"; do
                        case "$line" in flags*hypervisor*) v="unknown"; break ;; esac # the hypervisor CPUID bit says "virtualised" without saying by what, so the honest answer is unknown rather than a guess
                    done
                fi
                ;;
        esac
    fi
    _carinoProbeSet virt "" "$v"
}

_carinoProbeGpu ()
{
    local vendors=" " count=0 line lc
    if command -v lspci >/dev/null 2>&1; then
        while IFS= read -r line; do
            lc="${line,,}"
            case "$lc" in *" vga compatible controller"*|*" 3d controller"*|*" display controller"*) ;; *) continue ;; esac
            (( count++ ))
            case "$lc" in
                *nvidia*)                             [[ "$vendors" == *" nvidia "* ]] || vendors+="nvidia " ;;
                *"advanced micro devices"*|*amd/ati*|*" ati "*) [[ "$vendors" == *" amd "* ]] || vendors+="amd " ;;
                *intel*)                              [[ "$vendors" == *" intel "* ]] || vendors+="intel " ;;
            esac
        done < <(lspci 2>/dev/null)
    fi
    if (( count == 0 )); then
        local nf; case $- in *f*) nf=1 ;; *) nf=0 ;; esac; set +f # set -f is global from setup.sh:10 and is never lifted except at :733, and under it this loop iterates the literal string /sys/class/drm/card*/device/vendor and reads nothing
        local d dev id
        for d in /sys/class/drm/card*/device/vendor; do
            [[ -r "$d" ]] || continue
            dev="${d#/sys/class/drm/}"; dev="${dev%%/*}"
            [[ "$dev" =~ ^card[0-9]+$ ]] || continue # card1-DP-1 and friends are connector directories whose device symlink points at the same GPU, and counting them would multiply one card by its output count
            read -r id < "$d" 2>/dev/null
            case "$id" in
                0x10de) (( count++ )); [[ "$vendors" == *" nvidia "* ]] || vendors+="nvidia " ;;
                0x1002|0x1022) (( count++ )); [[ "$vendors" == *" amd "* ]] || vendors+="amd " ;;
                0x8086) (( count++ )); [[ "$vendors" == *" intel "* ]] || vendors+="intel " ;;
                ?*)     (( count++ )) ;;
            esac
        done
        (( nf )) && set -f
    fi
    vendors="${vendors# }"; vendors="${vendors% }"
    [[ -n "$vendors" ]] || vendors="none"
    _carinoProbeSet gpu.vendor "" "$vendors"
    _carinoProbeSet gpu.count "" "$count"
}

_carinoProbePower ()
{
    local nf; case $- in *f*) nf=1 ;; *) nf=0 ;; esac; set +f # same noglob save-and-restore as above, and saved rather than assumed because a fleet script that copies this file may not have set -f on at all
    local p t s online src="unknown" bat=0
    for p in /sys/class/power_supply/*; do
        [[ -d "$p" ]] || continue
        t=""; [[ -r "$p/type" ]] && read -r t < "$p/type" 2>/dev/null
        case "$t" in
            Mains|USB|UPS)
                online=""; [[ -r "$p/online" ]] && read -r online < "$p/online" 2>/dev/null
                [[ "$online" == 1 ]] && src="ac"
                ;;
            Battery)
                bat=1
                s=""; [[ -r "$p/status" ]] && read -r s < "$p/status" 2>/dev/null
                [[ "$s" == "Discharging" && "$src" != "ac" ]] && src="battery"
                ;;
        esac
    done
    (( nf )) && set -f
    _carinoProbeSet power.source "" "$src"
    _carinoProbeSet power.battery "" "$bat"
}

_carinoProbeDiskFree () # ARG = path
{
    local p="${1:-/}" hdr dev blocks used avail rest mb=""
    if command -v df >/dev/null 2>&1 && [[ -e "$p" ]]; then
        { read -r hdr; read -r dev blocks used avail rest; } < <(df -P -k "$p" 2>/dev/null) # -P is POSIX and is what guarantees one line per filesystem, without it a long device name wraps and "avail" lands in the wrong field
        [[ "$avail" =~ ^[0-9]+$ ]] && mb=$(( 10#$avail / 1024 ))
    fi
    [[ -n "$mb" ]] || mb="unknown"
    _carinoProbeSet disk.free.mb "${1-}" "$mb"
}

_carinoProbeDiskRot () # ARG = path
{
    local p="${1:-/}" hdr dev rest base rot="unknown" val
    if command -v df >/dev/null 2>&1 && [[ -e "$p" ]]; then
        { read -r hdr; read -r dev rest; } < <(df -P -k "$p" 2>/dev/null)
        base="${dev##*/}"
        if [[ -n "$base" ]]; then
            if [[ -r "/sys/class/block/$base/../queue/rotational" ]]; then
                read -r val < "/sys/class/block/$base/../queue/rotational" 2>/dev/null # the .. hop is what turns a partition into its parent disk, because /sys/class/block/nvme1n1p3 is a symlink into the parent device directory and only the parent carries queue/
            elif [[ -r "/sys/block/$base/queue/rotational" ]]; then
                read -r val < "/sys/block/$base/queue/rotational" 2>/dev/null
            fi
            [[ "$val" == 0 || "$val" == 1 ]] && rot="$val"
        fi
    fi
    _carinoProbeSet disk.rotational "${1-}" "$rot"
}

_carinoProbeNetMetered ()
{
    local m="unknown" line v
    if command -v nmcli >/dev/null 2>&1; then
        while IFS= read -r line; do
            v="${line#GENERAL.METERED:}"
            v="${v% (guessed)}" # nmcli appends "(guessed)" when it inferred rather than read the flag, and the parenthesis makes a plain string comparison silently fail
            case "$v" in
                yes*) m="yes"; break ;;
                no*)  [[ "$m" == "unknown" ]] && m="no" ;;
            esac
        done < <(nmcli -t -f GENERAL.METERED device show 2>/dev/null) # the device-level query, not "nmcli -t -f connection.metered connection show --active" which is not a valid field and errors out
    fi
    _carinoProbeSet net.metered "" "$m"
}

_carinoProbeNetConn ()
{
    local c="unknown" out
    if command -v nmcli >/dev/null 2>&1; then
        out=$(nmcli networking connectivity 2>/dev/null)
        case "$out" in full|portal|limited|none) c="$out" ;; esac
    fi
    _carinoProbeSet net.connectivity "" "$c"
}

# ---------------------------------------------------------------------------
# Tier C - the bandwidth measurement
# ---------------------------------------------------------------------------
# Reports "this mirror's throughput right now", never "your connection speed". The two are
# not the same number: on the development machine a generic CDN reported 750,477 B/s while
# the machine's own configured dnf mirror delivered 5,440,315 B/s, a 7x error that inverts
# the bucket decision. That is also why there is no Carino-hosted test file and no fallback
# target - setup.carino.systems is a CDN like any other and would measure a path dnf never
# takes. When the real mirror cannot be found or measured, the answer is unknown, full stop.

_carinoProbeNetFinish () # REASON [BPS] [RTTMS] [URL]
{
    _carinoProbeSet net.speed.reason "" "${1-}"
    _carinoProbeSet net.speed.bps    "" "${2:-unknown}"
    _carinoProbeSet net.rtt.ms       "" "${3:-unknown}"
    _carinoProbeSet net.mirror.url   "" "${4:-unknown}"
}

_carinoProbeMirrorUrl () # sets _cpMirror to a large, real, package-manager-owned file URL, or empty
{
    _cpMirror=""
    local t0=$SECONDS fam pm rel arch ml body u base repomd href cands origin # "repomd", not "rm": a local named rm reads like a call to the shimmed rm(1) to anyone auditing this file against enableDryRun's list
    if [[ -n "${CARINO_PROBE_MIRROR_URL-}" ]]; then _cpMirror="$CARINO_PROBE_MIRROR_URL"; return 0; fi # an operator override for an air-gapped internal mirror, and the only way to exercise this path in a test; it is not a fallback, nothing selects it automatically
    _carinoProbeFetch os.family;  fam="$_cpOut"
    _carinoProbeFetch pkg.manager; pm="$_cpOut"
    _carinoProbeFetch cpu.arch;   arch="$_cpOut"

    case "$pm" in
        dnf|dnf5)
            rel=""
            [[ "$fam" == fedora ]] && rel=$(rpm -E %fedora 2>/dev/null)
            if [[ ! "$rel" =~ ^[0-9]+$ ]]; then _carinoProbeFetch os.version; rel="${_cpOut%%.*}"; fi # every rhel-family release string is major.minor and every repository variable wants the major only
            [[ "$rel" =~ ^[0-9]+$ ]] || return 1
            local nf; case $- in *f*) nf=1 ;; *) nf=0 ;; esac; set +f # /etc/yum.repos.d/*.repo does not expand under set -f, and grep would then be handed the literal pattern as a filename
            local pat lines
            lines=$(grep -h -E '^[[:space:]]*(metalink|mirrorlist)=' /etc/yum.repos.d/*.repo 2>/dev/null)
            (( nf )) && set -f
            # Selected by EXACT repo name, never by directory order and never by a loose alternation.
            # /etc/yum.repos.d reads alphabetically so fedora-cisco-openh264.repo sorts first, and its
            # repository holds four packages whose primary.xml.zst is a couple of kilobytes. A first
            # draft of this function matched repo=(fedora|...) and picked exactly that file: the sample
            # then failed the 1 MiB floor and the whole probe answered bad-response on a healthy link.
            # These patterns are grep -F literals, so the $ of $releasever is a plain character here.
            for pat in "repo=fedora-\$releasever&" \
                       "repo=centos-baseos-\$stream&" "repo=centos-baseos-\$releasever&" \
                       "repo=BaseOS-\$releasever&" "repo=baseos-\$releasever&" \
                       "repo=rhel-\$releasever-" "repo=amazonlinux-\$releasever&"; do
                ml=$(printf '%s\n' "$lines" | grep -F "$pat" | head -1)
                [[ -n "$ml" ]] && break
            done
            [[ -n "$ml" ]] || return 1 # no recognised base repository means no honest target, and the answer is no-mirror; falling back to a generic CDN is explicitly rejected because it reintroduced a measured 7x error
            ml="${ml#*=}"; ml="${ml%%[[:space:]]*}"
            ml="${ml//\$releasever/$rel}"; ml="${ml//\$basearch/$arch}"; ml="${ml//\$stream/$rel}"
            ml="${ml//\$\{releasever\}/$rel}"; ml="${ml//\$\{basearch\}/$arch}" # curl has never heard of a dnf variable, so every one of them has to be expanded by hand here
            body=$(curl -fsSL --connect-timeout 2 --max-time 3 "$ml" 2>/dev/null) || return 1
            cands=$(printf '%s\n' "$body" | grep -oE 'https://[^<"]+/repodata/repomd\.xml' | head -4)
            [[ -n "$cands" ]] || cands=$(printf '%s\n' "$body" | grep -oE '^https://[^[:space:]]+' | head -4) # a mirrorlist= is a plain list of base URLs rather than metalink XML, so the https lines are bases and repodata is appended below
            ;;
        zypper)
            local base0
            base0=$(zypper --non-interactive lr -u 2>/dev/null | grep -oE 'https?://[^[:space:]|]+' | head -1)
            [[ -n "$base0" ]] || return 1
            base0="${base0%/}"
            body=$(curl -fsSL --connect-timeout 2 --max-time 3 "$base0/repodata/repomd.xml.metalink" 2>/dev/null) # MirrorBrain serves a preference-sorted mirror list from any file path with .metalink appended
            cands=$(printf '%s\n' "$body" | grep -oE 'https?://[^<"]+/repodata/repomd\.xml' | head -4)
            cands="$cands"$'\n'"$base0/repodata/repomd.xml" # the redirector itself is the last resort here rather than a generic CDN, because download.opensuse.org still serves the real repository and -L follows it to a real mirror
            ;;
        *) return 1 ;;
    esac

    [[ -n "$cands" ]] || return 1
    # Every candidate is tried in turn, not just the first. MirrorManager sorts by netblock preference
    # and that ordering says nothing about whether the host is up: a run of this function picked a
    # mirror whose repomd.xml never answered, burned the 2 s connect timeout and reported no-mirror on
    # a perfectly healthy link. Four candidates inside the same 6 s cap costs nothing when the first
    # one works, which is the normal case.
    while IFS= read -r u; do
        [[ -n "$u" ]] || continue
        (( SECONDS - t0 > 6 )) && return 1 # discovery is capped at 6 s total; past that the measurement is no longer worth what it costs the caller
        [[ "$u" == */repomd.xml ]] || u="${u%/}/repodata/repomd.xml"
        base="${u%/repodata/repomd.xml}"
        repomd=$(curl -fsSL --connect-timeout 2 --max-time 3 "$u" 2>/dev/null) || continue
        href=$(printf '%s\n' "$repomd" | grep -oE 'href="[^"]*-primary\.xml\.(zst|gz|xz)"' | head -1)
        [[ -n "$href" ]] || href=$(printf '%s\n' "$repomd" | grep -oE 'href="[^"]*-primary\.sqlite\.(zst|gz|xz|bz2)"' | head -1)
        [[ -n "$href" ]] || continue
        href="${href#href=\"}"; href="${href%\"}"
        case "$href" in
            http*) _cpMirror="$href" ;;
            /*)    origin="${base#*://}"; origin="${base%%://*}://${origin%%/*}"; _cpMirror="$origin$href" ;; # a root-relative href hangs off the scheme and host, not off the repository directory, and gluing it to $base would produce .../os//repodata/... on the mirrors that emit one
            *)     _cpMirror="$base/$href" ;;
        esac
        return 0
    done <<<"$cands"
    return 1
}

_carinoProbeSample () # URL RANGE -> sets _cpBps and _cpRtt, returns 1 on any failure
{
    local url="$1" range="$2" out rc code size speed tnl tcon rs re want=0
    _cpBps=0; _cpRtt="unknown"; _cpSize=0
    out=$(curl -sL -o /dev/null --connect-timeout 3 --max-time 5 -r "$range" \
               -w '%{http_code} %{size_download} %{speed_download} %{time_namelookup} %{time_connect}' \
               "$url" 2>/dev/null); rc=$?
    # -L is mandatory: without it the same osuosl URL measured 846 B/s instead of 2,059,712 B/s, a 2400x error, because ftp-chi.osuosl.org 301s and download.opensuse.org is a redirector by design
    # -r bounds the bytes and --max-time bounds the seconds; never --max-filesize, which reads Content-Length and refuses to start (exit 63, speed=0) and normalises into a plausible-looking "very slow link"
    (( rc == 0 || rc == 28 )) || return 1 # 28 is --max-time firing, and curl still prints a complete and correct %{speed_download} when it does; that is the success path on exactly the slow links this probe exists to detect
    read -r code size speed tnl tcon <<<"$out"
    rs="${range%%-*}"; re="${range##*-}"
    [[ "$rs" =~ ^[0-9]+$ && "$re" =~ ^[0-9]+$ ]] && want=$(( 10#$re - 10#$rs + 1 )) # the number of bytes actually asked for, recovered from the range itself because curl reports what arrived and never what was requested
    [[ "$size" =~ ^[0-9]+$ ]] || return 1 # checked BEFORE the status case below rather than after it, because the 200 arm does arithmetic on this field and a non-numeric one would abort the whole probe with an arithmetic error instead of failing one sample
    _cpSize=$(( 10#$size ))
    case "$code" in
        206) ;;
        200) (( want > 0 && 10#$size > want )) && return 1 ;; # -r is a REQUEST and not a guarantee: a mirror that ignores the Range header answers 200 with the entire file and --max-time 5 is then the only ceiling left, which on a gigabit link is five seconds of link speed rather than 8 MiB and quietly breaks the "it fetches up to 8 MiB" disclosure INTEGRATION-PLAN.md 8.2 turns into a README the user is asked to consent to; a 200 at or below the requested length is the legitimate "the file is smaller than the range" case and has to keep working
        *)   return 1 ;;
    esac
    (( 10#$size >= 1048576 )) || return 1 # exit status alone is never sufficient: a 301 without -L (1094 B/s), a 404 (564 B/s) and a Cloudflare 403 (6 B/s) all return exit 0 with a confident wrong number, and only the byte count catches all three
    _carinoProbeNum "$speed" || return 1
    _cpBps=$_cpNum
    (( _cpBps > 0 )) || return 1
    local a b
    if _carinoProbeUsec "$tcon"; then a=$_cpUsec; if _carinoProbeUsec "$tnl"; then b=$_cpUsec; (( a >= b )) && _cpRtt=$(( (a - b) / 1000 )); fi; fi # a free byproduct of the same request: no ping, no root, no extra round trip
    return 0
}

_carinoProbeNetSpeed ()
{
    local allow="${CARINO_PROBE_NET-}"
    if [[ "$allow" == 0 ]]; then _carinoProbeNetFinish skipped; return 0; fi
    if [[ "${NONINTERACTIVE:-0}" == 1 || "${DRYRUN:-0}" == 1 ]] && [[ "$allow" != 1 ]]; then
        _carinoProbeNetFinish skipped; return 0 # test.sh runs 8 plans under timeout 120 and 14 arguments under timeout 90 and treats exit 124 as an outright failure, so a multi-second probe multiplied across those rows blows the budget
    fi
    command -v curl >/dev/null 2>&1 || { _carinoProbeNetFinish no-target; return 0; }

    _carinoProbeFetch net.metered
    [[ "$_cpOut" == "yes" ]] && { _carinoProbeNetFinish metered; return 0; } # spending 8 MiB of a phone tether to tune download parallelism is indefensible
    _carinoProbeFetch net.connectivity
    case "$_cpOut" in
        portal|none) _carinoProbeNetFinish no-route; return 0 ;; # this is also the whole of the offline fast path: NetworkManager already knows there is no route and answers in about a millisecond, so nothing below ever opens a socket
    esac
    _carinoProbeFetch pkg.manager
    case "$_cpOut" in
        apt|pacman|rpm-ostree|unknown) _carinoProbeNetFinish no-target; return 0 ;; # there is no knob to feed on these and no guaranteed large file to measure: pacman's only certain file, core.db, is 130,150 bytes, an order of magnitude below the slow-start floor
    esac

    local budget="${CARINO_PROBE_NET_MAXSEC:-25}"
    [[ "$budget" =~ ^[0-9]+$ ]] || budget=25
    local t0=$SECONDS
    _carinoProbeMirrorUrl || { _carinoProbeNetFinish no-mirror; return 0; }
    local url="$_cpMirror"

    _carinoProbeSample "$url" "0-8388607" || { _carinoProbeNetFinish bad-response "" "" "$url"; return 0; }
    # 8 MiB is the floor, not a preference: TCP slow start under-reports smaller samples by up to 3.5x (1 MiB read 1.5 MB/s on a measured 5.5 MB/s link). The bias is always downward, which is the safe direction, but it is large enough to change the bucket.
    local bps=$_cpBps rtt="$_cpRtt"

    local near=0 b # median of three only when the first answer lands within 20% of a bucket boundary, because single samples spread 3.9x on repeated back-to-back runs while median-of-3 narrows to 1.29x, and paying another 12 MiB for that is only worth it where it can change the answer
    for b in 1000000 5000000; do
        (( bps >= b - b / 5 && bps <= b + b / 5 )) && near=1
    done
    if (( near )); then
        local s=(0 0 0) i=0 r ok=1
        for r in "0-4194303" "4194304-8388607" "8388608-12582911"; do
            (( SECONDS - t0 > budget - 6 )) && { ok=0; break; } # the wall-clock check sits BETWEEN samples rather than around the whole block, because --max-time only bounds one curl and four of them plus a 6 s discovery would otherwise overrun the 25 s ceiling on a slow link
            if _carinoProbeSample "$url" "$r" && (( _cpSize >= 4194304 )); then s[i]=$_cpBps; else ok=0; break; fi # a 416 on the third range means the index is smaller than 12 MiB, which is a legitimate outcome and simply means no escalation; the size test is what makes a SHORT third range mean the same thing, because an index between 8 and 12 MiB answers 206 with a 1.4 MiB body that clears the 1 MiB floor and would then enter the median carrying far more TCP slow-start bias than its two siblings, which is the exact mixing the comment below says is never done
            (( i++ ))
        done
        if (( ok && s[0] > 0 && s[1] > 0 && s[2] > 0 )); then
            local lo=${s[0]} hi=${s[0]}
            for i in 1 2; do (( s[i] < lo )) && lo=${s[i]}; (( s[i] > hi )) && hi=${s[i]}; done
            bps=$(( s[0] + s[1] + s[2] - lo - hi ))
            # three FRESH 4 MiB samples and the first 8 MiB reading is discarded, rather than a median across mixed range sizes: a 4 MiB sample carries more TCP slow-start bias than an 8 MiB one, so mixing the two puts a systematically higher number in the middle of the sort and the median stops meaning anything
        fi
    fi
    # worst case for the whole Tier C operation is therefore 8 + 4 + 4 + 4 = 20 MiB, which is the stated ceiling exactly, and the between-sample clock check is what holds the 25 s half of it

    if (( bps < 1000 )); then _carinoProbeNetFinish too-slow "$bps" "$rtt" "$url"; return 0; fi # below a kilobyte a second the reading is indistinguishable from a stalled connection, and dnf's own minrate default is 1000 B/s
    _carinoProbeNetFinish measured "$bps" "$rtt" "$url"
    return 0
}

# ---------------------------------------------------------------------------
# Resolution dispatcher
# ---------------------------------------------------------------------------

_carinoProbeResolve () # KEY ARG
{
    case "$1" in
        os.id|os.family|os.version|os.atomic|pkg.manager|cpu.arch|cpu.cores|cpu.model|mem.total.mb|mem.avail.mb|swap.total.mb|init.systemd|boot.uefi|container|priv.uid|priv.tool|tty.interactive)
            _CARINO_PROBE_TIERA=0; _carinoProbeTierA ;; # only reachable after carino_probe_reset KEY dropped one eager fact while the tier guard stayed raised; without this arm the key fell through to the default and answered "unknown" forever, and mem.avail.mb is exactly the fact a long-running script has a real reason to reset and re-read
        virt)                 _carinoProbeVirt ;;
        gpu.vendor|gpu.count) _carinoProbeGpu ;;
        power.source|power.battery) _carinoProbePower ;;
        disk.free.mb)         _carinoProbeDiskFree "${2-}" ;;
        disk.rotational)      _carinoProbeDiskRot "${2-}" ;;
        net.metered)          _carinoProbeNetMetered ;;
        net.connectivity)     _carinoProbeNetConn ;;
        net.speed.bps|net.speed.reason|net.rtt.ms|net.mirror.url) _carinoProbeNetSpeed ;; # one measurement resolves all four keys at once, so asking for the rtt never costs a second download
        *)                    _carinoProbeSet "$1" "${2-}" "unknown"; return 1 ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

carino_probe () # KEY [ARG] -> prints the value; exit 0 when known, 1 when unknown
{
    [[ -n "${1-}" ]] || { printf 'unknown\n'; return 1; }
    local rc
    _carinoProbeFetch "$1" "${2-}"; rc=$?
    printf '%s\n' "$_cpOut"
    return $rc
}

carino_probe_load () # KEY [ARG] -> resolve in THE CALLER'S shell, print nothing; exit 0 when known
{
    [[ -n "${1-}" ]] || return 1
    _carinoProbeFetch "$1" "${2-}"
    return $?
}
# This is the warming call, and any caller that reads more than one net.* key should use it:
#     carino_probe_load net.speed.bps          # one measurement, memoised HERE
#     echo "$(carino_probe net.speed.bps) at $(carino_probe net.rtt.ms) ms"   # both free
# Without it, each $( ) forks a subshell that re-measures and then throws the memo away.

carino_probe_has () # KEY [ARG] -> exit 0 when the fact is known and truthy
{
    _carinoProbeFetch "$1" "${2-}" # no $( ) here, so a boolean test also warms the parent's memo instead of discarding it
    case "$_cpOut" in ''|unknown|0|no|none|false|off) return 1 ;; esac
    return 0
}

carino_probe_int () # KEY [ARG] -> prints a bare integer, 0 when the value is not one; exit 1 when unknown
{
    _carinoProbeFetch "$1" "${2-}"
    if [[ "$_cpOut" =~ ^[0-9]+$ ]]; then printf '%s\n' "$(( 10#$_cpOut ))"; return 0; fi
    printf '0\n'
    return 1
}

carino_probe_all () # [PREFIX] -> every RESOLVED fact as key=value, sorted
{
    _carinoProbeTierA
    local k key arg out="" seen=$'\n'
    for k in "${_CARINO_PROBE_KEYS[@]}"; do
        key="${k%% *}"; arg=""; [[ "$k" == *" "* ]] && arg="${k#* }"
        [[ -n "${1-}" && "$key" != "${1-}"* ]] && continue
        [[ "$seen" == *$'\n'"$k"$'\n'* ]] && continue # the registry is append-only, so a carino_probe_reset followed by a re-probe leaves two entries for the same key and this listing would print it twice
        _carinoProbeIsSet "$key" "$arg" || continue   # and a single-key reset leaves a registry entry whose variable is gone, which would print "key=" with an empty value
        seen+="$k"$'\n'
        _carinoProbeRaw "$key" "$arg"
        out+="$k=$_cpOut"$'\n'
    done
    [[ -n "$out" ]] || return 0
    printf '%s' "$out" | LC_ALL=C sort # only facts already resolved plus the eager tier, and never a trigger for an expensive one, which is what makes this safe to call from a log header
    return 0
}

carino_probe_report () # human readable; uses carino-term.sh primitives when that library is loaded, plain printf when it is not
{
    _carinoProbeTierA
    local termed=0
    declare -F carino_kv >/dev/null 2>&1 && termed=1 # a soft, one-way, optional dependency; this file must never source or require carino-term.sh
    local k v
    for k in virt gpu.vendor gpu.count power.source power.battery net.metered net.connectivity; do
        _carinoProbeFetch "$k" # the whole cheap-lazy tier, resolved up front so the report is complete; the expensive tier is shown only when something already asked for it, because a log header must never cost 8 MiB
    done
    _carinoProbeFetch disk.free.mb /
    _carinoProbeFetch disk.rotational /

    if (( termed )) && declare -F carino_rule >/dev/null 2>&1; then carino_rule "SYSTEM FACTS"; fi
    (( termed )) && (( ${CT_KV_W:-0} < 17 )) && CT_KV_W=17 # carino_kv pads to the widest key it has ALREADY seen, so an unprimed column starts ragged and only squares up near the bottom of the table; 17 is the longest label this function can emit ("disk.rotational /" and "mirror.throughput"), and priming it is the documented way to use that primitive rather than a change to its contract
    for k in os.id os.family os.version os.atomic pkg.manager cpu.arch cpu.cores cpu.model \
             mem.total.mb mem.avail.mb swap.total.mb init.systemd boot.uefi container virt \
             gpu.vendor gpu.count power.source power.battery priv.uid priv.tool tty.interactive \
             net.metered net.connectivity; do
        _carinoProbeRaw "$k" ""; v="$_cpOut"
        [[ -n "$v" ]] || continue
        if (( termed )); then carino_kv "$k" "$v"; else printf '%-18s %s\n' "$k" "$v"; fi
    done
    for k in "disk.free.mb /" "disk.rotational /"; do
        _carinoProbeRaw "${k%% *}" "${k#* }"; v="$_cpOut"
        [[ -n "$v" ]] || continue
        if (( termed )); then carino_kv "$k" "$v"; else printf '%-18s %s\n' "$k" "$v"; fi
    done
    if _carinoProbeIsSet net.speed.bps ""; then
        local r rtt url pretty
        _carinoProbeRaw net.speed.bps "";    v="$_cpOut"
        _carinoProbeRaw net.speed.reason ""; r="$_cpOut"
        _carinoProbeRaw net.rtt.ms "";       rtt="$_cpOut"
        _carinoProbeRaw net.mirror.url "";   url="$_cpOut"
        pretty="$v"
        [[ "$v" =~ ^[0-9]+$ ]] && printf -v pretty '%d.%d MB/s' $(( v / 1000000 )) $(( (v % 1000000) * 10 / 1000000 )) # integer only, because bc is absent on a minimal install and this file will not fork a python to divide two numbers
        if (( termed )); then
            carino_kv "mirror.throughput" "$pretty ($r)"
            carino_kv "net.rtt.ms" "$rtt"
            carino_kv "net.mirror.url" "$url"
        else
            printf '%-18s %s (%s)\n' "mirror.throughput" "$pretty" "$r"
            printf '%-18s %s\n' "net.rtt.ms" "$rtt"
            printf '%-18s %s\n' "net.mirror.url" "$url"
        fi
        if [[ "$r" == "measured" ]]; then # only when there IS a figure; printing "that figure is this mirror's throughput" under "unknown (no-mirror)" told the reader something about a number that does not exist
            v="That figure is this mirror's throughput right now, not your connection speed." # MirrorManager sorts by netblock preference and dnf's own fastestmirror sorts by TCP latency, so neither the chosen mirror nor this number describes the link itself
            if (( termed )) && declare -F carino_note >/dev/null 2>&1; then carino_note "$v"; else printf '%s\n' "$v"; fi
        fi
    fi
    return 0
}

carinoProbeReport () { carino_probe_report "$@"; } # the camelCase spelling, because every other function name in setup.sh is camelCase and a caller should not have to remember which convention this one file uses

carino_probe_reset () # [KEY [ARG]] -> drop memoised values; testing only
{
    if [[ -n "${1-}" ]]; then
        _carinoProbeKeyVar "$1" "${2-}"
        unset "$_cpVar" "${_cpVar}_SET"
        return 0
    fi
    local v
    for v in $(compgen -v CARINO_PROBE_ 2>/dev/null); do
        case "$v" in CARINO_PROBE_LIB|CARINO_PROBE_NET|CARINO_PROBE_NET_MAXSEC|CARINO_PROBE_MIRROR_URL) continue ;; esac # the three env knobs share the namespace and are configuration, not memoised facts
        unset "$v"
    done
    _CARINO_PROBE_KEYS=()
    _CARINO_PROBE_TIERA=0
    return 0
}

# ---------------------------------------------------------------------------
# Decision helpers - they return a recommendation and a reason, they never execute anything
# ---------------------------------------------------------------------------

_carinoProbeParallelN () # sets _cpParN and _cpParWhy; the shared body of the two public helpers, so neither has to fork the other
{
    local bps
    _carinoProbeFetch net.speed.bps; bps="$_cpOut" # asking for this key IS the explicit opt-in the Tier C contract requires; every guard in _carinoProbeNetSpeed still applies, and on apt/pacman/rpm-ostree it answers unknown without touching the network
    if   [[ ! "$bps" =~ ^[0-9]+$ ]]; then _cpParN=0; _cpParWhy="unmeasured"
    elif (( bps < 1000000 ));       then _cpParN=0; _cpParWhy="slow-link" # never raise parallelism below about 1 MB/s: dnf5.conf(5) sets minrate 1000 B/s and timeout 30 s, so N connections on a link slower than N kB/s makes dnf abort connections; this is the documented mechanism by which "helpfully" raising the value makes a slow link worse rather than merely no better
    elif (( bps < 5000000 ));       then _cpParN=6; _cpParWhy="medium"
    else                                 _cpParN=8; _cpParWhy="fast" # ceiling 8, because measured aggregate throughput was 2.6x from 1 to 4 connections and only a further 1.1x from 4 to 8; 20 buys nothing and multiplies load on volunteer mirrors
    fi
    (( _cpParN > 20 )) && _cpParN=20 # unconditional and non-negotiable even though the ladder above can never reach it: dnf4 4.14.0 and dnf5 5.2.18 both accept 21 with exit 0 and then fail EVERY subsequent operation with "Librepo error: Bad value of LRO_MAXPARALLELDOWNLOADS" until someone hand-edits the file, so the clamp guards a future edit of the ladder rather than the ladder as written
    return 0
}

carino_probe_parallel_suggest () # prints "N reason"; N is the value to use, 0 means change nothing
{
    _carinoProbeParallelN
    printf '%s %s\n' "$_cpParN" "$_cpParWhy"
    return 0
}

carino_probe_parallel_flags () # prints the exact CLI flags for this pkg.manager, or nothing at all
{
    _carinoProbeParallelN
    (( _cpParN > 0 )) || return 0
    _carinoProbeFetch pkg.manager
    case "$_cpOut" in
        dnf|dnf5) printf '%s\n' "--setopt=max_parallel_downloads=$_cpParN --setopt=max_downloads_per_mirror=$_cpParN" ;; # both, always together: at its default of 3, max_downloads_per_mirror silently caps single-baseurl repos - RPM Fusion, Google Chrome, every copr setup.sh enables - so raising only the famous knob and announcing "parallel downloads enabled" overstates what actually happened on exactly the repos this script adds
        *) ;; # apt has no such option at all (apt-config dump | grep -ci parallel is 0 on apt 3.0.3), pacman already ships ParallelDownloads = 5 uncommented, zypper's max_concurrent_connections means chunks of one file rather than N packages, and rpm-ostree has no --setopt to pass; per-invocation flags are the whole mechanism, this file never writes a config file
    esac
    return 0
}

carino_probe_can_gpu_accel () # prints "amd|intel|nvidia|none reason"
{
    local v c
    _carinoProbeFetch gpu.vendor; v="$_cpOut"
    _carinoProbeFetch container;  c="$_cpOut"
    if [[ "$v" == "none" || "$v" == "unknown" ]]; then printf 'none no-gpu\n'; return 0; fi
    if [[ "$c" != "none" && "$c" != "unknown" ]]; then printf '%s container\n' "${v%% *}"; return 0; fi # a card is visible but the device nodes may not be passed through, so the caller is told which vendor AND that it is in a container rather than being told a flat yes
    case " $v " in
        *" nvidia "*) printf 'nvidia present\n' ;; # vendor only; whether the proprietary driver is loaded is a different question and this file does not run nvidia-smi, which is absent on a clean install and would print "command not found" into test.sh's forbidden-pattern check
        *" amd "*)    printf 'amd present\n' ;;
        *" intel "*)  printf 'intel present\n' ;;
        *)            printf 'none unrecognised-vendor\n' ;;
    esac
    return 0
}

carino_probe_enough_disk () # PATH MB -> exit 0/1; prints "have=N need=M"
{
    local p="${1:-/}" need="${2:-0}" have
    [[ "$need" =~ ^[0-9]+$ ]] || need=0
    _carinoProbeFetch disk.free.mb "$p"; have="$_cpOut"
    if [[ ! "$have" =~ ^[0-9]+$ ]]; then printf 'have=unknown need=%s\n' "$need"; return 1; fi
    printf 'have=%s need=%s\n' "$have" "$need"
    (( 10#$have >= need ))
}
