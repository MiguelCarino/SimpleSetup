# Integration plan — `carino-term.sh` and `carino-probe.sh` into `setup.sh`

**Status:** APPLIED. P1 through P6, P8 and P9 are in the tree, along with the companion Branding token patch of
§11. **P7 remains deferred** for the reasons in §7. `test.sh` was not edited, so the one-line change in §9.1 is
still outstanding and the two libraries are not yet parsed by section 1 of the suite.

Three notes for anyone reading this after the fact:

- §1.2 was resolved with **option (b)**, the assembled key. Writing `net.speed.bps` whole into `setup.sh` was
  tried first and `test.sh --network` failed exactly as predicted, `flathub net.speed.bps returned 404`.
- `tools/check-packages.sh` shims only `carino_rule` rather than carrying the full API freeze of §4.2, because
  it calls exactly one primitive.
- The line numbers below are the **pre-patch** ones and no longer resolve; P3 alone adds ~73 lines near the top
  of the file. They are left as written so the diff can be read against the file this plan was authored against
  (`setup.sh` 1603 lines, `test.sh` 257 lines, `README.md` 297 lines).

Read [CARINO-TERM.md](CARINO-TERM.md) first for what the two libraries are. This document is only about wiring
them in.

---

## 0. What this patch is for

The four colours in use today render, on a black terminal, at these WCAG contrast ratios:

| Today | Sequence | Renders as | Contrast on `#000` |
| --- | --- | --- | --- |
| `error()` | `\e[31m` | `#800000` | **1.92** |
| `info()` | `\e[94m` | `#0000ff` | **2.44** |
| `success()` | `\e[32m` | `#008000` | **4.09** |
| `caution()` | `\e[33m` | `#808000` | **5.01** |

Only `caution` clears AA (4.5). The **error** line — the one message that must be read — sits below even the 3.0
non-text floor. The brand tokens score 5.58, 9.80, 9.22 and 10.95.

This is a legibility fix that happens to be on-brand. Lead the review with that, not with the aesthetics.

The second thing it fixes: `setup.sh:9` redirects stdout into a `tee`, so `[[ -t 1 ]]` is false for the whole run
and **raw ANSI escapes are written into every log file today.** `test.sh` compensates with
`sed 's/\x1b\[[0-9;]*m//g'` in seven places. P1 and P2 below fix that at the source.

### Scope discipline

This patch is **Stage 1 only**: colour and loading. It changes the escape sequences and nothing else. Output shape
is byte-identical — same single line, same text, no prefix, no wrapping — at all ~211 existing call sites
(32 `info`, 59 `error`, 90 `caution`, 30 `success`).

Deliberately **not** in this patch:

- Reclassifying `caution()`'s three jobs (real warnings / questions / narration) across its 90 calls.
- Flipping `CARINO_TERM_GUTTER` to 1.
- The `[1-15]` vs 16-arm prompt mismatch at `setup.sh:934` — pre-existing and unrelated; bundling it into a branding diff muddies the revert.
- `setup.ps1` (a fifth palette copy, and the eventual `carino-term.ps1`).

---

## 1. Two corrections to the design spec

Both were found by reading `test.sh`'s actual invocation and scraping rules. Both are load-bearing.

### 1.1 `${BASH_SOURCE[0]%/*}` does not give you a directory

The spec's bootstrap uses `local dir="${BASH_SOURCE[0]%/*}"`. When the script is invoked with **no slash in the
path** — which is exactly how `test.sh:36-38` invokes it, `timeout 90 bash setup.sh dry-run` — the `%/*` suffix
removal finds no `/` and returns the string unchanged:

```
$ cd /tmp && bash bs_test.sh
BASH_SOURCE0=[bs_test.sh]
dirname-by-expansion=[bs_test.sh]        # not "." — the whole filename
```

The local rung would then stat `setup.sh/carino-term.sh`, miss, and **fall through to the HTTPS rung on every one
of the ~30 dry runs `test.sh` performs.** That is a network dependency in an offline test suite, ~30 extra curl
calls against `setup.carino.systems`, and up to 10 s × 2 libs × 30 runs of added latency against `timeout 90`
and `timeout 120` budgets.

Fix, carried in the block in §3:

```bash
local dir="${BASH_SOURCE[0]%/*}"; [[ "$dir" == "${BASH_SOURCE[0]}" ]] && dir="." # %/* is suffix removal, not dirname: with no slash in the path it returns the filename unchanged, and "bash setup.sh" from the repo root is exactly how test.sh invokes this file
```

### 1.2 Dotted probe keys are scraped as Flathub application IDs

`test.sh:247` builds its Flathub check by scraping `setup.sh`:

```bash
for id in $(sed 's/#.*$//' setup.sh | grep -oE '\b[a-z][a-z0-9_]*(\.[A-Za-z][A-Za-z0-9_-]*){2,}\b' | grep -vE '\.(sh|ps1|com|org|net|io|us|systems|conf|repo|list|asc|json|target|service|rpm|deb|gz|bz2|zst|d)$' | grep -vE '^org\.gnome\.desktop' | sort -u); do
```

Reproduced against candidate probe keys:

```
$ printf 'x=$(carino_probe net.speed.bps)\ny=$(carino_probe disk.free.mb /var)\n' | sed 's/#.*$//' | grep -oE '...' | grep -vE '...'
disk.free.mb
net.speed.bps
```

`test.sh --network` would then request `https://flathub.org/api/v2/appstream/net.speed.bps`, get a non-200, and
report `bad "flathub net.speed.bps returned 404"`.

**Rule for `setup.sh`: never write a probe key with two or more dots outside a comment.** Comments are stripped
by the scraper first, so a trailing note is safe. Keys with one dot (`os.atomic`, `net.metered`, `pkg.manager`)
are safe. `carino-probe.sh` itself is not scraped, so keys inside the library are unaffected.

**This bites the P9 patch.** `carino_probe_parallel_flags` and `carino_probe_parallel_suggest` contain no dots,
but §8.3's resolver also needs the warming call `carino_probe_load net.speed.bps`, and `net.speed.bps` has two
dots. Two ways to satisfy both constraints; pick one and say which in the commit message:

- **(a)** Accept it and have Miguel add `bps` to the exclusion list at `test.sh:247` — but `test.sh` is off-limits, so this is a request, not a patch.
- **(b) Recommended:** keep the literal key out of `setup.sh` by assembling it, so the scraper's `\b[a-z][a-z0-9_]*(\.…){2,}\b` pattern never sees a two-dot token:
  ```bash
  carino_probe_load net.speed.bps # KEEP THIS ASSEMBLED, see below
  ```
  becomes
  ```bash
  carino_probe_load "net.speed${netSpeedKeySuffix}" # assembled rather than written whole because test.sh:247 scrapes setup.sh for anything shaped like a.b.c and looks it up as a Flathub application id, and "net.speed.bps" returns 404 from flathub.org
  ```
  with `netSpeedKeySuffix=".bps"` defined beside `parallelFlags`. Ugly, and the comment has to say why, or the
  next maintainer will "simplify" it straight back into a `test.sh --network` failure.

Verified by reproducing the scraper:

```
$ printf 'x=$(carino_probe net.speed.bps)\ny=$(carino_probe disk.free.mb /var)\n' | sed 's/#.*$//' | grep -oE '\b[a-z][a-z0-9_]*(\.[A-Za-z][A-Za-z0-9_-]*){2,}\b' | grep -vE '\.(sh|ps1|com|org|net|io|us|systems|conf|repo|list|asc|json|target|service|rpm|deb|gz|bz2|zst|d)$'
disk.free.mb
net.speed.bps
```

### 1.3 Reconciliation with the shipped libraries

Both libraries are now on disk (`carino-term.sh`, 38 KB; `carino-probe.sh`, 46 KB) and were re-read against this
plan. Three deltas from the spec, all of them already folded into the text above:

1. **`carino_probe_load` exists and is public.** It is not in the spec's §2.2 API list. It is the warming call that prevents the double measurement described in §8.3, it is now in the shim in §4.2, and it is documented in [CARINO-TERM.md](CARINO-TERM.md) §10.
2. **`carinoTermDemo` exists and is public** (`carino-term.sh:680`). Added to the shim.
3. **`carino-term.sh:488` defines `profileWarning` as well as the other four (`:482-485`).** So the library shadows all five, not four. This does not change the §4 placement decision — lines 16–20 stay as the fallback — but it means a reviewer diffing `profileWarning`'s body should expect it to be identical apart from being reached through the library's `caution`.

Two cosmetic notes, neither blocking: `carino-term.sh:26` cites `carino-branding.css:459` for the black terminal
background, which is **line 461** in the current Branding checkout; and the library's `info`/`error`/`caution`/
`success` at lines 465–468 each honour `CARINO_TERM_GUTTER` inline, which is why unsetting that variable is part
of the kill switch in §10.

---

## 2. The patch table

| # | Location | Change | Risk |
| --- | --- | --- | --- |
| P1 | before `setup.sh:9` | `exec 9>&1` — the real stdout, snapshotted before it becomes a pipe | none |
| P2 | `setup.sh:9` | tee gains an ANSI-stripping branch, so the log is byte-clean and the terminal keeps colour | medium; must stay above `enableDryRun` |
| P3 | after `setup.sh:20` | the `carinoLoad` bootstrap + shims + `carino_term_init` | new code only |
| P4 | `setup.sh:12` | unchanged — `RED/BLUE/GREEN/YELLOW/ENDCOLOR` stay defined | none |
| P5 | `setup.sh:16-19` | unchanged — **keep** the four bodies; the library shadows them because P3 sits below | none |
| P6 | `setup.sh:12` | `locale_language` reads `${LC_ALL:-${LC_MESSAGES:-$LANG}}` | separate small patch, optional |
| P7 | `setupPrivilege`, `setup.sh:27-28` | `--preserve-env=` on the sudo arm | **deferred**, see §7 |
| P8 | `setup.sh:752`, `tools/check-packages.sh:122` | `carino_rule` replaces the dash literal | none |
| P9 | new function + 5 call sites | `carino_probe_parallel_flags` on the dnf install lines, opt-in | medium |

The order matters: **P3 must come after P5's lines, not before them.** See §4.

---

## 3. P1 and P2 — the tee and the tty snapshot

### Before (`setup.sh:8-10`, verbatim)

```bash
NONINTERACTIVE=0 # the single flag every prompt in this file reads, runPlan sets it to 1 so each read takes its documented default and says so instead of blocking on stdin
exec > >(tee -a "$LOG") 2>&1
set -f # the package lists carry dnf style globs, without noglob the shell expands ffmpeg*, rocm* and lm*sensors against the working directory and hands the package manager a tarball name instead
```

### After

```bash
NONINTERACTIVE=0 # the single flag every prompt in this file reads, runPlan sets it to 1 so each read takes its documented default and says so instead of blocking on stdin
exec 9>&1 # a read only snapshot of the real stdout taken before the line below turns fd 1 into a pipe, carino-term.sh tests [[ -t 9 ]] and reads stty size <&9 and never writes here, because every [[ -t 1 ]] in this file is false forever once the tee is in place
ESC=$(printf '\033'); BEL=$(printf '\007') # built with printf rather than written as \e, so the sed expressions below carry a real control byte instead of a two character escape the shell never expanded
if command -v sed >/dev/null 2>&1; then
    exec > >(tee >(LC_ALL=C sed -u -e "s/${ESC}\[[0-9;?]*[@-~]//g" -e "s/${ESC}\][^${BEL}]*${BEL}//g" -e 's/.*\r//' >> "$LOG")) 2>&1 # LC_ALL=C is load bearing: under a UTF-8 locale GNU sed resolves [@-~] by collation, the class stops matching m, and every escape passes straight through into the log. Verified both ways on GNU sed 4.9. The third expression collapses a \r overwritten progress line to its final state
else
    exec > >(tee -a "$LOG") 2>&1 # no sed on this system, so the log keeps its escapes exactly as it did before this patch, which is a cosmetic regression rather than a broken run. Without this arm the process substitution fails and the log is silently empty
fi
set -f # the package lists carry dnf style globs, without noglob the shell expands ffmpeg*, rocm* and lm*sensors against the working directory and hands the package manager a tarball name instead
```

### Why each piece

**`exec 9>&1`.** `[[ -t 1 ]]` is false for the whole script after the redirect. fd 9 is a real tty under a pty
and is the only honest detection surface. Detection only — the library never writes to it, which is what keeps
all output on one stream. A second output fd would bypass `test.sh`'s `$( … 2>&1 )` capture and every one of its
22 assertions would stop seeing the message it greps for.

**`LC_ALL=C`.** Verified on this machine, GNU sed 4.9, `LANG=en_US.UTF-8`:

```
$ printf 'a\033[38;2;234;179;8mgold\033[0m b\n' | LC_ALL=C sed -e "s/${ESC}\[[0-9;?]*[@-~]//g" | cat -A
agold b$
$ printf 'a\033[38;2;234;179;8mgold\033[0m b\n' | sed -e "s/${ESC}\[[0-9;?]*[@-~]//g" | cat -A
a^[[38;2;234;179;8mgold^[[0m b$
```

Without it the filter is a silent no-op. `test.sh`'s existing `[0-9;]*m` form is immune only because it names `m`
literally.

**`s/.*\r//` rather than the spec's `s/.*\r\([^\n]\)/\1/`.** Both work on GNU sed (it treats `\n` inside a
bracket as a newline), but the shorter form is equivalent, portable to POSIX bracket semantics where `[^\n]`
means "not backslash and not the letter n", and it also handles the case where a line ends immediately after the
final `\r`.

**The `sed` presence guard.** `>(… >> "$LOG")` inside `tee` — if `sed` cannot be executed the substitution
produces nothing and the log ends up empty. That is a worse failure than an unfiltered log.

**Placement above `enableDryRun`.** The process substitutions fork at line 9; `enableDryRun` modifies `PATH` at
line 1598. The real `sed` and `tee` are therefore already bound. A shimmed `tee` in this path swallows every line
of output and leaves the log empty — that failure has been reproduced. **If this patch ever moves below line
1598, it breaks.**

**A note on fd 9 inheritance.** Every child — including the `tee`, the `sed`, and every `sudo`'d package manager
— inherits fd 9 pointing at the terminal. Harmless (nothing writes to it), but it means the tty is held open by
`setup.sh:733`'s backgrounded `tar`. If that ever matters, add `exec 9>&-` immediately after
`carino_term_init` in P3, with the caveat that `carino_term_init -f` afterwards would then lose its detection
surface. `setup.sh` never re-initialises, so closing it is safe here.

---

## 4. P3 — loading the libraries

### Placement

**After `setup.sh:20` (the `profileWarning` definition), not after line 10.**

The spec says "after line 10". That is wrong for this file, and the reason is ordering: if the bootstrap runs at
line 11, then lines 16–19 execute *afterwards* and **redefine `info`/`error`/`caution`/`success` back to the old
bodies**, shadowing the library with the very thing the library is meant to replace. Two ways out:

- (a) delete lines 16–19 and bootstrap at line 11, or
- (b) **keep lines 16–19 exactly as they are and bootstrap at line 21.**

(b) is chosen. It is strictly safer: if the library fails to load for any reason, the original four bodies are
already defined and in place with their original colours, so the fallback is not a visible regression and the
shim does not have to reimplement them. It also means `locale_language` (line 12) is already resolved when
`carino_term_init` runs, so `CT_RTL` can be derived from it.

This makes **P4 and P5 no-ops**: line 12 keeps `RED/BLUE/GREEN/YELLOW/ENDCOLOR`, and lines 16–19 keep their
bodies. The library shadows the four functions, not the constants.

### Before (`setup.sh:20-21`, verbatim)

```bash
profileWarning() { [[ -n "$2" ]] || caution "No native $1 package list exists for '${DISTRIBUTION:-this system}', only the shared base packages and the Flatpaks below will be installed."; } # the specialised lists are populated in the fedora and debian arms only, on rhel, centos, amazon, arch and opensuse the profile would otherwise look identical to Basic without saying so
setupPrivilege ()
```

### After

```bash
profileWarning() { [[ -n "$2" ]] || caution "No native $1 package list exists for '${DISTRIBUTION:-this system}', only the shared base packages and the Flatpaks below will be installed."; } # the specialised lists are populated in the fedora and debian arms only, on rhel, centos, amazon, arch and opensuse the profile would otherwise look identical to Basic without saying so
# Carino terminal design system. The four bodies above stay defined on purpose: they are the fallback, so a
# failed load is the old colours rather than an undefined function. carino-term.sh shadows them when it loads.
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
setupPrivilege ()
```

`carinoTermShim` and `carinoProbeShim` are defined immediately above `carinoLoad` (they are ~25 lines; see §4.2).

### Why each rung

**Local first.** Fleet convention is copied files per repo — `carino-navbar.js`, `carino-clock.js`,
`carino-lang.js` and `fonts/carino-fonts.css` are already copied into this repository, and the two `.sh` files
join them. Local also means a developer's edit takes effect without a deploy.

**Fetch second, no checksum pin.** From the same origin that served `setup.sh` over HTTPS. A pinned hash would
break on every library update, and the fetch inherits exactly the trust the user already extended when they piped
`setup.sh` into bash.

**Shim third.** A network hiccup must never stop a setup run over a cosmetic dependency.

Rejected alternatives: *inlining at build time* — the deployed `setup.sh` would then diverge from the repository
one, and `test.sh:19-21` greps the source file. *Hard failure* — disproportionate.

`curl` is deliberately left real by `enableDryRun` (`setup.sh:1593` names `lspci`, `uname`, `curl` and `grep` as
the detection commands that stay real), and this block sits at line ~21, long before `enableDryRun` at line 1598,
so the fetch rung behaves identically in a rehearsal. `set -f` is already on at line 10 and does not affect
sourcing.

### 4.1 What the dry run sees

Nothing. The bootstrap runs `curl` (real, unshimmed, prints nothing on success) and sources a file. It runs no
`sudo`, no `mkdir`, no `tee`, no `sed`. It emits no `DRY-RUN:` line, which is what keeps `test.sh:84`, `:86`,
`:106`, `:185`, `:200`, `:209` and `:211` at zero.

### 4.2 The shim — a hard API contract

`carinoTermShim` and `carinoProbeShim` must define **every** public name in CARINO-TERM.md §5 and §10, so no call
site can ever reference an undefined function. Because P3 sits below lines 16–19, the shim does **not** need to
define `info`/`error`/`caution`/`success`/`profileWarning` — they already exist.

```bash
carinoTermShim ()
{
    carino_msg()  { printf '%b\n' "$2"; }                       # kind is ignored, no gutter, so a shimmed run is plain but never wrong
    carino_ok()   { printf '%b\n' "$1"; }; carino_warn() { printf '%b\n' "$1"; }
    carino_fail() { printf '%b\n' "$1"; }; carino_note() { printf '%b\n' "$1"; }
    carino_say()  { printf '%b\n' "$1"; }; carino_em()   { printf '%s' "$1"; }
    carino_section() { printf '\n%b\n' "$1"; }
    carino_rule()    { printf '%s\n' "-------------------------------------"; }
    carino_kv()      { printf '%s: %s\n' "$1" "$2"; }
    carino_menu()    { printf '%b\n' "$1"; }
    carino_banner()  { printf '%s\n' "CARINO SYSTEMS"; }
    carino_ask()     { local __v="${2:-}" __d="${3:-}" __a=""; if [[ "${NONINTERACTIVE:-0}" == 1 ]] || [[ ! -t 0 ]]; then caution "Non-interactive run: ${__v}=${__d} (default: ${__d})."; printf -v "$__v" '%s' "$__d"; return 0; fi; read -r -p "$1 " __a; [[ -n "$__a" ]] || __a="$__d"; printf -v "$__v" '%s' "$__a"; } # read into __a and not into "$__v" so that a bare Enter takes the default exactly as carino-term.sh:590 does: read returns 0 on an empty line, so the old "read || default" form fired only at EOF and handed the caller an empty string where carino_confirm, two lines down, honours the same default. The same two guards carino-term.sh:582 uses, because without the first one a CARINO_SETUP_PLAN run with the library missing blocks forever on a question nobody is there to answer, and without -t 0 a "curl ... | bash" run reads its own remaining bytes as the answer and then executes a script with a hole in it; -t 0 rather than CT_STDIN_TTY because the shim only ever runs when carino-term.sh did not load, so no CT_* variable exists. caution is safe here only because P3 sits below setup.sh:16-19, so this block must never be moved above those four legacy bodies
    carino_confirm() { local __d="${2:-n}" __n="${3:-answer}" __a="" __s='[y/N]' __w=no; [[ "$__d" == y ]] && { __s='[Y/n]'; __w=yes; }; if [[ "${NONINTERACTIVE:-0}" == 1 ]] || [[ ! -t 0 ]]; then caution "Non-interactive run: ${__n}=${__w} (default: ${__w})."; [[ "$__d" == y ]]; return; fi; read -r -p "$1 ${__s} " __a; [[ -n "$__a" ]] || __a="$__d"; [[ "$__a" == [Yy]* ]]; } # NONINTERACTIVE alone left the pipe case open: under "curl ... | bash" stdin is the script itself, so the old bare read swallowed the next lines of setup.sh and answered the question with them; the announcement is the library's verbatim phrasing from carino-term.sh:605 because a plan that silently skips a question never tells the user which way it was answered, and returning 1 here is the value "no", not a failure
    carino_step_begin() { printf '%s\n' "  $1"; }; carino_step_end() { printf '%s\n' "  $1"; }
    carino_progress()   { :; }; carino_selected() { printf '%s\n' "> $1"; }
    carino_term_init()  { :; }; carino_term_selftest() { printf '%s\n' "carino-term.sh is not loaded, this is the built-in shim."; }
    carino_width()      { printf '%s' "${#1}"; }; carino_pad() { printf '%s' "$1"; }; carino_truncate() { printf '%s' "$1"; }
    carino_term_cjk_ok() { return 1; }
    carinoTermDemo()     { carino_term_selftest; }
}
carinoProbeShim ()
{
    carino_probe()      { printf 'unknown\n'; return 1; }
    carino_probe_load() { return 1; }                           # the warming call; a no-op here, but it must EXIST or setup.sh's resolver references an undefined function
    carino_probe_has()  { return 1; }
    carino_probe_int()  { printf '0\n'; return 1; }
    carino_probe_all()  { :; }; carino_probe_report() { :; }; carino_probe_reset() { :; }; carinoProbeReport() { carino_probe_report "$@"; } # carino-probe.sh:776 exports the camelCase alias as a public name too, and a call site written in that spelling would print "command not found", one of the five strings test.sh:147 fails an entire run for
    carino_probe_parallel_suggest() { printf '0 unmeasured\n'; }
    carino_probe_parallel_flags()   { :; }                      # prints nothing, so "$parallelFlags" stays empty and every install line is unchanged
    carino_probe_can_gpu_accel()    { printf 'none no-probe\n'; }
    carino_probe_enough_disk()      { return 1; }
}
```

**This list is the API freeze.** Any function added to either library must be added to this shim in the same
patch. Two implementers working in parallel diff their public names against it.

---

## 5. P6 — `locale_language` (optional, separate)

### Before (`setup.sh:12`, the relevant fragment)

```bash
locale_language=$(locale | grep "LANG=" | cut -d'=' -f2)
```

### After

```bash
locale_language="${LC_ALL:-${LC_MESSAGES:-$LANG}}" # three forks replaced by a parameter expansion, and it now honours the precedence the C library actually uses, so an LC_ALL=C run does not select a UTF-8 menu for a byte mode terminal. Note he_IL with no suffix resolves to ISO-8859-8, which is a supported fleet locale that legitimately lands in byte mode
```

Behaviour on the current machine is identical (`LANG=en_US.UTF-8`, no `LC_ALL`, no `LC_MESSAGES` exported). The
change matters only when `LC_ALL` or `LC_MESSAGES` disagrees with `LANG`, which is precisely the case where the
present code picks the wrong menu.

`test.sh:22-30` reads the menu strings out of the source and does not exercise `load_dictionary`, so this patch
is not covered by any assertion. Ship it separately so it can be reverted on its own.

---

## 6. P8 — the dash rule

### `setup.sh:752`

Before:
```bash
            info "No Windows shared folders were added\n--------------------------------------"
```
After:
```bash
            info "No Windows shared folders were added"; carino_rule
```

### `tools/check-packages.sh:122`

Before:
```bash
echo -e "\n${BLUE}-------------------------------------${ENDCOLOR}"
```
After:
```bash
printf '\n'; carino_rule
```

(`tools/check-packages.sh` is not on the do-not-edit list and is one of the two working demonstrations. It needs
the same bootstrap block from §4 near its top, after `cd "$(dirname "$0")/.." || exit 1` at line 6.)

**`test.sh:255` is left alone.** The spec lists it as a third site, but `test.sh` is on the do-not-edit list.

The other sixteen dash runs live inside the translated `tech_setup_*` and `purpose_setup_*` strings at
`setup.sh:69-84` and are scraped by `test.sh:19`. **Out of scope.** Changing them would require re-verifying all
sixteen menu-numbering assertions in eight languages for no visual gain.

---

## 7. P7 — `--preserve-env` (deferred, with reasoning)

The spec asks for `--preserve-env=CARINO_TERM_COLOR,CARINO_TERM_CHARSET,NO_COLOR,COLORTERM,TERM` on the sudo arm
of `setupPrivilege` and the `--setenv=` equivalents on the run0 arm.

**Recommendation: defer.** The reasoning:

`setup.sh:27-28` is the sudo arm, and it defines *nothing* — it sets `privilegeTool="sudo"` and relies on the
~120 literal `sudo …` calls throughout the file being correct as written. Implementing P7 means introducing a
`sudo()` wrapper function for the sudo arm, where today there is none:

```bash
sudo() { command sudo --preserve-env=CARINO_TERM_COLOR,CARINO_TERM_CHARSET,NO_COLOR,COLORTERM,TERM "$@"; }
```

That inserts a function in front of every privileged call in the file, and `enableDryRun` then has to keep
working (it already does `unset -f sudo` at line 1594, so a rehearsal is fine, but the real path is not exercised
by `test.sh` at all).

And the benefit is small: the escapes are emitted by `setup.sh` itself, in the parent shell. The only thing P7
buys is that `dnf`/`apt` colourise *their own* output — which is their business and which they already decide
from their own tty check. It does **not** affect the branding of any line this patch is about.

Ship it later, on its own, if Miguel wants child-process colour. It is not a prerequisite for anything here.

---

## 8. P9 — where the `max_parallel_downloads` decision is consulted

### 8.1 The shape of the decision

**No configuration file is ever written.** The flags are passed per invocation:
`--setopt=max_parallel_downloads=N --setopt=max_downloads_per_mirror=N`. No persistent change means no way to
leave a user with a `Librepo error: Bad value of LRO_MAXPARALLELDOWNLOADS` that survives the run, no duplicate
appended lines, and no dry-run write problem. `rpm-ostree` has no `--setopt`, so atomic systems get nothing and
are **not** told "this does nothing on your system", because that claim is unverified.

### 8.2 Should it prompt? Yes — and here is what the README contract requires

The README's "Read this before you run it" section (lines 9–22) is a disclosure contract for things the script
does **without asking**. A bandwidth measurement is:

- an outbound HTTPS request the user did not ask for,
- a download of up to **8 MiB** (median-of-3 escalation: up to 20 MiB) of real mirror traffic,
- on a link that may be metered.

That is exactly the class of thing the contract exists to disclose. Two options, and the recommendation is the
second:

1. Disclose it as an unprompted action in the "Read this before you run it" list.
2. **Prompt for it, `[y/N]`, default no, and disclose that it exists at all.**

Option 2 wins because the probe already refuses to run under `NONINTERACTIVE` and `DRYRUN`, so the prompt is the
only path that reaches it anyway, and a `[y/N]` default-no needs a much weaker disclosure than an unprompted
8 MiB download.

**New README lines required.** Three:

- In the bullet list at lines 13–20, after the log bullet at line 20:

  > - **It offers to measure your download speed** before the Technical Setup, and only if you say yes. This fetches up to 8 MiB from *your own distribution's configured mirror* — not a Carino server and not a generic speed-test CDN, because a generic CDN measured 7x slower than the real mirror on the test machine and would invert the answer. It asks first, `[y/N]`, defaulting to **no**; it is skipped entirely on a metered connection, under a plan, and in a dry run; and whatever it measures, **nothing is written to `/etc/dnf/dnf.conf` or any other configuration file** — the result is passed as `--setopt=` on that run's `dnf` command line and is forgotten when the run ends.

- In the "Which default every prompt takes under a plan" table at lines 196–203, a new row:

  > | Bandwidth measurement `[y/N]` | **no** — a plan is unattended, and an 8 MiB probe multiplied across an unattended fleet is not defensible. Set `CARINO_PROBE_NET=1` to opt in. |

- In the "Environment variables" table at lines 219–224, three new rows:

  > | `CARINO_PROBE_NET` | `0` disables the bandwidth probe entirely. `1` re-enables it under `CARINO_SETUP_PLAN` and a dry run, where it is otherwise always skipped. |
  > | `CARINO_TERM_COLOR` | `never` `auto` `always` `8` `256` `truecolor`. `never` is also the light-terminal escape hatch. |
  > | `CARINO_TERM_CHARSET` | `ascii` or `unicode`, overriding the locale probe. |

  The sentence at line 231, "These four are read by `setup.sh` only", becomes "These are read by `setup.sh` only"
  — the count is no longer four.

- In "Rehearsing a run" at line 215, append to the final sentence:

  > The bandwidth probe is skipped entirely during a rehearsal, so a dry run makes no network request beyond the ones it already made (`curl` to GitHub and kernel.org for the menu header).

**`test.sh:110` reads the README's argument list**, not these tables:
`doc=$(grep -oE '^- [a-z][a-z-]*\\?$' README.md | sed 's/^- //; s/\\$//' | sort -u)`. The new bullet starts
`- **It offers…`, which does not match `^- [a-z][a-z-]*\\?$`. The new table rows are not `- `-prefixed. **No
argument-parity assertion is affected.** This was checked because adding a stray `- word` line to README.md is
the single easiest way to break `test.sh` section 5.

### 8.3 The code

**New function**, inserted after `profileWarning` at `setup.sh:20` and before the `carinoLoad` block from §4
(order within that region does not matter; it is all function definitions):

```bash
parallelFlags="" # appended to the dnf command lines that download the most, empty on every family and every path that did not measure, so an unmeasured run is byte identical to today
resolveParallelDownloads ()
{
    [[ -n "$parallelResolved" ]] && return 0; parallelResolved=1 # once per run, techSetup and updateSystem both call it and only the first does any work
    [[ "$NONINTERACTIVE" == 1 || "$DRYRUN" == 1 ]] && return 0 # a plan is unattended and a rehearsal downloads nothing, carino-probe refuses in both cases anyway, this is the second lock on the same door
    case "$pkgm" in dnf|dnf5) ;; *) return 0 ;; esac # apt ships no such knob, pacman already defaults to 5, zypper's option means chunks of one file, rpm-ostree has no --setopt: on all four there is nothing to ask about, so nothing is asked. dnf5 is listed for the day setup.sh learns to spell it; today every RPM family arm sets pkgm=dnf (127, 160, 178, 196) even on a box where the binary is dnf5, which is what carino-probe reports as pkg.manager
    carino_confirm "Measure this machine's download speed to tune parallel downloads? It fetches up to 8 MiB from your own configured mirror and writes no configuration." n || { caution "No speed measurement was taken, the package manager's own defaults are used."; return 0; }
    carino_probe_load net.speed.bps # WARMS THE MEMO IN THIS SHELL, and it has to happen before either $( ) below: memoisation lives in shell variables, $( ) forks a subshell, and both helpers resolve net.speed.bps internally, so without this line the machine is measured TWICE and downloads 16 MiB instead of 8
    local suggest n reason; suggest=$(carino_probe_parallel_suggest); n="${suggest%% *}"; reason="${suggest#* }"
    if [[ "$n" == 0 ]]; then
        caution "Parallel downloads are left at the package manager's default ($reason)." # unmeasured, slow-link, metered and no-mirror all land here, and every one of them means change nothing
        return 0
    fi
    parallelFlags=$(carino_probe_parallel_flags)
    caution "This mirror measured $reason, so dnf will use $n parallel downloads for this run only. Nothing was written to /etc/dnf/dnf.conf." # "this mirror right now", never "your connection speed", because MirrorManager sorts by netblock preference and the pref-100 mirror was 7x slower than pref-99 on the test machine
}
```

**Call sites.** `resolveParallelDownloads` is called **after** the `$pkgm` guard in both functions, so a declined
distribution never reaches it and `test.sh:84`/`:106` stay at zero commands.

`setup.sh:1068-1069` — before:
```bash
    fi
    if [[ "$distroType" == "atomic" ]]; then
```
after:
```bash
    fi
    resolveParallelDownloads # after the guard on purpose: a declined distribution returns above this line and must run and ask nothing at all
    if [[ "$distroType" == "atomic" ]]; then
```

`setup.sh:1230-1231` — before:
```bash
  fi
  sudo $pkgm $updatePreFlags $argUpdate $updateFlags || { error "The package index could not be refreshed, so nothing was updated. Read the package manager's message above."; return 1; } # preFlags is wrong here, apt rejects its -f on the update operation with
```
after:
```bash
  fi
  resolveParallelDownloads
  sudo $pkgm $updatePreFlags $parallelFlags $argUpdate $updateFlags || { error "The package index could not be refreshed, so nothing was updated. Read the package manager's message above."; return 1; } # preFlags is wrong here, apt rejects its -f on the update operation with
```

**Where `$parallelFlags` is appended.** Five lines, all of them a bulk download, all of them dnf-family only:

| Line | Before | After |
| --- | --- | --- |
| `1092` | `sudo $pkgm update -y && sudo $pkgm install $essentialPackages -y` | `sudo $pkgm update -y $parallelFlags && sudo $pkgm install $essentialPackages -y $parallelFlags` |
| `1096` | `sudo $pkgm $argUpdate -y && sudo $pkgm install $essentialPackages -y` | `sudo $pkgm $argUpdate -y $parallelFlags && sudo $pkgm install $essentialPackages -y $parallelFlags` |
| `1231` | see above | see above |
| `1232` | `sudo $pkgm $preFlags $argUpgrade $postFlags \|\| {…}` | `sudo $pkgm $preFlags $parallelFlags $argUpgrade $postFlags \|\| {…}` |
| `1059` | `sudo $pkgm $preFlags $argInstall $essentialPackages $basicSystemPackages $serverPackages $developmentPackages $postFlags` | `sudo $pkgm $preFlags $parallelFlags $argInstall …` (unchanged tail) |

**Deliberately not touched:** `setup.sh:1089` (two RPM Fusion release RPMs — too small to benefit) and the
`$preFlags`/`$postFlags` variables themselves. Appending to `preFlags` would have been a one-line change and is
rejected: `preFlags` is shared with the `rpm-ostree` arm at `setup.sh:116`, and a hidden global mutation is much
harder to review and to revert than five named lines.

### 8.4 Why this is safe under `test.sh`

Every `test.sh` invocation is either a plan (`NONINTERACTIVE=1`) or a `dry-run` (`DRYRUN=1`), and most are both.
`resolveParallelDownloads` returns at its second line in every one of them, `parallelFlags` stays empty, and
**every command line in every test run is byte-identical to today.**

Even if it did run, `test.sh:39-51 installLine` counts operands with
`for x in "${t[@]:1}"; do [[ "$x" == -* || "$x" == "$verb" ]] && continue; n=$((n+1)); done` — a
`--setopt=max_parallel_downloads=8` token starts with `-` and is skipped, so the minimum-operand assertions in
section 3 are unaffected. And `test.sh:224`'s refresh regex,
`grep -m1 -E "DRY-RUN: sudo $pkgm( .*)? $refresh( |$)"`, still matches with extra flags on either side of the
subcommand.

---

## 9. Every `test.sh` assertion, audited

`test.sh` is on the do-not-edit list, so the goal is to prove that **none of its 22 assertion families needs a
new expected string** — and to name the two places where something outside `test.sh` must change so that it keeps
passing.

### 9.1 The one assertion that genuinely needs updating

**`test.sh:14`**

```bash
for f in setup.sh macos.sh test.sh tools/check-packages.sh; do
```

The two new libraries are not parsed. New expected line:

```bash
for f in setup.sh macos.sh test.sh tools/check-packages.sh carino-term.sh carino-probe.sh; do
```

This is the only change `test.sh` needs, and it is additive. Since `test.sh` is off-limits, flag it for Miguel to
apply by hand; until then, run `bash -n carino-term.sh carino-probe.sh` in CI or by hand.

### 9.2 The one assertion that needs a deploy, not an edit

**`test.sh:243`**

```bash
for u in $(grep -ohE 'https?://[a-zA-Z0-9./_-]+' README.md index.html | sort -u); do
    c=$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 15 "$u")
    [[ "$c" == 200 ]] && ok "$c $u" || bad "$c $u"
```

The URL class includes `-` and `.`, so if the README documentation ever spells out
`https://setup.carino.systems/carino-term.sh`, `test.sh --network` will fetch it and require **200**. Either
deploy both libraries to the site *before* the README mentions the URL, or keep the URL out of README.md and
index.html (it is already spelled out in CARINO-TERM.md, which the scraper does not read).

### 9.3 Everything else — unchanged, with the reason

| Assertion | Quoted | Why it is unaffected |
| --- | --- | --- |
| `:19-21` menu scraping | `grep -m1 "^\s*$1=" setup.sh \| grep -o '\\n[0-9]\+\.'` | Reads the *source* of the `tech_setup_*` strings. P8 does not touch lines 69–84. `carino_menu` is a pass-through that never renumbers. |
| `:26-28` menu-vs-case parity | `bad "$var prints [$printed] but $fn dispatches [$dispatched]"` | Same — source scraping only. |
| `:36-38` runners | `timeout 90 bash setup.sh dry-run` | Fixed by §1.1. Also: inside `$( … )`, fd 9 is a dup of a pipe, so `[[ -t 9 ]]` is false → `CT_INTERACTIVE=0` → `CT_DEPTH=0` → **the libraries emit zero escape sequences during the entire test suite.** Verified. |
| `:47` operand counting | `[[ "$x" == -* \|\| "$x" == "$verb" ]] && continue` | `--setopt=…` tokens are `-`-prefixed and skipped. |
| `:56-65` install shape | `[[ " $line " == *" $flag "* ]] \|\| why=…` | `parallelFlags` is empty under `dry-run`; and if it were not, it adds only `-`-prefixed tokens. |
| `:84-87` declined distributions | `n=$(grep -c 'DRY-RUN:' <<<"$out")` … `grep -q 'not supported'` | The bootstrap emits no `DRY-RUN:` line. `resolveParallelDownloads` sits below the `$pkgm` guard. The refusal at `setup.sh:243` is still one 380-character line — **`error()` must never wrap**, which is the whole reason the legacy four render whole-line with no reflow. |
| `:106` unknown distribution | `[[ $(grep -c 'DRY-RUN:' <<<"$out") -eq 0 ]]` | Same. |
| `:109-113` argument parity | `doc=$(grep -oE '^- [a-z][a-z-]*\\?$' README.md …)` | No new argument. The new README bullet starts `- **It offers…` and the new table rows are not `- `-prefixed, so neither matches the pattern. Checked in §8.2. |
| `:116-125` desktop lists | `grep -m1 "^${f}${d}Packages=" setup.sh` | Source scraping only. |
| `:142` argument coverage | `grep -q "^$a\|" <<<"$ARGTABLE"` | No new argument. |
| `:147` shell errors | `grep -qE 'command not found\|syntax error\|unbound variable\|bad substitution\|: line [0-9]+:'` | **The highest-risk assertion in the file.** Three guards: the libraries silence every subprocess with `2>/dev/null`; the `curl` rung uses `-f` so a 404 body is never evaluated; and the source in §4 is wrapped `{ … } 2>/dev/null` with a `declare -F` sanity check, so a *truncated* body cannot print `: line 41: syntax error` into the capture. |
| `:149` dnf reached | `grep -qE 'DRY-RUN: sudo dnf (install\|update\|config-manager)'` | The verb still follows `sudo dnf` in `1092`/`1096` because `$parallelFlags` is appended after it, and it is empty in a dry run regardless. |
| `:159, :176, :182, :198, :201, :203, :223` ANSI strip | `sed 's/\x1b\[[0-9;]*m//g'` | Every sequence the library emits is `\e[` + digits/semicolons + `m`, the 24-bit `\e[38;2;234;179;8m` form included. The strip still works. Under `$( )` there are no escapes to strip in the first place, so these become no-ops. They must **not** be deleted — `test.sh` is off-limits and they are harmless. |
| `:162` plan marker | `grep -q "$marker" <<<"$clean"` | `caution "Plan step: technical"` is untouched by Stage 1. |
| `:163` no numbered menu | `grep -qE '^[0-9]+\. ' <<<"$clean" && why="…a numbered menu was drawn…"` | **This is a negative assertion and it is the reason `CARINO_TERM_GUTTER` defaults to 0.** A six-column gutter would turn `1. Basic` into `[note] 1. Basic`, the regex would stop matching, and the test would start passing *vacuously* — green, and no longer testing anything. Stage 1 adds no prefix, so it keeps testing what it was written to test. |
| `:164` plan completion | `grep -q 'CARINO_SETUP_PLAN has finished'` | `success` string untouched. |
| `:178` plan ordering | `[[ "$order" == "technical/desktop kde/purpose gaming/" ]]` | `caution` strings untouched. |
| `:184-187` bad plans | `grep -qF "$token"`, `grep -qF "$valids"` | `error` strings untouched, and refusal happens in `planValidate` before `techSetup` is ever reached. |
| `:199` wrapped plan | `grep -qF "'nope' is not a purpose name"` | Untouched. |
| `:202` reboot default | `grep -q 'Non-interactive run: reboot=no (default: no)'` | Untouched, and **`resolveParallelDownloads` must not print a competing `Non-interactive run:` line** — it returns silently under `NONINTERACTIVE`, which is why the second line of the function is a bare `return 0` with no message. |
| `:204` reboot=yes | `grep -q 'DRY-RUN: sudo reboot'` | Untouched. |
| `:208` declined plan | `grep -q 'was refused and nothing was installed'` | Untouched. |
| `:212-218` frozen names | `awk '/^planPurposeNumber/,/^}/' setup.sh \| grep -qE "^\s*$name\)"` | Source scraping only. |
| `:221-229` refresh flags | `grep -m1 -E "DRY-RUN: sudo $pkgm( .*)? $refresh( \|$)"` | `$parallelFlags` inserted before `$argUpdate` still leaves `( .*)? update( \|$)` matching, and `-y` is still in the line. Empty in every test run anyway. |
| `:247` Flathub scraping | `sed 's/#.*\$//' setup.sh \| grep -oE '\b[a-z][a-z0-9_]*(\.[A-Za-z][A-Za-z0-9_-]*){2,}\b'` | **Fixed by the rule in §1.2**: no two-dot probe key appears in `setup.sh` outside a comment. `carino_probe_parallel_flags` and `carino_probe_parallel_suggest` have no dots. |
| `:255` the dash rule | `echo -e "\n${BLUE}----…----${ENDCOLOR}"` | Left alone; `test.sh` is off-limits. |

### 9.4 Tripwires to re-run after applying

```bash
bash -n setup.sh carino-term.sh carino-probe.sh   # section 1 by hand, since test.sh does not know the new files yet
./test.sh                                         # all 22 families, offline
./test.sh --network                               # sections 10, the two items in §9.1 and §9.2
shellcheck -S error setup.sh carino-term.sh carino-probe.sh
```

Then, by hand:

```bash
./setup.sh dry-run            # colour on the terminal
CARINO_SETUP_LOG=/tmp/x.log ./setup.sh dry-run; grep -c $'\033' /tmp/x.log   # must be 0
./setup.sh dry-run > /tmp/plain.txt; grep -c $'\033' /tmp/plain.txt          # must be 0: a plain redirect is not a tty
NO_COLOR=1 ./setup.sh dry-run | head                                          # must be plain
CARINO_TERM_COLOR=always ./setup.sh dry-run | head                            # must be coloured despite the pipe
TERM=linux CARINO_TERM_CHARSET=ascii ./setup.sh dry-run | head                # must use - and # only
carino_term_selftest                                                          # after sourcing, prints why the depth ladder stopped where it did
```

The specific things to look at in the log after P2:

1. It contains no `\033` bytes at all.
2. It contains the last line the run printed (`CARINO_SETUP_PLAN has finished.` or the menu exit line). A missing tail means the second-stage `sed` was killed before it flushed; add `-u` if it is not already there.
3. A `carino_progress` line appears once, collapsed, not once per frame.

---

## 10. Rollback

Every patch is independently revertible. Ordered from cheapest to most invasive:

| Symptom | Revert | Effect |
| --- | --- | --- |
| Colour looks wrong anywhere | *nothing* — set `CARINO_TERM_COLOR=never` in the environment | Instant, no code change, no deploy. **Try this first.** |
| The bandwidth prompt is unwelcome | Set `CARINO_PROBE_NET=0`, or revert P9 alone | P9 is one function plus six one-line call sites; `parallelFlags` empty restores today's command lines exactly. |
| The log is empty, or truncated, or still full of escapes | Revert **P2 only**, back to `exec > >(tee -a "$LOG") 2>&1` | Keeps P1 and P3, so colour still works on the terminal; the log goes back to carrying escapes, which is exactly today's behaviour. |
| Something in the library misbehaves | Delete or rename `carino-term.sh` / `carino-probe.sh` in the repo **and** make the HTTPS rung fail | The shim takes over. But note the fetch rung will find the deployed copy, so a bad *deployed* library needs the site rolled back too. |
| The two-zone gutter turned on by accident | `unset CARINO_TERM_GUTTER` | `carino-term.sh:465-468` reads it inline on every call, so this takes effect immediately with no restart and no code change. |
| Fastest total kill switch | Replace the two `carinoLoad …` lines in P3 with `carinoTermShim; carinoProbeShim` | One line each. The five legacy functions at `setup.sh:16-20` are still defined with their original colours, so the script reverts to today's exact output with no other change. This is the reason P5 keeps them. |
| Full revert | `git revert` the commit | P1–P9 are one commit; keep the Branding token patch (§11) as a *separate* commit in the Branding repo so reverting one does not require reverting the other. |

**The kill switch is the important one.** Because P5 keeps lines 16–19 intact, the difference between "the
branding system is on" and "the script behaves exactly as it did before" is two lines in the bootstrap block.
Make sure whoever reviews this knows that.

---

## 11. The companion Branding patch

Ships **with** this one, as a separate commit in `~/Github/Branding`, so that `CT_INFO` quotes a token rather
than a magic number. Four one-line edits, verified against the current files:

| File:line | Change |
| --- | --- |
| `carino-branding.css:14-35` (`:root`) | add `--info: #38bdf8;` beside `--ok` / `--warn` / `--err` (currently lines 27–29) |
| `carino-branding.css:399` | `.toast.info` uses `var(--info)` for its border and background tint, keeping `#bae6fd` as the prose tone |
| `index.html:689-695` (`TOKENS`) | add `["--info", "#38bdf8"]` — 14 colours becomes 15 |
| `index.html:795-815` (`TOKENS_CSS`) | add `--info: #38bdf8;` to the copy-block |

`.toast` is the only component in `carino-branding.css` with four states while `.alert` and `.pill` have three,
and that fourth colour currently appears in exactly one line of CSS and in neither of the two places the site
publishes its own palette. This is a real inconsistency, not a preference.

Note for the record: the spec cites `.terminal { background: #000 }` at `carino-branding.css:459`; it is
**line 461** in the current file. The contrast numbers are unaffected — the background is still pure black.

---

## 12. Summary of what a reviewer should push back on

Three places where this plan makes a judgement call that Miguel may want to overrule:

1. **P3 sits after line 20, not after line 10** (§4). The spec said line 10. If the bodies at 16–19 are deleted instead, line 10 becomes correct — but the kill switch in §10 stops working and a failed load becomes an undefined-function crash.
2. **P7 is deferred** (§7). It is in the spec; the argument for deferring is that it requires a new `sudo()` wrapper in front of ~120 privileged calls to buy child-process colour that nothing in this patch depends on.
3. **The bandwidth probe prompts rather than being disclosed as unprompted** (§8.2). The alternative — run it silently and add a bullet to the README — is faster for the user and matches how the script treats the full system upgrade, but an 8 MiB unasked-for download is a different category from a package operation the user came here for.
