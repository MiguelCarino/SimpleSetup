# shellcheck shell=bash
# carino-term.sh — the Carino Systems terminal design system.
# ---------------------------------------------------------------------------
# The terminal counterpart to https://branding.carino.systems. Every colour in
# here is a token lifted from carino-branding.css, so a shell script and a web
# page made by Carino Systems read as one product. Source it, call the
# primitives, never hand-roll an escape sequence again.
#
#   . ./carino-term.sh          # or fetched over HTTPS, see carinoLoad in setup.sh
#   carino_term_init            # optional, every primitive self-initialises
#   carino_ok "Flatpak remote flathub is configured."
#   carinoTermDemo              # renders every primitive so a human can eyeball it
#
# Distribution model: this file is COPIED into each fleet script repo, exactly
# like carino-navbar.js, carino-clock.js and carino-lang.js already are. There
# is no package, no installer and no dependency beyond bash 4+ and a coreutils
# that a minimal install actually ships. tput, python, bc, sed, awk and jq are
# all optional or unused.
#
# THIS FILE MUST BE SAVED AS UTF-8. The multibyte probe in carino_term_init
# compares ${#v} against a literal é; re-saving as Latin-1 turns that one
# character into two bytes, silently inverts the answer, and drops every
# terminal in the fleet into the ASCII tier for no reason.
#
# Light terminals: this library assumes a dark background, because every
# contrast figure in the token table below is measured against #000000 and
# carino-branding.css:459 hardcodes .terminal { background: #000 }. Detecting
# the real background needs an OSC 11 query with a raw tty read and a timeout,
# most terminals ignore it, and fd 0 may be a pipe. A light-terminal user sets
# CARINO_TERM_COLOR=never. That is the whole of the light-mode story.
#
# Public API, frozen. setup.sh's carinoTermShim must define every name on this
# list or a call site can reference an undefined function; anything added here
# has to be added there in the same patch.
#   carino_term_init  carino_term_selftest  carino_term_cjk_ok
#   carino_msg  carino_ok  carino_warn  carino_fail  carino_note  carino_say  carino_em
#   info  error  caution  success  profileWarning
#   carino_rule  carino_section  carino_kv  carino_menu  carino_banner  carino_selected
#   carino_ask  carino_confirm
#   carino_step_begin  carino_step_end  carino_progress
#   carino_width  carino_pad  carino_truncate  carinoTermDemo
#
# carino_confirm returns 1 for "no", which is a value and not a failure. A host
# script running under set -e must call it in an if or a && list, never bare.
#
# SPDX-License-Identifier: AGPL-3.0-or-later
# GNU Affero General Public License v3.0 or later. Copyright (C) 2026 Miguel Carino.
# ---------------------------------------------------------------------------

# --- Resolved state ---------------------------------------------------------
# Every CT_* below is treated as read-only after carino_term_init, by convention
# and not by the readonly builtin, because carino_term_init -f has to be able to
# re-resolve them and a readonly variable would abort the whole host script with
# "readonly variable" the first time a test harness tried it.
CT_INIT=${CT_INIT:-0}          # guard, so sourcing this file twice costs nothing
CT_DEPTH=${CT_DEPTH:-0}        # 0 | 8 | 256 | 16777216
CT_DEPTH_WHY=${CT_DEPTH_WHY:-} # which rung of the ladder in 1.3.2 answered, for carino_term_selftest
CT_CHARSET=${CT_CHARSET:-ascii}
CT_COLS=${CT_COLS:-80}
CT_NARROW=${CT_NARROW:-0}
CT_INTERACTIVE=${CT_INTERACTIVE:-0}
CT_STDIN_TTY=${CT_STDIN_TTY:-0}
CT_RTL=${CT_RTL:-0}
CT_MULTIBYTE=${CT_MULTIBYTE:-0}
CT_SECTION_N=${CT_SECTION_N:-0}
CT_TTY_FD=${CT_TTY_FD:-9}
CT_KV_W=${CT_KV_W:-0}          # widest carino_kv key seen so far, so the value column stops jumping
CT_STEP_TEXT=""                # what carino_step_begin is currently showing, so carino_step_end can restate it
CT_W=0                         # scratch output of _carino_width_var, see the fork note there
CT_REPEAT=""                   # scratch output of _carino_repeat

# Colour tokens. Empty strings at depth 0, so no call site ever has to branch on
# whether colour is on. They hold a LITERAL escape character, not the two-character
# sequence \e, because read -r -p does not process %b escapes and a \e token would
# print the letters backslash-e into every prompt.
CT_RESET=""; CT_BOLD=""; CT_REV=""
CT_ACCENT=""; CT_OK=""; CT_WARN=""; CT_ERR=""; CT_INFO=""
CT_TEXT=""; CT_SEC=""; CT_MUTED=""; CT_EMPH=""

# Glyphs. See carino_term_init for the two tiers; the vocabulary is deliberately
# tiny and is documented at the assignment.
CT_G_RULE="-"; CT_G_VBAR="|"; CT_G_BLOCK="#"; CT_G_TRACK="-"; CT_G_MARK=">"

# --- Internal helpers -------------------------------------------------------
_carino_repeat ()
{
    local c="$1" n="$2" pad=""
    if (( n <= 0 )); then CT_REPEAT=""; return 0; fi
    printf -v pad '%*s' "$n" '' # %*s pads with spaces and spaces are single byte, so this is the one place a byte-width printf is correct
    CT_REPEAT=${pad// /$c}      # a pure-bash substitution rather than a seq/tr pipeline, because every fork here would be paid once per progress frame
}

_carino_width_var ()
{
    # Sets CT_W to the display width of $1. The value is returned in a global
    # rather than printed, because $( carino_width ... ) forks a subshell and
    # carino_pad is on the per-message path where the spec budgets zero forks.
    local s="$1" i n cp w=0
    if (( CT_MULTIBYTE == 0 )); then CT_W=${#s}; return 0; fi # byte mode: ${#s} counts bytes and this is documented as approximate, see the he_IL note in carino_term_init
    n=${#s}
    for (( i = 0; i < n; i++ )); do
        printf -v cp '%d' "'${s:i:1}" 2>/dev/null || cp=63 # the leading quote is printf's "value of this character" form; the fallback is '?' so a lone surrogate cannot abort the loop
        if   (( cp < 32 )) || (( cp >= 127 && cp <= 159 )); then continue   # C0/C1 controls occupy no columns
        elif (( cp >= 0x0300 && cp <= 0x036F )); then continue              # combining diacritical marks
        elif (( cp >= 0x0483 && cp <= 0x0489 )); then continue              # Cyrillic combining
        elif (( cp >= 0x0591 && cp <= 0x05BD )) || (( cp == 0x05BF )) \
          || (( cp >= 0x05C1 && cp <= 0x05C2 )) || (( cp >= 0x05C4 && cp <= 0x05C5 )) \
          || (( cp == 0x05C7 )); then continue                              # Hebrew points, he_IL is a supported fleet locale
        elif (( cp >= 0x0610 && cp <= 0x061A )) || (( cp >= 0x064B && cp <= 0x065F )) \
          || (( cp == 0x0670 )) || (( cp >= 0x06D6 && cp <= 0x06DC )) \
          || (( cp >= 0x06DF && cp <= 0x06E4 )) || (( cp >= 0x06E7 && cp <= 0x06E8 )) \
          || (( cp >= 0x06EA && cp <= 0x06ED )); then continue              # Arabic marks
        elif (( cp == 0x0711 )) || (( cp >= 0x0730 && cp <= 0x074A )) \
          || (( cp >= 0x07A6 && cp <= 0x07B0 )); then continue              # Syriac, Thaana
        elif (( cp == 0x0E31 )) || (( cp >= 0x0E34 && cp <= 0x0E3A )) \
          || (( cp >= 0x0E47 && cp <= 0x0E4E )); then continue              # Thai above/below vowels
        elif (( cp >= 0x1AB0 && cp <= 0x1AFF )) || (( cp >= 0x1DC0 && cp <= 0x1DFF )) \
          || (( cp >= 0x20D0 && cp <= 0x20F0 )); then continue              # combining extensions and marks for symbols
        elif (( cp >= 0x200B && cp <= 0x200F )) || (( cp >= 0x202A && cp <= 0x202E )) \
          || (( cp >= 0x2060 && cp <= 0x2064 )) || (( cp >= 0x206A && cp <= 0x206F )) \
          || (( cp == 0xFEFF )); then continue                              # zero-width and bidi controls
        elif (( cp >= 0xFE00 && cp <= 0xFE0F )) || (( cp >= 0xFE20 && cp <= 0xFE2F )) \
          || (( cp >= 0xE0100 && cp <= 0xE01EF )); then continue            # variation selectors and half marks
        elif (( cp >= 0x1100 && cp <= 0x115F )) || (( cp >= 0x2329 && cp <= 0x232A )) \
          || (( cp >= 0x2E80 && cp <= 0x303E )) || (( cp >= 0x3041 && cp <= 0x33FF )) \
          || (( cp >= 0x3400 && cp <= 0x4DBF )) || (( cp >= 0x4E00 && cp <= 0x9FFF )) \
          || (( cp >= 0xA000 && cp <= 0xA4CF )) || (( cp >= 0xA960 && cp <= 0xA97F )) \
          || (( cp >= 0xAC00 && cp <= 0xD7A3 )) || (( cp >= 0xF900 && cp <= 0xFAFF )) \
          || (( cp >= 0xFE10 && cp <= 0xFE19 )) || (( cp >= 0xFE30 && cp <= 0xFE6F )) \
          || (( cp >= 0xFF00 && cp <= 0xFF60 )) || (( cp >= 0xFFE0 && cp <= 0xFFE6 )) \
          || (( cp >= 0x1F300 && cp <= 0x1F64F )) || (( cp >= 0x1F900 && cp <= 0x1F9FF )) \
          || (( cp >= 0x20000 && cp <= 0x3FFFD )); then w=$(( w + 2 ))      # East Asian Wide and Fullwidth; 0x303F is deliberately outside the range because it is narrow
        else w=$(( w + 1 ))
        fi
    done
    CT_W=$w
}

_carino_num_ok ()
{
    # The gate that rejects a pty reporting "0 0", a tput cols of -1, and an
    # empty COLUMNS. Applied after EVERY rung of the width ladder, not once at
    # the end, because a bad answer from rung 2 must fall through to rung 3
    # rather than be clamped up to 20 and believed.
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 20 ))
}

_carino_resolve_depth ()
{
    # Exact precedence, evaluated top down, first match wins. Do not reorder.
    local forced=0
    case "${CARINO_TERM_COLOR:-auto}" in
        never|0|off|no)      CT_DEPTH=0;        CT_DEPTH_WHY="CARINO_TERM_COLOR=never"; return 0 ;;
        8)                   CT_DEPTH=8;        CT_DEPTH_WHY="CARINO_TERM_COLOR=8"; return 0 ;;
        256)                 CT_DEPTH=256;      CT_DEPTH_WHY="CARINO_TERM_COLOR=256"; return 0 ;;
        24bit|truecolor)     CT_DEPTH=16777216; CT_DEPTH_WHY="CARINO_TERM_COLOR=truecolor"; return 0 ;;
        always)              CT_DEPTH=16777216; CT_DEPTH_WHY="CARINO_TERM_COLOR=always"; return 0 ;;
        auto|"")             ;;
        *)                   ;; # an unrecognised spelling falls through to auto rather than turning colour off, so a typo does not silently unbrand the run
    esac
    if [[ -n "${NO_COLOR:-}" ]]; then CT_DEPTH=0; CT_DEPTH_WHY="NO_COLOR is set and non-empty"; return 0; fi # non-empty only, per the literal text on no-color.org; a user who typed "export NO_COLOR=" by accident still gets colour
    if [[ "${FORCE_COLOR:-}" == 0 ]]; then CT_DEPTH=0; CT_DEPTH_WHY="FORCE_COLOR=0"; return 0; fi
    if [[ "${CLICOLOR:-}" == 0 ]]; then CT_DEPTH=0; CT_DEPTH_WHY="CLICOLOR=0"; return 0; fi
    case "${FORCE_COLOR:-}" in
        1) CT_DEPTH=8;        CT_DEPTH_WHY="FORCE_COLOR=1"; return 0 ;;
        2) CT_DEPTH=256;      CT_DEPTH_WHY="FORCE_COLOR=2"; return 0 ;;
        3) CT_DEPTH=16777216; CT_DEPTH_WHY="FORCE_COLOR=3"; return 0 ;;
    esac
    [[ -n "${CLICOLOR_FORCE:-}" ]] && forced=1 # skips the tty test below and nothing else; the TERM checks still apply because a dumb terminal cannot render colour however hard it is forced
    case "${TERM:-}" in
        dumb|unknown|vt100|vt220|sun|"") CT_DEPTH=0; CT_DEPTH_WHY="TERM=${TERM:-unset} cannot render colour"; return 0 ;;
    esac
    if (( forced == 0 && CT_INTERACTIVE == 0 )); then CT_DEPTH=0; CT_DEPTH_WHY="not interactive (fd $CT_TTY_FD and fd 1 are both non-tty)"; return 0; fi
    case "${COLORTERM:-}" in
        truecolor|24bit) CT_DEPTH=16777216; CT_DEPTH_WHY="COLORTERM=$COLORTERM"; return 0 ;;
    esac
    case "$TERM" in
        *-256color*|alacritty|foot|xterm-kitty|*-direct*)
            CT_DEPTH=256;  CT_DEPTH_WHY="TERM=$TERM is a 256-colour name" ;;
        linux|cons25|screen|tmux|xterm|xterm-color|ansi|eterm-color|rxvt*|putty*)
            CT_DEPTH=8;    CT_DEPTH_WHY="TERM=$TERM is a 16-colour name" ;;
        *)
            CT_DEPTH=8;    CT_DEPTH_WHY="TERM=$TERM is unknown, assuming 16 colours"
            # tput is consulted HERE and nowhere else. A pure-bash case agreed with
            # tput on all 21 TERM values surveyed, tput costs ~1.0 ms against ~14 us
            # for a case, and ncurses/ncurses-bin is in no essentialPackages list in
            # setup.sh, so paying for it on a known name buys nothing. The unknown
            # arm is the only place tput knows something the case does not.
            local tc=""
            if command -v tput >/dev/null 2>&1; then tc=$(tput colors 2>/dev/null); fi
            if [[ "$tc" =~ ^[1-9][0-9]*$ ]]; then # NOT a bare exit-status check: tput colors prints -1 and exits 0 for dumb/vt100/vt220/sun, so "if tput colors" succeeds exactly where it must not
                if   (( tc >= 16777216 )); then CT_DEPTH=16777216; CT_DEPTH_WHY="tput colors=$tc raised the unknown-TERM default"
                elif (( tc >= 256 ));      then CT_DEPTH=256;      CT_DEPTH_WHY="tput colors=$tc raised the unknown-TERM default"
                fi                                 # never lowered below 8, because a wrong-but-styled run is better than an unbranded one
            fi
            ;;
    esac
    return 0
}

_carino_set_tokens ()
{
    local e=""
    printf -v e '\033' # a builtin, so this costs no fork; see the literal-ESC note at the token declarations
    CT_RESET=""; CT_BOLD=""; CT_REV=""
    CT_ACCENT=""; CT_OK=""; CT_WARN=""; CT_ERR=""; CT_INFO=""
    CT_TEXT=""; CT_SEC=""; CT_MUTED=""; CT_EMPH=""
    (( CT_DEPTH == 0 )) && return 0
    CT_RESET="${e}[0m"; CT_BOLD="${e}[1m"; CT_REV="${e}[7m"
    # SGR 2 (dim) is never emitted anywhere in this file. Dim on --text-sec drops
    # it to 4.37 contrast and dim on muted to 2.26; dim is a level, not a modifier,
    # and "below muted" is expressed as a lighter GLYPH instead.
    case "$CT_DEPTH" in
        16777216)
            CT_ACCENT="${e}[38;2;234;179;8m"    # --accent #eab308, 10.95 on black
            CT_OK="${e}[38;2;34;197;94m"        # --ok     #22c55e, 9.22
            CT_ERR="${e}[38;2;239;68;68m"       # --err    #ef4444, 5.58
            CT_INFO="${e}[38;2;56;189;248m"     # --info   #38bdf8, 9.80, promoted out of .toast.info
            CT_TEXT="${e}[38;2;255;255;255m"    # --text   #ffffff
            CT_SEC="${e}[38;2;163;163;163m"     # --text-sec #a3a3a3, 8.33
            CT_MUTED="${e}[38;2;138;138;138m"   # carino-navbar.js --cn-muted #8a8a8a, 6.08; --text-muted #666666 (3.66) and --border #262626 (1.39) are NEVER terminal foregrounds because the terminal has no lifted card to sit them on
            CT_EMPH="${e}[38;2;253;230;138m"    # .alert b #fde68a, 17.3
            ;;
        256)
            CT_ACCENT="${e}[38;5;178m"
            CT_OK="${e}[38;5;41m"
            CT_ERR="${e}[38;5;203m"
            CT_INFO="${e}[38;5;75m"
            CT_TEXT="${e}[38;5;231m"
            CT_SEC="${e}[38;5;247m"
            CT_MUTED="${e}[38;5;245m"           # 8 + 10*13 = 138 = 0x8a, so #8a8a8a maps here with zero error
            CT_EMPH="${e}[38;5;222m"
            ;;
        *)
            # The depth-8 column is HAND-ASSIGNED BY MEANING and must never be
            # regenerated by RGB distance. Nearest-RGB sends --ok #22c55e to CYAN
            # (d=84.1, beating both greens at 115.6 and 121.5) and --err #ef4444 to
            # the VT's brown. If you are here to "fix" this table with a distance
            # function, this comment is the reason not to.
            # Only 31/32/33 are emitted at this depth. No 9x brights and no 90:
            # Fedora and RHEL VT default fonts carry 512 glyphs, which steals the
            # intensity bit, so 93 renders brown and 90 renders black on black.
            # Everything else is the terminal's own default foreground, which is
            # also the most on-brand palette in the whole document: one accent.
            CT_ACCENT="${e}[33m"
            CT_OK="${e}[32m"
            CT_ERR="${e}[31m"
            CT_EMPH="${e}[33m"
            CT_INFO=""; CT_TEXT=""; CT_SEC=""; CT_MUTED=""
            ;;
    esac
    CT_WARN="$CT_ACCENT" # --warn and --accent are the same #eab308 on the web and the terminal does not get to disagree
    return 0
}

_carino_set_glyphs ()
{
    if [[ "$CT_CHARSET" == unicode ]]; then
        # The vocabulary is the VERIFIED intersection of the seven console fonts
        # surveyed: light box drawing and the full block. Nothing else. No
        # check marks, no bullets, no arrows, no rounded corners, no braille and
        # no emoji, because every one of those is missing from Fedora's eurlatgr
        # or Debian's Lat2-Terminus16 and renders as a blank or a tofu box on a
        # bare-metal console.
        CT_G_RULE="─"   # U+2500
        CT_G_VBAR="│"   # U+2502, reserved, no v1 primitive draws it
        CT_G_BLOCK="█"  # U+2588, the only block present in every font surveyed
    else
        CT_G_RULE="-"; CT_G_VBAR="|"; CT_G_BLOCK="#"
    fi
    CT_G_TRACK="-"  # ASCII in BOTH tiers: the shaded blocks would be the natural track but U+2591/2/3 are unverified outside eurlatgr
    CT_G_MARK=">"   # ASCII in BOTH tiers: U+25B8, U+25B6 and U+2192 are all absent from Fedora's default console font
}

# --- Lifecycle --------------------------------------------------------------
carino_term_init ()
{
    # shellcheck disable=SC2120  # -f is a documented public argument; shellcheck only sees the argument-less calls
    [[ "${1:-}" == "-f" ]] && CT_INIT=0 # ${1:-} and not $1, so a host script running under set -u does not abort on an argument-less call
    (( CT_INIT )) && return 0

    local v="é"
    (( ${#v} == 1 )) && CT_MULTIBYTE=1 || CT_MULTIBYTE=0 # no fork, immune to the utf8/UTF-8 spelling split (891 locales here are spelled en_US.utf8), immune to LC_ALL=C beating LANG, and it tests exactly the property _carino_width_var depends on

    CT_TTY_FD=${CARINO_TERM_TTY_FD:-9}
    CT_INTERACTIVE=0
    # Exactly these two checks and no /dev/tty fallback. setup.sh:9 turns fd 1 into
    # a pipe for the whole run, so [[ -t 1 ]] is false forever and fd 9 is the
    # snapshot of the real stdout taken before that redirect. A /dev/tty fallback
    # would over-report under ./setup.sh > file and write escapes into a plain
    # redirect. This must never be evaluated inside $( ... ): command substitution
    # makes fd 1 a pipe regardless of what the host script did.
    { [[ -t "$CT_TTY_FD" ]]; } 2>/dev/null && CT_INTERACTIVE=1
    (( CT_INTERACTIVE == 0 )) && [[ -t 1 ]] && CT_INTERACTIVE=1
    [[ -t 0 ]] && CT_STDIN_TTY=1 || CT_STDIN_TTY=0 # survives the tee redirect and is the ONLY reliable "a human can answer" signal; interactivity is not promptability

    _carino_resolve_depth

    case "${CARINO_TERM_CHARSET:-}" in
        ascii)   CT_CHARSET=ascii ;;
        unicode) CT_CHARSET=unicode ;;
        *)
            if   (( CT_MULTIBYTE == 0 )); then CT_CHARSET=ascii # note he_IL with no suffix resolves to ISO-8859-8, so a supported fleet locale legitimately lands in byte mode
            else
                case "${TERM:-}" in
                    dumb|unknown|vt100|vt220|sun|"") CT_CHARSET=ascii ;;
                    *) CT_CHARSET=unicode ;;
                esac
            fi
            ;;
    esac

    local raw=""
    if _carino_num_ok "${CARINO_TERM_WIDTH:-}"; then raw="$CARINO_TERM_WIDTH"; fi
    if [[ -z "$raw" ]] && (( CT_INTERACTIVE )); then
        local sz="" szfd=1
        { [[ -t "$CT_TTY_FD" ]]; } 2>/dev/null && szfd="$CT_TTY_FD" # prefer the snapshot fd but fall back to fd 1, because a host script without the exec 9>&1 line would otherwise hand stty a closed descriptor and lose the real width
        sz=$( { stty size <&"$szfd"; } 2>/dev/null ) # read-only use of the snapshot fd; this library never WRITES to fd 9, which is what keeps decision 1 (one output stream) intact
        sz=${sz#* }
        _carino_num_ok "$sz" && raw="$sz"
    fi
    if [[ -z "$raw" ]]; then _carino_num_ok "${COLUMNS:-}" && raw="$COLUMNS"; fi
    if [[ -z "$raw" ]] && command -v tput >/dev/null 2>&1; then
        local tw=""; tw=$(tput cols 2>/dev/null)
        _carino_num_ok "$tw" && raw="$tw"
    fi
    [[ -n "$raw" ]] || raw=80
    CT_NARROW=0
    if (( raw < 40 )); then CT_NARROW=1; CT_COLS=40; else CT_COLS=$raw; fi # a 40-column serial console gets no rules and no padding rather than a wrapped mess
    (( CT_COLS > 100 )) && CT_COLS=100 # no SIGWINCH handling: a setup script does not need to reflow, and a trap would fire mid-progress-frame

    case "${CARINO_TERM_RTL:-}" in
        1) CT_RTL=1 ;;
        0) CT_RTL=0 ;;
        *)
            case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
                he*|ar*|fa*|ur*) CT_RTL=1 ;;
                *) CT_RTL=0 ;;
            esac
            ;;
    esac

    _carino_set_tokens
    _carino_set_glyphs
    CT_INIT=1
    return 0
}

carino_term_cjk_ok ()
{
    # Returns 1 when CJK and Hebrew cannot be rendered. No bare-metal console font
    # tested contains a single CJK or Hebrew glyph, so a ja_JP user on TERM=linux
    # sees blanks. This function EXPOSES that fact and changes nothing: silently
    # substituting English is worse than an unreadable menu the user can fix.
    (( CT_INIT )) || carino_term_init
    (( CT_MULTIBYTE )) || return 1
    case "${TERM:-}" in linux|cons25|dumb|unknown|vt100|vt220|sun|"") return 1 ;; esac
    return 0
}

carino_term_selftest ()
{
    (( CT_INIT )) || carino_term_init
    carino_rule "carino-term selftest"
    (( CT_KV_W < 12 )) && CT_KV_W=12 # carino_kv only knows the widest key it has ALREADY seen, so the first two rows would print unpadded and the table would look broken; priming the column to the longest label below is the fix, not a change to carino_kv's contract
    carino_kv "depth"       "$CT_DEPTH"
    carino_kv "depth reason" "$CT_DEPTH_WHY"
    carino_kv "charset"     "$CT_CHARSET"
    carino_kv "cols"        "$CT_COLS"
    carino_kv "narrow"      "$CT_NARROW"
    carino_kv "interactive" "$CT_INTERACTIVE"
    carino_kv "stdin tty"   "$CT_STDIN_TTY"
    carino_kv "tty fd"      "$CT_TTY_FD"
    carino_kv "multibyte"   "$CT_MULTIBYTE"
    carino_kv "rtl"         "$CT_RTL"
    carino_kv "gutter"      "${CARINO_TERM_GUTTER:-0}"
    carino_kv "cjk ok"      "$(carino_term_cjk_ok && echo yes || echo no)"
    if (( CT_DEPTH == 0 )); then # CT_DEPTH and never CT_INTERACTIVE: CARINO_TERM_COLOR=always, FORCE_COLOR=3 and CLICOLOR_FORCE all leave CT_INTERACTIVE at 0 while colour is fully on, so gating on CT_INTERACTIVE prints "no colour" in 24-bit colour directly above the coloured token row that disproves it
        carino_msg note "No colour because nothing looks like a terminal. If this is a host script with a tee on stdout, add 'exec 9>&1' ABOVE the redirect; otherwise set CARINO_TERM_COLOR=always."
    fi
    printf '%s\n' "${CT_ACCENT}accent${CT_RESET} ${CT_OK}ok${CT_RESET} ${CT_ERR}err${CT_RESET} ${CT_INFO}info${CT_RESET} ${CT_TEXT}text${CT_RESET} ${CT_SEC}sec${CT_RESET} ${CT_MUTED}muted${CT_RESET} ${CT_EMPH}emph${CT_RESET} ${CT_BOLD}bold${CT_RESET} ${CT_REV}rev${CT_RESET}"
    printf '%s\n' "${CT_MUTED}rule[${CT_G_RULE}] vbar[${CT_G_VBAR}] block[${CT_G_BLOCK}] track[${CT_G_TRACK}] mark[${CT_G_MARK}]${CT_RESET}"
    return 0
}

# --- Width, padding, truncation ---------------------------------------------
# printf field widths and ${#s} are BANNED from every layout path below.
# printf '%-12s' pads by bytes, so "Instalacion" with an accent and a katakana
# label both receive zero padding; printf '%.10s' splits a UTF-8 sequence and
# renders a replacement character. Everything here goes through _carino_width_var.
carino_width ()
{
    (( CT_INIT )) || carino_term_init
    _carino_width_var "${1:-}"
    printf '%d' "$CT_W"
}

carino_pad ()
{
    (( CT_INIT )) || carino_term_init
    local s="${1:-}" n="${2:-0}" side="${3:-right}"
    if (( CT_NARROW || CT_RTL )); then printf '%s' "$s"; return 0; fi # never emit a padded column in RTL: the frame survives (box characters are bidi class ON and resolve to L at a paragraph edge) but the label and value columns SWAP on VTE >= 0.57 and Konsole while xterm, alacritty, kitty, foot and the VT leave them alone, and this library cannot detect which side of that line it is on
    _carino_width_var "$s"
    local fill=$(( n - CT_W ))
    (( fill <= 0 )) && { printf '%s' "$s"; return 0; }
    _carino_repeat ' ' "$fill"
    if [[ "$side" == left ]]; then printf '%s%s' "$CT_REPEAT" "$s"; else printf '%s%s' "$s" "$CT_REPEAT"; fi
}

carino_truncate ()
{
    (( CT_INIT )) || carino_term_init
    local s="${1:-}" n="${2:-0}" i len out="" w=0 cw
    _carino_width_var "$s"
    (( CT_W <= n )) && { printf '%s' "$s"; return 0; }
    (( n <= 3 )) && { printf '%s' "..."; return 0; }
    len=${#s}
    for (( i = 0; i < len; i++ )); do
        _carino_width_var "${s:i:1}"; cw=$CT_W
        (( w + cw > n - 3 )) && break
        out+="${s:i:1}" # ${s:i:1} is character based in a multibyte locale, which is why this loop can never split a UTF-8 sequence the way printf '%.Ns' does
        w=$(( w + cw ))
    done
    printf '%s...' "$out"
}

# --- Messages ---------------------------------------------------------------
carino_msg ()
{
    (( CT_INIT )) || carino_term_init
    local kind="${1:-}" tag col
    case "$kind" in
        ok)    tag='[ ok ]'; col="$CT_OK" ;;
        warn)  tag='[warn]'; col="$CT_WARN" ;;
        fail)  tag='[fail]'; col="$CT_ERR" ;;
        note)  tag='[note]'; col="$CT_INFO" ;;
        busy)  tag='[ .. ]'; col="$CT_MUTED" ;; # the in-progress tag carino_step_begin shows, so carino_step_end can overwrite it in place and the prose column never moves
        plain) printf '%b\n' "${CT_TEXT}${2:-}${CT_RESET}"; return 0 ;;
        say|*) printf '%b\n' "      ${CT_SEC}${2:-}${CT_RESET}"; return 0 ;; # six spaces, the same width as a tag, so narration lines up under the tagged ones
    esac
    # The tag is reset before the prose starts, so at depth 8 (where CT_TEXT is
    # deliberately empty) the prose falls back to the terminal's own foreground
    # instead of inheriting the tag's green or red for the rest of the line.
    printf '%b\n' "${col}${tag}${CT_RESET} ${CT_TEXT}${2:-}${CT_RESET}"
}

carino_ok   () { carino_msg ok   "${1:-}"; }
carino_warn () { carino_msg warn "${1:-}"; }
carino_fail () { carino_msg fail "${1:-}"; }
carino_note () { carino_msg note "${1:-}"; }
carino_say  () { carino_msg say  "${1:-}"; }

carino_em ()
{
    (( CT_INIT )) || carino_term_init
    printf '%s' "${CT_EMPH}${1:-}${CT_RESET}${CT_TEXT}" # mirrors .alert b { color: #fde68a }; the reset before CT_TEXT matters at depth 8 where CT_TEXT is empty and the gold would otherwise run to end of line
}

# --- Legacy names, exact compatibility --------------------------------------
# These four shadow the bodies in setup.sh:16-19 and macos.sh:7-10. Output shape
# is byte identical apart from the escape sequences themselves: one line, same
# text, no prefix, no gutter, no wrap. All 212 call sites stay untouched.
#
# Rules that are load bearing and must not be "tidied":
#  * "$1" and never "$*". setup.sh:1064 is `caution $NAME` unquoted, so with
#    NAME="Fedora Linux" only "Fedora" prints today and "$*" would silently
#    change the output of a line test.sh reads.
#  * printf '%b\n' and not echo -e. The 16 translated menu strings and
#    setup.sh:752 encode their layout as literal \n. echo -e "-n" prints nothing
#    because echo eats it as an option, while printf '%b\n' "-n" prints -n.
#  * One printf per call, so a colour run never spans a line boundary in a way
#    the log filter can split.
#  * No wrapping and no reflow, ever. The Gentoo refusal at setup.sh:243 is a
#    380-character single line and test.sh:85 greps "not supported" inside it; a
#    newline at column 80 splits the phrase and fails all 15 declined-distro
#    assertions.
# info() is grey --text-sec and NOT blue and NOT gold: it carries all nine
# localized menus, and a coloured menu is wrong on both counts. The promoted
# --info #38bdf8 exists as a token and belongs to carino_note alone.
# ${1:-} rather than a bare $1 throughout: identical output whenever an argument
# is present, and it does not abort a host script that runs under set -u.
info    () { (( CT_INIT )) || carino_term_init; if [[ "${CARINO_TERM_GUTTER:-0}" == 1 ]]; then carino_msg say  "${1:-}"; else printf '%b\n' "${CT_SEC}${1:-}${CT_RESET}"; fi; }
error   () { (( CT_INIT )) || carino_term_init; if [[ "${CARINO_TERM_GUTTER:-0}" == 1 ]]; then carino_msg fail "${1:-}"; else printf '%b\n' "${CT_ERR}${1:-}${CT_RESET}"; fi; }
caution () { (( CT_INIT )) || carino_term_init; if [[ "${CARINO_TERM_GUTTER:-0}" == 1 ]]; then carino_msg warn "${1:-}"; else printf '%b\n' "${CT_ACCENT}${1:-}${CT_RESET}"; fi; }
success () { (( CT_INIT )) || carino_term_init; if [[ "${CARINO_TERM_GUTTER:-0}" == 1 ]]; then carino_msg ok   "${1:-}"; else printf '%b\n' "${CT_OK}${1:-}${CT_RESET}"; fi; }
# error() writes to STDOUT and not stderr on purpose: moving it would reorder it
# against setup.sh's tee and change what test.sh's $( ... 2>&1 ) captures.
profileWarning () { [[ -n "${2:-}" ]] || caution "No native $1 package list exists for '${DISTRIBUTION:-this system}', only the shared base packages and the Flatpaks below will be installed."; }

# --- Structure --------------------------------------------------------------
carino_rule ()
{
    (( CT_INIT )) || carino_term_init
    local label="${1:-}" lead n
    (( CT_NARROW )) && { printf '\n'; return 0; } # a rule on a 40-column console is noise, a blank line is the same separation for free
    if [[ -z "$label" ]]; then
        _carino_repeat "$CT_G_RULE" "$CT_COLS"
        printf '%s\n' "${CT_MUTED}${CT_REPEAT}${CT_RESET}"
        return 0
    fi
    label=${label^^}
    _carino_width_var "$label"
    n=$(( CT_COLS - CT_W - 4 ))
    (( n < 0 )) && n=0
    _carino_repeat "$CT_G_RULE" 2; lead="$CT_REPEAT"
    _carino_repeat "$CT_G_RULE" "$n"
    printf '%s\n' "${CT_MUTED}${lead}${CT_RESET} ${CT_SEC}${label}${CT_RESET} ${CT_MUTED}${CT_REPEAT}${CT_RESET}"
}

carino_section ()
{
    (( CT_INIT )) || carino_term_init
    local n
    CT_SECTION_N=$(( CT_SECTION_N + 1 ))
    printf -v n '%02d' "$CT_SECTION_N"
    # Open ended numbering with no denominator. A branch-heavy installer cannot
    # know its step count up front and a wrong "03/12" is worse than none.
    # The leading blank line is the terminal's z-axis: vertical isolation is the
    # only way the web's elevation transfers to a text stream.
    local title="${1:-}"
    printf '\n%s\n' "${CT_ACCENT}${n}${CT_RESET} ${CT_MUTED}${CT_G_MARK}${CT_RESET} ${CT_ACCENT}${CT_BOLD}${title^^}${CT_RESET}"
}

carino_kv ()
{
    (( CT_INIT )) || carino_term_init
    local k="${1:-}" v="${2:-}"
    if (( CT_RTL || CT_NARROW )); then printf '%s\n' "${CT_MUTED}${k}:${CT_RESET} ${CT_TEXT}${v}${CT_RESET}"; return 0; fi # see the column-swap note in carino_pad; the library never emits a multi-field line in RTL
    _carino_width_var "$k"
    (( CT_W > CT_KV_W )) && CT_KV_W=$CT_W
    local padded; padded=$(carino_pad "$k" "$CT_KV_W") # the one fork on this path; carino_kv is a header primitive called a handful of times, not a per-message one
    printf '%s\n' "${CT_MUTED}${padded}${CT_RESET}  ${CT_TEXT}${v}${CT_RESET}"
}

carino_menu ()
{
    (( CT_INIT )) || carino_term_init
    local expanded line
    printf -v expanded '%b' "${1:-}" # the menu strings encode their layout as literal \n, so expand once here and print with %s below rather than %b twice, which would eat a backslash a translator wrote on purpose
    printf '\n'
    # A PASS-THROUGH renderer and not a list renderer. It must not generate or
    # renumber items: the digits live inside 16 translated strings and test.sh:19
    # scrapes them out of the source. It must not box, pad, centre or right align:
    # ${#s} is 13 for a ja line occupying 23 columns and he_IL reorders. It must
    # not alter the "^N. " shape, because test.sh:163 is a NEGATIVE assertion on
    # it that would start passing vacuously if the shape changed.
    while IFS= read -r line; do
        printf '%s\n' "${CT_SEC}${line}${CT_RESET}"
    done <<< "$expanded"
}

carino_banner ()
{
    (( CT_INIT )) || carino_term_init
    # No injected letter spacing. The .guide-hero .kicker 0.35em tic is the most
    # recognisable Carino typographic gesture and it is rejected here: it costs
    # horizontal room on a 40-column serial console and it breaks copy-paste and
    # grep for a tool people run over SSH.
    printf '%s\n' "${CT_ACCENT}${CT_BOLD}CARINO SYSTEMS${CT_RESET}"
    carino_rule
}

carino_selected ()
{
    (( CT_INIT )) || carino_term_init
    # The exact analogue of the web's .btn-primary inversion, background:
    # var(--accent) over color:#050505. Hover has no terminal analogue and is not
    # modelled; disabled is not modelled either because SGR 2 is banned.
    printf '%s\n' "${CT_ACCENT}${CT_REV} ${CT_G_MARK} ${1:-} ${CT_RESET}"
}

# --- Prompts ----------------------------------------------------------------
# Both of these use read -r -p and colour ONLY inside the -p argument. Bash prints
# a read -p prompt only when stdin is a terminal and writes it to STDERR. That
# free suppression is what keeps prompt strings out of every test.sh capture and
# out of the DRY-RUN: line counts; a printf-based prompt would start emitting
# them. Neither function writes anything to stdout.
carino_ask ()
{
    (( CT_INIT )) || carino_term_init
    local prompt="${1:-}" var="${2:-}" def="${3:-}" ans="" p
    if [[ "${NONINTERACTIVE:-0}" == 1 ]] || (( CT_STDIN_TTY == 0 )); then
        caution "Non-interactive run: ${var}=${def} (default: ${def})." # the exact existing phrasing, because test.sh:202 greps it verbatim and the file's whole contract is that every skipped prompt names the default it took
        printf -v "$var" '%s' "$def"
        return 0
    fi
    p="${CT_ACCENT}${CT_G_MARK}${CT_RESET} ${CT_TEXT}${prompt}${CT_RESET} "
    [[ -n "$def" ]] && p+="${CT_MUTED}[${def}]${CT_RESET} "
    read -r -p "$p" ans
    [[ -n "$ans" ]] || ans="$def"
    printf -v "$var" '%s' "$ans"
    return 0
}

carino_confirm ()
{
    (( CT_INIT )) || carino_term_init
    # NAME is an addition to the spec signature: the non-interactive announcement
    # has to say "<thing>=<value>" and a yes/no question has no variable name of
    # its own to put there. It defaults to "answer" so the two-argument form in
    # the spec still works unchanged.
    local prompt="${1:-}" def="${2:-n}" name="${3:-answer}" ans="" p suffix word
    if [[ "$def" == y ]]; then suffix='[Y/n]'; word=yes; else suffix='[y/N]'; word=no; fi
    if [[ "${NONINTERACTIVE:-0}" == 1 ]] || (( CT_STDIN_TTY == 0 )); then
        caution "Non-interactive run: ${name}=${word} (default: ${word})."
        [[ "$def" == y ]]
        return
    fi
    p="${CT_ACCENT}${CT_G_MARK}${CT_RESET} ${CT_TEXT}${prompt}${CT_RESET} ${CT_MUTED}${suffix}${CT_RESET} "
    read -r -p "$p" ans
    [[ -n "$ans" ]] || ans="$def"
    [[ "$ans" == [Yy]* ]]
}

# --- Motion -----------------------------------------------------------------
# The whole vocabulary is a bare carriage return plus spaces for erasure. No
# \e[2K, no cursor addressing, no scroll regions, no \e[?25l. CR-and-overwrite
# renders identically on the bare-metal VT and under TERM=dumb, needs no CSI at
# all, and collapses to one clean line in the log under the s/.*\r\([^\n]\)/\1/
# branch of setup.sh's tee filter.
carino_step_begin ()
{
    (( CT_INIT )) || carino_term_init
    CT_STEP_TEXT="${1:-}"
    if (( CT_INTERACTIVE )); then
        printf '%s' "${CT_MUTED}[ .. ]${CT_RESET} ${CT_SEC}${1:-}${CT_RESET}"
    else
        carino_msg busy "${1:-}" # not a tty, so print a whole line now and let carino_step_end add its own below rather than leaving a half line in a log
    fi
}

carino_step_end ()
{
    (( CT_INIT )) || carino_term_init
    local r="${1:-ok}" t="${2:-$CT_STEP_TEXT}" kind
    case "$r" in
        ok)   kind=ok ;;
        fail) kind=fail ;;
        skip) kind=say ;; # a skipped step is narration, not a warning; painting it gold would put a false alarm in the scrollback
        *)    kind=say ;;
    esac
    if (( CT_INTERACTIVE )); then
        _carino_repeat ' ' $(( CT_COLS - 1 )) # CT_COLS-1 and not CT_COLS, because writing exactly the terminal width wraps and the following \r then lands on the wrong row
        printf '\r%s\r' "$CT_REPEAT"
    fi
    CT_STEP_TEXT=""
    carino_msg "$kind" "$t"
}

carino_progress ()
{
    (( CT_INIT )) || carino_term_init
    local cur="${1:-0}" total="${2:-1}" label="${3:-}" barw filled pct head track line # cur and not done: "done" is a bash reserved word and "local done=..." is a hard syntax error that would break the whole file at source time
    [[ "$total" =~ ^[0-9]+$ ]] && (( total > 0 )) || total=1
    [[ "$cur" =~ ^[0-9]+$ ]] || cur=0
    (( cur > total )) && cur=$total
    pct=$(( cur * 100 / total ))
    if (( CT_INTERACTIVE == 0 )); then
        (( pct == 0 || pct == 100 )) || return 0 # a log does not need 98 intermediate frames, and a plan run under test.sh's timeout does not need to pay for them
        carino_msg say "${label:+$label }${pct}%"
        return 0
    fi
    barw=$(( CT_COLS - 24 ))
    (( barw > 40 )) && barw=40
    (( barw < 10 )) && barw=10
    filled=$(( cur * barw / total ))
    # The FULL track is drawn first in muted with a gold head travelling over it,
    # never a bar growing out of nothing. This is carino-anim.css:45-53 stated as
    # a house rule: the whole shape is always present, so the bright part reads as
    # a pass across something that exists.
    _carino_repeat "$CT_G_BLOCK" "$filled"; head="$CT_REPEAT"
    _carino_repeat "$CT_G_TRACK" $(( barw - filled )); track="$CT_REPEAT"
    line="${CT_MUTED}[${CT_RESET}${CT_ACCENT}${head}${CT_MUTED}${track}${CT_RESET}${CT_MUTED}]${CT_RESET} ${CT_SEC}${pct}%${label:+ $label}${CT_RESET}"
    printf '\r%s' "$line" # %s and not %b, so a literal percent sign in the composed line is never read as a format specifier
    (( pct == 100 )) && printf '\n'
    return 0
}

# --- Demo -------------------------------------------------------------------
carinoTermDemo ()
{
    carino_term_init
    carino_banner
    carino_term_selftest

    carino_section "messages"
    carino_ok   "Flatpak remote flathub is configured."
    carino_warn "No native gaming package list exists for 'openSUSE'."
    carino_fail "Gentoo is not supported: no package list, no repository and no tested path exist for it here."
    carino_note "dnf will use 8 parallel downloads for this run."
    carino_say  "Installing ffmpeg..."
    carino_msg plain "A plain line, brand white, no gutter."
    carino_ok   "Installed $(carino_em ffmpeg) from RPM Fusion."

    carino_section "legacy names"
    info    "info() is grey now, it carries the menus."
    error   "error() is the token red, 5.58 on black instead of 1.92."
    caution "caution() is Carino gold."
    success "success() is the token green."
    profileWarning "gaming" ""

    carino_section "structure"
    carino_rule
    carino_rule "network"
    carino_kv "distribution" "Fedora Linux 42"
    carino_kv "kernel"       "6.15.4-200.fc42.x86_64"
    carino_kv "arch"         "x86_64"
    carino_selected "3. Corporate"
    carino_menu "1. Technical setup\n2. Purpose setup\n3. Exit"

    carino_section "width helpers"
    carino_kv "ascii"    "$(carino_width 'Installation') columns"
    carino_kv "accented" "$(carino_width 'Instalación') columns"
    carino_kv "katakana" "$(carino_width 'インストール') columns"
    carino_kv "truncated" "$(carino_truncate 'インストールしています、お待ちください' 20)"
    carino_kv "padded"   "[$(carino_pad 'ja' 12)]"

    carino_section "motion"
    carino_step_begin "Refreshing repository metadata"
    carino_step_end ok
    carino_step_begin "Layering packages with rpm-ostree"
    carino_step_end fail "rpm-ostree refused: a deployment is already staged."
    carino_step_begin "Configuring Windows shares"
    carino_step_end skip "No server name was given."
    local i
    for i in 0 25 50 75 100; do carino_progress "$i" 100 "packages"; done

    carino_section "prompts"
    carino_say "carino_ask and carino_confirm write nothing to stdout; run them by hand on a tty to see the prompts."
    return 0
}
