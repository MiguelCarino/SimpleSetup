# Carino Terminal Design System

The terminal counterpart to [branding.carino.systems](https://branding.carino.systems). Same tokens, same
grammar, same restraint — expressed in ANSI instead of CSS, so that `setup.sh`, `macos.sh`,
`tools/check-packages.sh` and every future Carino shell script look like one product rather than four scripts
that each happened to pick red, green and yellow.

Two files, both sourced, both self-contained:

| File | What it is |
| --- | --- |
| `carino-term.sh` | Colour tokens, glyphs, message primitives, structure, prompts, motion. The *look*. |
| `carino-probe.sh` | A read-only fact provider: OS, CPU, memory, GPU, power, disk, network, bandwidth. The *facts*. |

They are independent. `carino-probe.sh` uses `carino-term.sh` if it happens to be loaded and falls back to
`printf` if it is not. `carino-term.sh` never references the probe. Two files that source each other is a trap,
and the dependency here is one-way and optional by design.

---

## 1. How you get it

Shared fleet code travels as **copied files per repository**, never as a package. `SimpleSetup` already carries
`carino-navbar.js`, `carino-clock.js`, `carino-lang.js` and `fonts/carino-fonts.css` this way. `carino-term.sh`
and `carino-probe.sh` join them under exactly the same rule: copy the file in, commit it, no installation step,
no dependency beyond what a minimal system already has.

The complication is that the documented install path for `setup.sh` is

```bash
bash <(curl -s https://setup.carino.systems/setup.sh)
```

There is no checkout. `BASH_SOURCE[0]` is `/dev/fd/63` and its dirname is `/dev/fd`, so `source ./carino-term.sh`
cannot work. The loader therefore has three rungs — local file, HTTPS fetch, built-in shim — and this exact block
is what every Carino script should copy:

```bash
carinoLoad ()
{
    local lib="$1" dir="${BASH_SOURCE[0]%/*}"
    [[ "$dir" == "${BASH_SOURCE[0]}" ]] && dir="." # %/* is suffix removal, not dirname: with no slash in the path it returns the filename unchanged, and "bash setup.sh" from the repo root is exactly how test.sh invokes this file
    [[ -f "$dir/$lib" && -r "$dir/$lib" ]] && { . "$dir/$lib"; return 0; } # a repo checkout or a fleet copy sitting beside the script, which is the normal case for every repo except the curl one-liner
    command -v curl >/dev/null 2>&1 || return 1
    local src; src=$(curl -fsSL --max-time 10 "https://setup.carino.systems/$lib" 2>/dev/null) || return 1
    [[ -n "$src" ]] || return 1
    { . /dev/stdin <<<"$src"; } 2>/dev/null || return 1 # a herestring rather than source <(curl ...), so a 404 body is caught by -f before anything is evaluated, and stderr is discarded so a truncated body cannot print ": line 41: syntax error" into the log and trip test.sh:147
    return 0
}
carinoLoad carino-term.sh  && declare -F carino_msg   >/dev/null 2>&1 || carinoTermShim  # the declare check catches a body that was truncated mid file: -f only proves the HTTP status, not that the last function closed
carinoLoad carino-probe.sh && declare -F carino_probe >/dev/null 2>&1 || carinoProbeShim
carino_term_init # idempotent, and every primitive self initialises anyway, so this is good manners rather than a requirement
```

The `dir="."` line is load-bearing and must not be simplified away: `${BASH_SOURCE[0]%/*}` is suffix removal, not
`dirname`, so an invocation with no slash in the path — `bash setup.sh dry-run`, which is exactly how `test.sh`
runs this file — leaves `dir` as `setup.sh`, the local rung stats `setup.sh/carino-term.sh`, misses, and every
offline dry run falls through to the network rung instead.

Local first, because a developer's edit must take effect without a deploy. Fetch second, from the same origin
that already served the script the user piped into bash — no checksum pin, because a pinned hash breaks on every
library update and the fetch inherits exactly the trust the user already extended. Shim third, so a network
hiccup can never stop a setup run over a cosmetic dependency. The shim is described in
[INTEGRATION-PLAN.md](INTEGRATION-PLAN.md) §4 and is a hard API contract: **every public name in this document
must exist in the shim.**

`carino_term_init` is idempotent and every primitive self-initialises on first use, so calling it explicitly is
good manners rather than a requirement.

---

## 2. The tokens

Nine colour tokens. Role-first names, bare abbreviations for status — the same grammar as `carino-branding.css`.
Every one is a shell variable holding a complete escape sequence, or **the empty string** when colour is off, so
call sites never branch on whether colour is available.

| Token | Web source | 24-bit | 256 | 16-colour | Contrast on `#000` |
| --- | --- | --- | --- | --- | --- |
| `CT_ACCENT` | `--accent` `#eab308` | `\e[38;2;234;179;8m` | `\e[38;5;178m` | `\e[33m` | 10.95 |
| `CT_WARN` | `--warn` `#eab308` — alias of `CT_ACCENT` | — | — | — | 10.95 |
| `CT_OK` | `--ok` `#22c55e` | `\e[38;2;34;197;94m` | `\e[38;5;41m` | `\e[32m` | 9.22 |
| `CT_ERR` | `--err` `#ef4444` | `\e[38;2;239;68;68m` | `\e[38;5;203m` | `\e[31m` | 5.58 |
| `CT_INFO` | `--info` `#38bdf8` (from `.toast.info`) | `\e[38;2;56;189;248m` | `\e[38;5;75m` | *(empty)* | 9.80 |
| `CT_TEXT` | `--text` `#ffffff` | `\e[38;2;255;255;255m` | `\e[38;5;231m` | *(empty)* | 21.0 |
| `CT_SEC` | `--text-sec` `#a3a3a3` | `\e[38;2;163;163;163m` | `\e[38;5;247m` | *(empty)* | 8.33 |
| `CT_MUTED` | `carino-navbar.js:53` `--cn-muted` `#8a8a8a` | `\e[38;2;138;138;138m` | `\e[38;5;245m` | *(empty)* | 6.08 |
| `CT_EMPH` | `carino-branding.css:289` `.alert b` `#fde68a` | `\e[38;2;253;230;138m` | `\e[38;5;222m` | `\e[33m` | 17.3 |

Plus three attributes: `CT_BOLD`, `CT_REV`, `CT_RESET`.

At `CT_DEPTH=0` **every one of them is the empty string, `CT_RESET` included.**

The table writes the sequences as `\e[…m` for legibility, but the variables hold a **literal ESC byte**, not the
two-character `\e`. That is deliberate: `read -r -p` does not process `%b` escapes, so a `\e`-spelled token would
print the four characters `\e[3` into every prompt. It also means `printf '%s'` and `printf '%b'` both render a
token correctly.

### Three rules, each with the bug it prevents

**The 16-colour column is hand-assigned by meaning, never by RGB distance.** A nearest-colour function sends
`--ok #22c55e` to **cyan** (distance 84.1, beating both greens at 115.6 and 121.5) and `--err #ef4444` to the
VT's brown. Green must be green. If you ever find yourself writing a distance function to "fix" this table, the
table is right and the function is wrong.

**`--text-muted #666666` and `--border #262626` are never used as terminal foregrounds.** They score 3.66 and
1.39 on black. The web gets away with them because muted text always sits on a lifted card; the terminal has no
card. `#8a8a8a` is the fleet's own published answer for a flat background — it is what `carino-navbar.js` uses —
and it maps to x256 index 245 with *zero* error (`8 + 10·13 = 138 = 0x8a`).

**Never stack SGR 2 (dim) on an already-dimmed token.** Dim on `--text-sec` drops it to 4.37; dim on muted gives
2.26. Dim is a level, not a modifier. The library does not emit SGR 2 anywhere, which also means *disabled* has
no terminal analogue and is not modelled.

### Background

Always `#000000`. `carino-branding.css:461` hardcodes `.terminal { background: #000 }`, not `var(--bg)`, and
every contrast number above is measured against pure black. **The library assumes a dark terminal and never
tries to detect otherwise.** OSC 11 needs a raw tty read with a timeout, many terminals ignore it, and fd 0 may
be a pipe. A light-terminal user sets `CARINO_TERM_COLOR=never`. That is the whole of the light-mode story and it
is deliberate.

---

## 3. Degradation

Two axes, resolved once, never re-read.

### 3.1 Colour depth — `CT_DEPTH`

`0` · `8` · `256` · `16777216`. First match wins, top down:

1. `CARINO_TERM_COLOR` — `never|0` → 0; `always` → 24-bit; `8|256|24bit|truecolor` → that depth; `auto`/unset → fall through.
2. `NO_COLOR` set **and non-empty** → 0. An empty `NO_COLOR` is ignored, per no-color.org's literal wording — a user who typed `export NO_COLOR=` by accident expects colour.
3. `FORCE_COLOR=0` → 0. `CLICOLOR=0` → 0.
4. `FORCE_COLOR` ∈ {1,2,3} → 8 / 256 / 16777216. `CLICOLOR_FORCE` non-empty → skip the tty test.
5. `TERM` ∈ {`dumb`, `unknown`, `vt100`, `vt220`, `sun`, empty} → 0.
6. `CT_INTERACTIVE == 0` → 0.
7. `COLORTERM` ∈ {`truecolor`, `24bit`} → 16777216.
8. `TERM` ladder: `*-256color*|alacritty|foot|xterm-kitty|*-direct*` → 256; `linux|cons25|screen|tmux|xterm|xterm-color|ansi|eterm-color|rxvt*|putty*` → 8; **anything else → 8, never 0.**

An unknown `TERM` defaults to 8 rather than 0 so a bare `TERM=linux` console, and a `TERM` that `sudo` replaced,
still get styling. `sudo`'s `env_reset` drops `COLORTERM`, `NO_COLOR`, `FORCE_COLOR` and `CLICOLOR*`; a missing
`COLORTERM` therefore means "unknown, use the ladder answer", never "not truecolor". (See
[INTEGRATION-PLAN.md](INTEGRATION-PLAN.md) P7 for the `--preserve-env` patch that fixes this properly.)

`tput` is an optional refinement only. It may *raise* the ladder's answer, never lower it below 8, and only when
its output matches `^[1-9][0-9]*$`. The trap it guards against: `tput colors` returns `-1` **with exit status 0**
for `dumb`/`vt100`/`vt220`/`sun`, so a `command -v`-style success check passes and hands you `-1`. It also costs
~1.0 ms against ~14 µs for a `case`, a pure-bash `case` agreed with it on 21/21 `TERM` values, and it lives in
`ncurses`/`ncurses-bin`, which is in no `essentialPackages` list.

At depth 8 the **only** colours emitted are `33`, `32` and `31`. No `9x` bright codes, no `90`, no SGR 2 —
Fedora and RHEL VT default fonts carry 512 glyphs, which steals the intensity bit, so `93` renders brown and `90`
renders black-on-black. Everything that is not accent, ok or err is simply the terminal's default foreground.
One accent plus default ink is also the most on-brand thing in this whole document.

### 3.2 Character set — `CT_CHARSET`

`ascii` or `unicode`, where "unicode" means **the verified VT-safe intersection and nothing more**: light box
drawing `─│┌┐└┘├┤┬┴┼` and `█`. Of those, v1 actually uses two.

1. `CARINO_TERM_CHARSET=ascii|unicode` → honoured verbatim.
2. `CT_MULTIBYTE == 0` → `ascii`.
3. `TERM` ∈ {`dumb`, `unknown`, `vt100`, `vt220`, `sun`, empty} → `ascii`.
4. otherwise → `unicode`.

`CT_MULTIBYTE` is decided by `v=é; (( ${#v} == 1 ))`. No fork; immune to the `utf8` / `UTF-8` spelling split
(891 locales on a Fedora box are spelled `en_US.utf8`); immune to `LC_ALL=C` beating `LANG`; and it tests
exactly the property `carino_width` depends on. Note that `he_IL` with no suffix resolves to **ISO-8859-8**, so a
supported fleet locale legitimately lands in byte mode.

**The library file itself must be saved UTF-8.** The charset probe compares `${#é}`, and a Latin-1 re-save
silently inverts the answer.

| Glyph | `unicode` | `ascii` | Note |
| --- | --- | --- | --- |
| `CT_G_RULE` | `─` U+2500 | `-` | present in all seven console fonts surveyed |
| `CT_G_VBAR` | `│` U+2502 | `\|` | reserved; no v1 primitive uses it |
| `CT_G_BLOCK` | `█` U+2588 | `#` | the only block glyph present in every font |
| `CT_G_TRACK` | `-` | `-` | **ASCII in both tiers** — `░▒▓` are unverified outside Fedora's `eurlatgr` |
| `CT_G_MARK` | `>` | `>` | **ASCII in both tiers** — `▸ ▶ →` are absent from Fedora's default console font |

**`✓ ⚠ ▸ ╭ • → ✔`, braille and emoji are not in the fleet's terminal vocabulary and never will be.** They are
missing from Fedora's `eurlatgr` and/or Debian's `Lat2-Terminus16`. A ZWJ emoji sequence measures 6 in bash, 6 in
libc and 2 in most terminals, and no console font has any emoji at all.

Status tags are ASCII in both tiers and are never glyphs: `[ ok ]` `[warn]` `[fail]` `[note]` `[ .. ]`. Six
columns, fixed, so the prose column always aligns.

### 3.3 Interactivity — the fd-9 snapshot

`setup.sh:9` redirects stdout into a `tee`. After that line, `[[ -t 1 ]]` is **false for the entire run**, which
is why the script writes raw escapes into every log today. The fix is a read-only snapshot of the real stdout,
taken before the redirect:

```bash
exec 9>&1                       # the real stdout, captured before it becomes a pipe, used for detection only
exec > >(tee -a "$LOG") 2>&1
```

The library then does **exactly these two checks and no more**:

```bash
CT_TTY_FD=${CARINO_TERM_TTY_FD:-9}
[[ -t $CT_TTY_FD ]] && CT_INTERACTIVE=1
[[ $CT_INTERACTIVE == 0 && -t 1 ]] && CT_INTERACTIVE=1
```

There is no `/dev/tty` fallback. It would over-report under `./setup.sh > file` and put escapes into a plain
redirect. If a host script forgets `exec 9>&1` it loses colour and `carino_term_selftest` says so in one line;
`CARINO_TERM_COLOR=always` overrides.

**The library never writes to fd 9.** Detection only. All output goes to stdout, escapes inline, one stream —
because a second output fd bypasses `test.sh`'s `$( … 2>&1 )` capture and every one of its 22 assertions stops
seeing the message it greps for.

**Interactive is not the same as promptable.** `[[ -t 0 ]]` survives the redirect and is the only reliable
"a human can answer" signal. It is stored separately as `CT_STDIN_TTY`, and it is what `carino_ask`,
`carino_confirm` and `carino_progress` consult. Note that `[[ -t 1 ]]` is false inside any `$( … )` regardless of
redirects, so this check must never live in a command substitution.

### 3.4 The whole resolved state

All read-only after `carino_term_init`. Prefix `CT_`.

| Variable | Values | Meaning |
| --- | --- | --- |
| `CT_DEPTH` | `0` `8` `256` `16777216` | colour depth in use |
| `CT_DEPTH_WHY` | free text | which rung of the ladder in §3.1 answered — what `carino_term_selftest` prints |
| `CT_CHARSET` | `ascii` `unicode` | glyph tier |
| `CT_COLS` | 40–100 | usable width, clamped |
| `CT_NARROW` | `0` `1` | raw width < 40; suppresses rules and padding |
| `CT_INTERACTIVE` | `0` `1` | a human is watching |
| `CT_STDIN_TTY` | `0` `1` | a human can answer |
| `CT_RTL` | `0` `1` | resolved message language is he/ar/fa/ur |
| `CT_MULTIBYTE` | `0` `1` | shell is in a multibyte locale |
| `CT_SECTION_N` | integer | section counter, starts at 0 |
| `CT_TTY_FD` | integer | which fd holds the pre-redirect stdout snapshot; default 9 |
| `CT_KV_W` | integer | widest `carino_kv` key seen so far, so the value column stops jumping |
| `CT_INIT` | `1` | guard; re-running init is a no-op unless `-f` |

They are read-only **by convention, not by the `readonly` builtin** — `carino_term_init -f` has to be able to
re-resolve them, and a `readonly` variable would abort the whole host script the first time a test harness tried.

---

## 4. Width

**`printf` field widths and `${#s}` are banned from every layout path.** `printf '%-12s'` pads by *bytes*, so
`Instalación` and `インストール` both receive zero padding; `printf '%.10s'` splits a UTF-8 sequence and renders
`インス` followed by a replacement character.

```bash
carino_width  STR          # display width as an integer
carino_pad    STR N [left|right]
carino_truncate STR N      # slices with ${s:i:n}, appends "..." when it cuts
```

`carino_width` is pure bash — one `printf -v cp "%d" "'${s:i:1}"` per character against coarse East-Asian-Wide,
combining-mark and control tables. It matched libc `wcswidth` 13/13 across es/ja/zh/ko/he/ar/ru, box drawing and
combining marks, and costs ~0.5 ms for a 12-character label. When `CT_MULTIBYTE == 0` it returns `${#s}` and that
is documented as approximate.

`carino_pad` is a no-op when `CT_NARROW=1` or `CT_RTL=1`.

Width resolution, with `[[ $n =~ ^[0-9]+$ ]] && (( n >= 20 ))` re-checked **after every step** — that gate is what
rejects `stty`'s `0 0`, a `-1` and an empty answer:

1. `CARINO_TERM_WIDTH` → 2. `stty size <&9` (second field) → 3. `$COLUMNS` → 4. `tput cols` → 5. `80`

Then clamp to 100. If the raw value is under 40, set `CT_NARROW=1` and `CT_COLS=40`. There is no SIGWINCH
handling; a setup script does not need it.

---

## 5. The primitives

Everything writes to **stdout only** and returns 0 unless stated. Everything self-initialises. Nothing forks.

### 5.1 Messages — the two-zone form

```bash
carino_msg KIND TEXT      # KIND ∈ ok | warn | fail | note | say | plain
carino_ok   TEXT
carino_warn TEXT
carino_fail TEXT
carino_note TEXT
carino_say  TEXT
```

A six-column gutter tag in the raw status token, one space, then prose in `CT_TEXT`:

```
[ ok ] Flatpak remote flathub is configured.
[warn] No native gaming package list exists for 'openSUSE'.
[fail] Gentoo is not supported: portage builds from source, so every package name here is wrong.
[note] dnf will use 8 parallel downloads for this run.
       Installing ffmpeg…
```

The last line is `carino_say`: a six-space gutter and prose in `CT_SEC`. It is narration, not a status.

```bash
carino_ok   "Flathub remote added system-wide."
carino_warn "No native gaming package list exists for '$DISTRIBUTION'."
carino_fail "The package index could not be refreshed, so nothing was installed."
carino_note "$(carino_probe_parallel_suggest) parallel downloads will be used for this run."
carino_say  "Installing the Design profile…"
```

### 5.2 Messages — the legacy four

```bash
info    TEXT       # CT_SEC     whole line, no gutter, no prefix
error   TEXT       # CT_ERR     whole line, no gutter, no prefix
caution TEXT       # CT_ACCENT  whole line, no gutter, no prefix
success TEXT       # CT_OK      whole line, no gutter, no prefix
profileWarning A B # unchanged semantics; emits caution()
```

These are the ~211 existing call sites in `setup.sh` (32 `info`, 59 `error`, 90 `caution`, 30 `success`). The
library shadows the four functions and changes **nothing but the escape sequences**. Same single line, same text,
no prefix, no wrap.

`info()` is **grey `--text-sec`, not blue and not gold.** It carries all nine localized menus; a blue or a gold
menu is wrong on both counts, and neutral prose is `--text-sec` everywhere on the web. The promoted `--info`
`#38bdf8` exists as a token and is used by the new `carino_note` primitive only.

Four compatibility rules, all load-bearing:

- **Single argument.** The body uses `"$1"`, never `"$*"`. `setup.sh:1064` is `caution $NAME` *unquoted*; with `NAME="Fedora Linux"` only `Fedora` prints today, and `"$*"` would silently change that output.
- **`%b` semantics.** `printf '%b\n' "${colour}$1${CT_RESET}"`. The 16 menu strings and `setup.sh:752` encode layout as literal `\n`. Verified: `echo -e "-n"` prints *nothing* (it parses `-n` as an option) while `printf '%b\n' "-n"` prints `-n`; `\c`, `\t` and `\n` behave identically in both. No call site begins with `-n`, `-e` or `-E`, so this is a strict improvement.
- **One `printf` per call**, so a colour run never spans a line boundary in a way the log filter can split.
- **No wrapping, no reflow, no padding, no right-alignment, no mid-line decoration, ever.** The Gentoo refusal at `setup.sh:243` is a 380-character single line and `test.sh:85` greps `not supported` inside it. A newline at column 80 splits the phrase and fails all fifteen declined-distribution assertions.

And one prohibition that applies to every primitive: **never emit text matching
`command not found|syntax error|unbound variable|bad substitution|: line [0-9]+:`.** `test.sh:147` fails any run
containing it.

`CARINO_TERM_GUTTER=1` switches the legacy four to their two-zone equivalents. **Default off.** It exists so the
branded form can be seen on demand, and so the flip can be made globally once all call sites are audited.

### 5.3 Inline emphasis

```bash
carino_em TEXT     # wraps TEXT in CT_EMPH … CT_TEXT, for interpolation
```

```bash
carino_ok "Installed $(carino_em ffmpeg) from RPM Fusion."
```

Mirrors `.alert b { color: #fde68a }`. Returns the bare text at depth 0.

### 5.4 Structure — five primitives, no widget toolkit

```bash
carino_rule [LABEL]
```

A full-width `CT_G_RULE` run in `CT_MUTED`. With a label, `── LABEL ──────────` with the label in `CT_SEC`,
uppercased. Collapses to a single blank line when `CT_NARROW=1`.

```
────────────────────────────────────────────────────────────
── NETWORK ──────────────────────────────────────────────────
```

This replaces the 37-dash literal — but **only at `setup.sh:752`, `test.sh:255` and
`tools/check-packages.sh:122`**. The other sixteen occurrences live inside translated menu strings that
`test.sh:19` scrapes out of the source, and are out of scope.

```bash
carino_section TITLE
```

Blank line, then `NN > TITLE`: `NN` zero-padded in `CT_ACCENT`, `>` in `CT_MUTED`, `TITLE` uppercased in
`CT_ACCENT` + `CT_BOLD`. Increments `CT_SECTION_N`.

```

01 > REPOSITORIES

02 > ESSENTIAL PACKAGES

03 > NETWORK
```

**Open-ended numbering, no denominator.** `03 > NETWORK`, never `03/12`. A branch-heavy installer cannot know its
step count up front and a wrong denominator is worse than none. Mirrors `.spec-num` + `.spec-head h2`. The blank
line is the terminal's z-axis: vertical isolation is how elevation transfers.

```bash
carino_kv KEY VALUE
```

The fact line. `KEY` in `CT_MUTED`, padded via `carino_pad` to the widest key seen so far; `VALUE` in `CT_TEXT`.

```bash
carino_kv "Distribution" "$DISTRIBUTION $VERSION"
carino_kv "Kernel"       "$kernelVersion"
carino_kv "Architecture" "$archType"
```
```
Distribution   Fedora Linux 42
Kernel         6.15.4-200.fc42.x86_64
Architecture   x86_64
```

**When `CT_RTL=1` or `CT_NARROW=1` it degrades to unpadded `key: value`.** The frame does not break — box
characters are bidi class ON and resolve to L at a paragraph edge — but the label and value columns **swap
places** and the padding jumps to the opposite edge on VTE ≥ 0.57 and Konsole, while xterm, alacritty, kitty,
foot and the VT show them unswapped. The library cannot detect which side of that line it is on, so it never
emits a multi-field line in RTL.

```bash
carino_menu TEXT
```

A **pass-through renderer, not a list renderer.** Splits on newlines, prints each line with `CT_SEC` applied and
reset per line, blank line first. It must not generate or renumber items — the digits live inside sixteen
translated strings and `test.sh:19` reads them straight out of the source. It must not box, pad, centre or
right-align: `${#s}` is 13 for a Japanese line that occupies 23 columns, and `he_IL` reorders. And it must not
alter the `^N. ` shape, because `test.sh:163` depends on it and would start passing vacuously if it changed.

```bash
carino_banner
```

`CARINO SYSTEMS` uppercase in `CT_ACCENT` + `CT_BOLD` on one line, a `CT_G_RULE` under it.

```
CARINO SYSTEMS
────────────────────────────────────────────────────────────
```

**No injected letter-spacing.** The `.guide-hero .kicker` 0.35em tic is the most recognisable Carino typographic
gesture and it is rejected here: it costs horizontal room on a 40-column serial console and it breaks copy-paste
and `grep` for a tool people run over SSH.

### 5.5 Prompts

```bash
carino_ask     PROMPT VARNAME [DEFAULT]   # assigns via printf -v
carino_confirm PROMPT [y|n]               # 0 = yes, 1 = no
```

```bash
carino_confirm "Rewrite GRUB_TIMEOUT to 5 and regenerate the bootloader configuration?" n && updateGrub
carino_ask "What is the server name you wish to connect to?" server
```

**Both use `read -r -p`, and colour goes only *inside* the `-p` argument.** Bash prints a `read -p` prompt only
when stdin is a terminal, and writes it to **stderr** — verified under a pty harness. That free suppression is
what keeps three previously-silent prompt strings out of every `test.sh` capture and out of the `DRY-RUN:` line
counts. A `printf`-based prompt would start emitting them. **The prompt primitives write nothing to stdout.**

When `NONINTERACTIVE=1` or `CT_STDIN_TTY=0`, both take the stated default and announce it in the exact existing
phrasing — `Non-interactive run: <thing>=<value> (default: <value>)` via `caution` — because `test.sh:202`
asserts on that string verbatim and the file's whole contract is "every skipped prompt names the default it took".

`carino_confirm` renders its suffix as `[y/N]` or `[Y/n]`, matching the existing GRUB prompt style.

### 5.6 Motion

```bash
carino_step_begin TEXT                    # "  TEXT …" with no trailing newline, CT_SEC
carino_step_end   ok|fail|skip [TEXT]
carino_progress   DONE TOTAL [LABEL]
```

```bash
carino_step_begin "Refreshing the package index"
sudo $pkgm $updatePreFlags $argUpdate $updateFlags && carino_step_end ok || carino_step_end fail
```
```
  Refreshing the package index … [ ok ]
```
```bash
carino_progress 4 12 "packages"
```
```
[████------] 4/12 packages
```

Rules, absolute:

- **The vocabulary is bare `\r` plus spaces for erasure.** No `\e[2K`, no cursor addressing, no scroll regions, no `\e[?25l`. CR-and-overwrite renders identically on the VT and under `TERM=dumb`, needs no CSI at all, and collapses to one clean line in the log under the filter in [INTEGRATION-PLAN.md](INTEGRATION-PLAN.md) P2.
- **The whole animated path is gated on `CT_INTERACTIVE == 1`.** When it is 0, `carino_step_begin` prints a complete line, `carino_step_end` prints its result on a new line, and `carino_progress` prints only at 0% and 100%.
- **The full track is drawn first in `CT_MUTED` with a gold head travelling over it** — `[████------]` — never a bar growing from nothing. This is `carino-anim.css:45-53` stated as a house rule: the whole shape is always present, so the bright part reads as a pass across something that exists.
- **No spinner in v1.** A step line plus a progress bar covers every case in `setup.sh`, and a spinner is the primitive most likely to be left mid-frame by an interrupt.

### 5.7 Selection

```bash
carino_selected TEXT
```

`CT_REV` over `CT_ACCENT` with a leading `CT_G_MARK`. The exact analogue of the web's
`background: var(--accent); color: #050505` inversion used by `.btn-primary`, `.toggle-btn.active` and
`.chip-tz`. Hover has no terminal analogue and is not modelled.

### 5.8 Lifecycle and diagnosis

```bash
carino_term_init [-f]     # resolve all CT_* state; idempotent; -f forces re-resolution
carino_term_selftest      # the resolved tier table plus a swatch of every token and glyph
carino_term_cjk_ok        # 0 if CJK is likely to render, 1 when TERM=linux
carinoTermDemo            # renders every primitive in order, so a human can eyeball the whole system
```

`carino_term_selftest` is the documented way a fleet author finds out why they have no colour. It prints depth,
charset, cols, interactive, stdin-tty, rtl, multibyte, tty-fd, **and the reason the depth ladder stopped where it
did**. When someone reports "the branding does not work on my box", ask for this output first.

---

## 6. Environment knobs

Read once at init, never re-read.

| Variable | Effect |
| --- | --- |
| `CARINO_TERM_COLOR` | `never` `0` `auto` `always` `8` `256` `24bit` `truecolor`. Also the light-terminal escape hatch: `never`. |
| `CARINO_TERM_CHARSET` | `ascii` or `unicode`, honoured verbatim. |
| `CARINO_TERM_WIDTH` | Integer ≥ 20, overrides `stty`/`COLUMNS`/`tput`. |
| `CARINO_TERM_TTY_FD` | Which fd holds the pre-redirect stdout snapshot. Default `9`. |
| `CARINO_TERM_GUTTER` | `1` renders the legacy four in the two-zone form. Default off. |
| `CARINO_TERM_RTL` | Force `CT_RTL`. |

The standards are honoured too: `NO_COLOR` (non-empty), `FORCE_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE`, `COLORTERM`,
`TERM`.

---

## 7. What `carino-term.sh` never does

This list is the contract. If a change would violate one of these, the change is wrong.

- Never writes to fd 9, `/dev/tty`, or any fd but 1. Never calls `exec` on fd 1 or 2. Never re-establishes the tee.
- **Never creates, writes, moves or deletes a file.** Never calls `mkdir`, `tee`, `cp`, `mv`, `ln`, `rm`, `chmod` or `sed` — all of those are PATH-shimmed by `enableDryRun`, and a bare `>` redirect would defeat the shim and really write during a rehearsal.
- Never emits cursor-positioning, scroll-region, alternate-screen or cursor-hide sequences.
- Never wraps, reflows, pads, centres or right-aligns message prose.
- Never frames or columnises when `CT_RTL=1`.
- Never renumbers, reorders or reformats menu content.
- Never emits `✓ ⚠ ▸ ╭ • →`, braille, or emoji.
- Never uses `\e[9x`, `\e[90m`, or SGR 2.
- Never calls `tput` outside `carino_term_init`.
- **Never reprograms the VT palette.** `\e]P3eab308` would put real Carino gold on a bare-metal console instead of `#AA5500` brown — the single biggest gap between the terminal and web identities — but it mutates global state across every VT and survives a hard kill until reboot. Not shipped in v1; revisit only on an explicit branding call.
- **Never switches the user's message language.** On the VT, no console font tested contains a single CJK or Hebrew glyph, so a `ja_JP` user sees blanks — but silently substituting English is worse than an unreadable menu the user can fix. The library exposes the fact (`CT_CHARSET=ascii` on a byte-mode locale, `carino_term_cjk_ok` returning 1 when `TERM=linux`) and lets the host script decide.

---

## 8. Adopting it in another Carino script

1. Copy `carino-term.sh` (and `carino-probe.sh` if you want facts) into the repository root. Commit them.
2. Take the fd-9 snapshot **before** any redirect of stdout:
   ```bash
   exec 9>&1                  # detection only, the library never writes here; without it every [[ -t 1 ]] below is false forever
   ```
3. Paste the `carinoLoad` block from §1, plus the shim functions from [INTEGRATION-PLAN.md](INTEGRATION-PLAN.md) §4.
4. Delete your local `RED=`/`BLUE=`/`GREEN=`/`YELLOW=` palette and your local `info`/`error`/`caution`/`success` bodies. The library provides all four with identical semantics. **`macos.sh:5,7-10` and `tools/check-packages.sh:7,9-12` are each a duplicate of that palette and are the two scripts to convert first**, as the working demonstration.
5. Write new output with the two-zone primitives — `carino_ok`, `carino_warn`, `carino_fail`, `carino_note`, `carino_say`, `carino_section`, `carino_kv`, `carino_rule`. Leave existing call sites alone until you can audit them.
6. Run `carino_term_selftest` once by hand, and once through a pipe, and confirm the second run is escape-free.

If your script strips ANSI from its own captured output — as `test.sh` does with
`sed 's/\x1b\[[0-9;]*m//g'` — that filter keeps working unchanged. Every sequence the library emits is
`\e[` followed by digits and semicolons followed by `m`, including the 24-bit `\e[38;2;234;179;8m` form.

---

# `carino-probe.sh`

## 9. What it is

A general **fact provider**. It answers questions; it never acts on the answers. Sourced, self-contained,
**zero side effects at source time** — no directory creation, no file write, no network, no forks. It defines
functions and nothing else.

The probe **reports**; the caller **decides**. Even the decision helpers only return a recommendation and a
reason.

## 10. API

```bash
carino_probe       KEY [ARG]     # print the value; exit 0 if known, 1 if unknown (prints "unknown")
carino_probe_load  KEY [ARG]     # resolve in the CALLER'S shell, print nothing; exit 0 if known
carino_probe_has   KEY [ARG]     # exit 0 if the fact is known and truthy
carino_probe_int   KEY [ARG]     # print a bare integer, or 0; exit 1 if unknown
carino_probe_all   [PREFIX]      # every already-resolved fact as key=value, one per line, sorted
carino_probe_report              # human-readable, via carino_kv when available and printf otherwise
carinoProbeReport                # the camelCase alias of the line above, for setup.sh's convention
carino_probe_reset [KEY [ARG]]   # drop memoised values (testing only)
```

```bash
if carino_probe_has os.atomic; then
    carino_note "Atomic system: only the essential packages can be layered."
fi
cores=$(carino_probe_int cpu.cores)
free=$(carino_probe_int disk.free.mb /var)
carino_probe_all os.            # os.atomic=0 os.family=fedora os.id=fedora os.version=42
```

### `carino_probe_load` — the one thing that is easy to get wrong

**Memoisation lives in shell variables, and `$( … )` forks a subshell.** A value resolved inside a command
substitution is memoised in the subshell and thrown away when it exits. For Tier A and B facts that costs a
handful of microseconds. For a Tier C bandwidth measurement it costs **another 8 MiB and another two seconds**.

So any caller that reads more than one `net.*` value must warm the parent's memo first:

```bash
carino_probe_load net.speed.bps                    # one measurement, memoised HERE, prints nothing
echo "$(carino_probe net.speed.bps) at $(carino_probe net.rtt.ms) ms"   # both now free
```

This applies to the decision helpers too — `carino_probe_parallel_suggest` and `carino_probe_parallel_flags`
each resolve `net.speed.bps` internally, so calling both inside `$( … )` without a preceding
`carino_probe_load net.speed.bps` measures **twice**. See [INTEGRATION-PLAN.md](INTEGRATION-PLAN.md) §8.3, where
this is the first line of the resolver.

`carino_probe_has` deliberately does not use `$( … )` internally for the same reason: a boolean test also warms
the parent's memo instead of discarding it.

`carino_probe_all` is the machine-readable surface and is what makes a log header cheap: it prints only facts
already resolved plus the eager tier, and **never triggers an expensive probe.**

Keys are dotted and lowercase. Values are bare tokens or integers — no units, no thousands separators, no colour.
**`unknown` is a first-class value and every caller must handle it.**

## 11. The fact catalogue

### Tier A — cheap and eager (resolved on the first `carino_probe` call; no forks beyond `uname`)

| Key | Values | Source |
| --- | --- | --- |
| `os.id` | os-release `ID` | `$OSRELEASE`, honouring `CARINO_SETUP_OSRELEASE` |
| `os.family` | `debian` `fedora` `rhel` `centos` `amazon` `arch` `opensuse` `unknown` | `ID` + `ID_LIKE` |
| `os.version` | `VERSION_ID` or `unknown` | os-release |
| `os.atomic` | `1` `0` | `rpm-ostree` present **and** `/run/ostree-booted` exists |
| `pkg.manager` | `dnf5` `dnf` `apt` `pacman` `zypper` `rpm-ostree` `unknown` | `command -v`; `dnf5` preferred |
| `cpu.arch` | `uname -m` | |
| `cpu.cores` | integer | `getconf _NPROCESSORS_ONLN` → `^processor` count in `/proc/cpuinfo` → `1` |
| `cpu.model` | free text, no commas | first `model name` in `/proc/cpuinfo` |
| `mem.total.mb` | integer | `/proc/meminfo` `MemTotal` / 1024 |
| `mem.avail.mb` | integer | `/proc/meminfo` `MemAvailable` |
| `swap.total.mb` | integer | `/proc/meminfo` `SwapTotal` |
| `init.systemd` | `1` `0` | `/run/systemd/system` is a directory |
| `boot.uefi` | `1` `0` | `/sys/firmware/efi` is a directory |
| `container` | `docker` `podman` `lxc` `none` `unknown` | `/.dockerenv`, `/run/.containerenv`, `/proc/1/cgroup` |
| `priv.uid` | integer | `${EUID:-$(id -u)}` |
| `priv.tool` | `root` `sudo` `doas` `run0` `none` | mirrors `setupPrivilege` |
| `tty.interactive` | `1` `0` | `[[ -t 0 ]]` |

### Tier B — cheap and lazy (one fork on first query, then memoised)

| Key | Values | Source |
| --- | --- | --- |
| `virt` | `kvm` `vmware` `virtualbox` `hyperv` `xen` `none` `unknown` | `systemd-detect-virt` → DMI `product_name` → `hypervisor` flag |
| `gpu.vendor` | subset of `intel amd nvidia`, space-separated, or `none` | `lspci` → `/sys/class/drm/card*/device/vendor` (`0x8086` `0x1002` `0x10de`) |
| `gpu.count` | integer | same |
| `power.source` | `ac` `battery` `unknown` | `/sys/class/power_supply/*/type` + `online`/`status` |
| `power.battery` | `1` `0` | any `power_supply` of type `Battery` |
| `disk.free.mb PATH` | integer | `df -P -k PATH` field 4 / 1024; `PATH` defaults to `/` |
| `disk.rotational PATH` | `1` `0` `unknown` | device → `/sys/block/<dev>/queue/rotational` |
| `net.metered` | `yes` `no` `unknown` | `nmcli -t -f GENERAL.METERED device show`, trailing `(guessed)` stripped |
| `net.connectivity` | `full` `portal` `limited` `none` `unknown` | `nmcli networking connectivity` |

The two path-taking keys are addressed and memoised per argument:

```bash
carino_probe disk.free.mb /var
carino_probe disk.rotational /
```

### Tier C — expensive, explicit opt-in only

| Key | Values |
| --- | --- |
| `net.speed.bps` | integer bytes/sec, or `unknown` |
| `net.speed.reason` | `skipped` `metered` `no-route` `no-target` `no-mirror` `bad-response` `too-slow` |
| `net.rtt.ms` | integer, or `unknown` — a free byproduct of the same curl, no ping and no root |
| `net.mirror.url` | the discovered measurement target, or `unknown` |

Tier C **never runs** unless asked for by key, and never at all when `NONINTERACTIVE=1`, `DRYRUN=1` or
`CARINO_PROBE_NET=0`. `CARINO_PROBE_NET=1` re-enables it under `NONINTERACTIVE` for someone who genuinely wants
it. Asking for `net.speed.bps` — directly, or through either parallel-download helper — **is** the explicit
opt-in the contract requires.

### Probe environment knobs

| Variable | Effect |
| --- | --- |
| `CARINO_PROBE_NET` | `0` forbids the bandwidth probe outright; `1` permits it even under `NONINTERACTIVE`/`DRYRUN`. Default: permitted only in a normal interactive run. |
| `CARINO_PROBE_NET_MAXSEC` | Hard wall-clock ceiling for the whole Tier-C operation. Default `25`. |
| `CARINO_PROBE_MIRROR_URL` | Skip mirror discovery and measure this exact URL. For an air-gapped internal mirror, and the only way to exercise the measurement path in a test. **It is an override, not a fallback** — nothing selects it automatically. |
| `CARINO_SETUP_OSRELEASE` | Honoured for the `os.*` keys, so a test harness can drive other families. |
| `CARINO_PROBE_LIB` | Set to `1` by the library. A marker for the caller, not a guard — re-sourcing is harmless. |

`carino_probe_reset` with no argument clears every memoised `CARINO_PROBE_*` fact but deliberately skips
`CARINO_PROBE_LIB`, `CARINO_PROBE_NET`, `CARINO_PROBE_NET_MAXSEC` and `CARINO_PROBE_MIRROR_URL`: those four share
the namespace but are configuration, not facts.

## 12. Caching and dry-run safety

- **Memoised in shell variables only** — one `CARINO_PROBE_<KEY_UPPER_UNDERSCORED>` per fact plus a parallel `_SET` marker, so a legitimately-empty value is not re-probed. They are never `export`ed: a child `setup.sh` re-run should re-probe a machine whose state may have changed.
- **No disk cache. Not gated, not optional — none.** Under the dry-run shim `mkdir` and `tee` silently no-op so a cache *read* returns empty, while `>` redirection is a shell builtin the shim cannot intercept and really *writes* the file, violating the README's "a rehearsal creates, modifies and deletes nothing" at line 215. The mechanism is wrong in both directions, and re-probing costs a few milliseconds per process.
- **Never calls `sed`.** It is shimmed: `echo "speed=5440315" | sed 's/speed=//'` prints `DRY-RUN: sed s/speed=//` during a rehearsal. Parsing uses bash parameter expansion, `grep`, `cut`, `awk` and `tr` — all left real.
- **Every glob over `/sys` or `/proc` saves and restores noglob:**
  ```bash
  case $- in *f*) _nf=1;; *) _nf=0;; esac; set +f
  for d in /sys/class/drm/card*/device; do … done
  (( _nf )) && set -f    # saved and restored rather than a bare set -f at the end, because a fleet script that copies this file may not have noglob on in the first place
  ```
  `set -f` at `setup.sh:10` is global and is lifted in exactly one place (`setup.sh:733`). Under it, `for i in /sys/class/net/*` iterates the literal pattern and reads nothing.
- **Every subprocess is silenced with `2>/dev/null`.** `test.sh:147` fails any run whose output matches `command not found`, and a bare call to a missing `nvidia-smi`, `lscpu` or `nmcli` emits exactly that.
- **Nothing is assumed present** beyond a minimal system: not `bc`, `python`, `jq`, `lscpu`, `glxinfo`, `speedtest-cli`, `nvidia-smi`, nor GNU-only flags. `df -P` is POSIX; `grep -m1` and `cut -d' ' -f2` are safe.

## 13. Bandwidth

### 13.1 Pre-flight, in order

1. `NONINTERACTIVE=1` or `DRYRUN=1` and `CARINO_PROBE_NET != 1` → `unknown`, reason `skipped`. `test.sh` runs 8 plans under `timeout 120` and 14 arguments under `timeout 90`, and treats exit 124 as an outright failure; a multi-second probe multiplied across those rows blows the budget.
2. `net.metered == yes` → `unknown`, reason `metered`. Spending 8 MiB of a phone tether to tune download parallelism is indefensible.
3. `net.connectivity` ∈ {`portal`, `none`} → `unknown`, reason `no-route`.
4. `pkg.manager` ∈ {`apt`, `pacman`, `rpm-ostree`} → `unknown`, reason `no-target`. There is no knob to feed and no guaranteed large file to measure — pacman's only certain file, `core.db`, is 130,150 bytes, an order of magnitude below the slow-start floor.

A missing `nmcli` yields `unknown`, which is not clearance for steps 2–3 by itself but does not block either: the
probe proceeds and relies on the response validation below. Proxies need no code — curl honours
`http_proxy`/`https_proxy`, and measuring through the proxy is correct because dnf will use it too.

### 13.2 Target

**The machine's own configured mirror, always.** On the test machine a generic CDN reported 750,477 B/s while the
real dnf mirror delivered 5,440,315 B/s — a 7x error that inverts the bucket decision. This also rules out a
Carino-hosted test file: `setup.carino.systems` is a CDN like any other and would measure a path dnf never uses.

For the dnf family the metalink is selected **by name, never by directory order** — `/etc/yum.repos.d` reads
alphabetically and `fedora-cisco-openh264.repo` sorts first, whose repository holds four packages and whose index
is a few kilobytes:

```bash
grep -h '^metalink=' /etc/yum.repos.d/*.repo | grep 'repo=fedora-\$releasever'
```

`$releasever` is expanded by hand from `rpm -E %fedora` (else os-release `VERSION_ID`) and `$basearch` from
`uname -m`, because curl has never heard of dnf variables. Then: fetch the metalink (≤3 s), take the first
`https` `<url>`, fetch its sibling `repomd.xml` (≤3 s), `grep` the `href` ending `primary.xml.zst` or `.gz`, and
build the absolute URL. For zypper, append `.metalink` to `<repo-base>/repodata/repomd.xml` — MirrorBrain serves a
preference-sorted list — with base URIs from `zypper lr -u`.

Do not assume the first metalink entry is the fastest: MirrorManager sorts by netblock preference, and on the test
machine the pref-100 mirror was 7x slower than pref-99. `fastestmirror` does not help either — `dnf5.conf(5)`
says it uses TCP latency and "does not take into consideration mirror bandwidth", which vindicates the existing
comment at `setup.sh:1081`. **The probe therefore reports "this mirror's speed right now", never "your connection
speed", and `carino_probe_report` phrases it that way.**

Discovery is capped at **6 s total**, and its failure is `unknown` / `no-mirror`. Falling back to a generic target
is explicitly rejected — it reintroduces the 7x error.

### 13.3 The sample

```bash
curl -sL -o /dev/null --max-time 5 -r 0-8388607 \
     -w '%{http_code} %{size_download} %{speed_download} %{time_namelookup} %{time_connect}' \
     "$url" 2>/dev/null
```

- **`-L` is mandatory.** Without it the same osuosl URL measured 846 B/s instead of 2,059,712 B/s — a 2400x error. `ftp-chi.osuosl.org` 301s, and openSUSE's `download.opensuse.org` is a redirector by design.
- **`-r 0-8388607` bounds the bytes; `--max-time` bounds the time.** Never `--max-filesize`: it reads Content-Length and refuses to start (exit 63, `speed=0`), which normalises into a plausible-looking "very slow link".
- **8 MiB is the floor.** TCP slow start under-reports smaller samples by up to 3.5x (1 MiB reads 1.5 MB/s on a 5.5 MB/s link). The bias is always downward, which is the safe direction, but it is large enough to change the bucket.
- **Accept `rc == 0 || rc == 28`.** `--max-time` aborts with 28 and still prints a complete, correct `%{speed_download}` — that is the success path on exactly the slow links the probe exists to detect. Every other non-zero exit is a failure.
- **Validate all three of** exit ∈ {0,28}, `http_code` ∈ {200,206}, `size_download >= 1048576`. Exit code alone is never sufficient: 301-without-`-L` (1094 B/s), a 404 (564 B/s) and a Cloudflare 403 (6 B/s) all return exit 0 with a confident wrong number.
- **Normalise before arithmetic.** curl 8.18 prints a whole number and is locale-independent, but older builds emit decimals and some use `%g`. Strip a trailing `.…`, convert a `,` decimal separator, and expand `5.4403e+06` → `5440300`. A bare `$((10#$raw))` on scientific notation is a **fatal** arithmetic error that aborts the probe mid-run. All formatting is integer-only: one decimal place is `printf '%d.%d' $((v/D)) $(((v%D)*10/D))`.

One sample by default. It escalates to **median of three** — three 4 MiB ranges at different offsets, one
connection each — only when the first result lands within 20% of a bucket boundary. Single samples spread 3.9x on
repeated back-to-back runs; median-of-3 narrows that to 1.29x, at 12 MiB instead of 8.

Hard ceiling on the whole Tier-C operation: **25 seconds and 20 MiB**, enforced by a wall-clock check between
samples. Typical measured cost including discovery: **1,812 ms and ~8 MiB** — under 1% of the multi-hundred-MB
install it precedes.

### 13.4 The "cannot measure" contract

`carino_probe net.speed.bps` prints `unknown` and exits 1; `carino_probe net.speed.reason` says why.
**Every decision helper treats `unknown` as "change nothing".** There is no fallback target and no guessing.

## 14. Decision helpers

```bash
carino_probe_parallel_suggest     # prints "N reason"; N is the value to use, 0 means change nothing
carino_probe_parallel_flags       # prints the exact CLI flags for pkg.manager, or nothing
carino_probe_can_gpu_accel        # prints "amd|intel|nvidia|none reason"
carino_probe_enough_disk PATH MB  # exit 0/1; prints "have=N need=M"
```

Three buckets, deliberately wide, because the measurement noise does not support finer granularity — four of five
noisy samples agreed at these boundaries, and at 1 and 2 MB/s they would not:

| Measured | Suggestion | Reason |
| --- | --- | --- |
| `unknown` | `0` | `unmeasured` |
| < 1,000,000 B/s | `0` | `slow-link` |
| 1–5 MB/s | `6` | `medium` |
| ≥ 5 MB/s | `8` | `fast` |

**Never raise parallelism below ~1 MB/s.** `dnf5.conf(5)` sets `minrate` to 1000 B/s and `timeout` to 30 s, so N
connections on a link slower than N kB/s makes dnf abort connections. That is the documented mechanism by which
"helpfully" raising the value makes a slow link *worse*, not merely no better.

**Ceiling 8, hard clamp 20.** Measured aggregate throughput rose 2.6x from 1→4 connections and only 1.1x more
from 4→8; 20 buys nothing and multiplies load on volunteer mirrors. The clamp is unconditional: both dnf4 4.14.0
and dnf5 5.2.18 accept 21 with exit 0 and then fail **every** subsequent operation with
`Librepo error: Bad value of LRO_MAXPARALLELDOWNLOADS` until someone hand-edits the file.

What `carino_probe_parallel_flags` emits, by family:

| `pkg.manager` | Emits | Why |
| --- | --- | --- |
| `dnf5`, `dnf` | `--setopt=max_parallel_downloads=N --setopt=max_downloads_per_mirror=N` | **Both, always together.** At its default of 3, `max_downloads_per_mirror` silently caps single-baseurl repos — RPM Fusion, Google Chrome, every copr `setup.sh` enables — so raising only the famous knob and announcing "parallel downloads enabled" overstates what happened on exactly the repos this script adds. |
| `apt` | *(nothing)* | `apt-config dump \| grep -ci parallel` returns 0 on apt 3.0.3. Queue-Mode is a partitioning strategy, not a count; Pipeline-Depth is a different mechanism, widely disabled server-side, and undocumented in trixie's `apt.conf(5)`. |
| `pacman` | *(nothing)* | Upstream `pacman.conf` ships `ParallelDownloads = 5` uncommented, verified against the pristine 7.1.0 package. Nothing to turn on. |
| `zypper` | *(nothing)* | `download.max_concurrent_connections` defaults to 5 and means "per transfer" — chunked fetching of one file, not N packages at once. Tumbleweed ships no `/etc/zypp/zypp.conf` at all while Leap 16.0 does, so it would need two code paths for the weakest benefit of any family. |
| `rpm-ostree` | *(nothing)* | No `--setopt` flag exists, so the per-invocation approach is unavailable. Whether it honours `/etc/dnf/dnf.conf` is unverified. Do nothing — and do **not** tell an atomic user "this does nothing on your system", because that claim is unsupported. |

**Config files are never written.** The flags are passed per invocation. No persistent change means no way to
leave a user with a bricked dnf, no duplicate appended lines, and no dry-run write problem.

## 15. What `carino-probe.sh` never does

- Never writes to any system config file, to `/etc`, to `/var`, to a dotfile, or to a cache directory. Never `mkdir`. Never `>`-redirects to a path.
- Never executes a package manager, a service manager, `modprobe`, or anything privileged. It contains no `sudo` calls at all.
- Never runs anything at source time.
- Never prompts.
- Never calls `sed`.
- Never measures bandwidth without an explicit key request, and never under `NONINTERACTIVE` or `DRYRUN` unless `CARINO_PROBE_NET=1`.
- Never falls back to a generic CDN target.
- Never emits anything that could match `test.sh:147`.
- Never requires `carino-term.sh`.

---

## 16. The companion Branding change

The terminal library quotes tokens rather than magic numbers, so `--info` has to exist as a token. Four one-line
edits in `~/Github/Branding`:

1. `carino-branding.css` `:root` (lines 14–35): add `--info: #38bdf8;` beside `--ok` / `--warn` / `--err`.
2. `carino-branding.css:399`: rewrite `.toast.info` to use `var(--info)` for its border and background tint, keeping `#bae6fd` as the prose tone.
3. `index.html:689` `TOKENS` array: add `["--info", "#38bdf8"]`, taking it from 14 colours to 15.
4. `index.html:795` `TOKENS_CSS` copy-block: the same addition.

This is a real inconsistency rather than a preference. `.toast` is the only component in the file with four states
while `.alert` and `.pill` have three, and that fourth colour currently appears in exactly one line of CSS and in
neither of the two places the site publishes its own palette.

---

## Appendix — questions that are closed

| Question | Answer | Why |
| --- | --- | --- |
| Blue, gold or grey for `info()`? | **Grey `--text-sec`.** | It carries all nine localized menus. Neutral prose is `--text-sec` everywhere on the web. Zero call-site churn. |
| Box-drawing characters at all? | Yes, but only `─│┌┐└┘├┤┬┴┼` and `█`, and only `─`/`█` are used in v1. | Verified present in all seven console fonts surveyed. Everything else is not. |
| Numbered sections against a known total? | Open-ended `NN >`. | A branch-heavy installer cannot know its count; a wrong denominator is worse than none. |
| Letter-spaced `C A R I N O` banner? | No. | Costs width on a 40-column console and breaks copy-paste and `grep`. |
| Assume a dark background? | Yes, documented, with `CARINO_TERM_COLOR=never` as the escape hatch. | OSC 11 needs a raw tty read with a timeout and is widely ignored; fd 0 may be a pipe. |
| VT palette override `\e]P3`? | Not shipped. | Mutates global state across all VTs and survives a hard kill. |
| CJK on the VT? | Expose the fact, change nothing automatically. | Silently substituting English is worse than a menu the user can fix. |
| Require the fd-9 snapshot? | Yes, and lose colour without it, with `carino_term_selftest` as the explanation. | The alternative over-reports and puts escapes into plain redirects. |
| Bandwidth in the menu header? | No. | It is Tier C, it costs 8 MiB, and on apt/pacman there is no decision it feeds. Available on request via `carino_probe_report`. |
| Write `max_parallel_downloads` to `dnf.conf`? | Never. Pass `--setopt=` per invocation. | No persistent change, no README disclosure bullet, no bricked dnf, no duplicate appended lines. |
