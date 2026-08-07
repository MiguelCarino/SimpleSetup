# Carino Setup

Setup scripts **for Linux, Windows and macOS**, so the user does not have to worry about choices besides their actual use case.

Site: <https://setup.carino.systems>

> The GitHub repository is still literally named `SimpleSetup`. Only the owner can rename it, so every `https://github.com/MiguelCarino/SimpleSetup` link is left exactly as it is and keeps working. Renaming the repository is a pending owner action; nothing in this repository depends on it.

## Read this before you run it

`setup.sh` is not a package picker. On the Technical Setup path it changes the machine in ways that are hard to undo, and it does most of them without a confirmation:

- **It performs a full upgrade of every installed package** before it installs anything. `dnf update -y` on the Fedora, CentOS/rebuild and Amazon families, `apt update && apt upgrade -y` on the Debian family, `pacman -Syu` on Arch, `rpm-ostree upgrade` on the atomic Fedora images, and `zypper dup` on Tumbleweed and Slowroll, which is a true rolling **distribution** upgrade rather than a package refresh. Red Hat Enterprise Linux is the one family whose Technical Setup does not upgrade the system.
- **It enables third-party repositories.** RPM Fusion **free and nonfree** on Fedora; **EPEL** plus **CRB** (`powertools` on 8) on CentOS Stream and the RHEL rebuilds; **EPEL** plus the `codeready-builder` repository through `subscription-manager` on RHEL itself; **Flathub**, added system-wide, on every family. Enabling the driver step can add more: Debian gets a `contrib non-free non-free-firmware` drop-in at `/etc/apt/sources.list.d/carino-nonfree.sources`, and openSUSE gets NVIDIA's own repository through the matching `openSUSE-repos-*-NVIDIA` package.
- **It swaps Fedora's codecs for the freeworld builds.** `ffmpeg-free` becomes `ffmpeg`, `mesa-va-drivers` and `mesa-vdpau-drivers` become their `-freeworld` counterparts, and `libavcodec-freeworld` is added. Fedora only, and only once RPM Fusion is enabled.
- **It installs proprietary GPU drivers.** The NVIDIA step asks first and honours a `n`. The AMD and the Intel steps ask, but **install the same list either way** — the script ships no ROCm-free AMD list and no separate oneAPI list, and it says so on stdout rather than pretending the answer mattered. The driver step is skipped entirely if `lspci` is missing or the machine is not `x86_64`.
- **It rewrites `GRUB_TIMEOUT` to 5 in `/etc/default/grub` and regenerates the bootloader configuration.** This one prompts, `[y/N]`, defaulting to no. It is reached on Fedora only when RPM Fusion was not already enabled, and on the Nobara/Ultramarine/Bazzite group, the CentOS family and Arch.
- **It sets the default systemd target to `graphical`** after any successful desktop install, and enables `gdm`, `sddm` or `lightdm` if one of them is in the package list it just installed. No prompt.
- **It disables `NetworkManager-wait-online.service`** on Red Hat Enterprise Linux. No prompt, and RHEL only — the rebuilds and Fedora do not do this.
- **It writes a log** into the current working directory, `carino-setup-YYYYmmdd-HHMMSS.log`, unless `CARINO_SETUP_LOG` names another path.

Everything above can be watched first: see [Rehearsing a run](#rehearsing-a-run).

## Root or user?

**Run it as your normal desktop user.** The script escalates per command rather than expecting to be launched with `sudo`.

`setupPrivilege` runs before anything else and picks the tool:

| You are | What happens |
| --- | --- |
| root | Nothing is escalated. `sudo` becomes a pass-through, and the one `sudo -u <user>` call is translated to `runuser` or `su`. |
| a user with `sudo` | Used as written. |
| a user with `doas` | Used instead, arguments pass through unchanged. |
| a user with `run0` | Used instead, `-u` is rewritten to `--user=`. |
| a user with none of the three | The script says so and **stops before running anything**, rather than failing line by line. A dry run is still allowed. |

Running the whole thing as root works and is explicitly supported, but the user-facing half then lands in root's account: ProtonGE unpacks into `/root/.steam`, the i3 dotfiles and the `gsettings` theme tweaks apply to root, SVP installs under `/home/root`, and the CIFS share mounts at `/root/WinFiles`. A root shell also usually has no `XDG_CURRENT_DESKTOP`, so the Technical Setup concludes you have no desktop environment and offers to install one.

## Systems supported

### Linux

Families as matched by `identifyDistro` in `setup.sh`:

- **Debian** family — Debian, Ubuntu (and the Ubuntu flavours, which all report `NAME=Ubuntu`), Pop!_OS, Linux Mint, LMDE, Zorin, elementary, Kali, Parrot, Devuan, Raspbian / Raspberry Pi OS, MX, antiX, Deepin, KDE neon, Trisquel, PureOS, TUXEDO, PikaOS, Armbian, SparkyLinux, Q4OS. Package manager `apt`.
- **Fedora** family — Fedora, Nobara, Risi, Ultramarine, plus the atomic/image-based variants Silverblue, Kinoite, Sericea, Onyx, Bazzite, Bluefin, Aurora and Universal Blue. Package manager `dnf`, and `rpm-ostree` is used automatically wherever it is present. On an atomic system only the essential packages are layered: RPM Fusion, the codec swap and the GRUB step do not apply there.
- **Red Hat Enterprise Linux** — package manager `dnf`, with the extra RHEL package set.
- **CentOS** family, i.e. CentOS Stream and the RHEL rebuilds — Rocky, AlmaLinux, Oracle Linux, EuroLinux, Circle Linux, Springdale, Anolis, OpenCloudOS, TencentOS, Alibaba Cloud Linux, CloudLinux. Package manager `dnf`.
- **Amazon Linux** — package manager `dnf`. It carries no EPEL and no CRB, and the script cautions you about that on detection. In practice the only path it genuinely refuses is the **desktop** one: no `amazon*Packages` desktop lists exist, so `installDesktopEnvironment` names the missing list and declines. The Technical Setup, the server setup, the driver step, the system update and every purpose profile all run, from the Amazon repositories alone.
- **Arch** family — Arch, Manjaro, EndeavourOS, Garuda, CachyOS, ArcoLinux, RebornOS, Archcraft. Package manager `pacman` with `--noconfirm --needed`; the package lists are replaced with Arch-specific ones rather than appended, essential packages are installed one at a time so an unknown name cannot abort the transaction, and all the desktop environments are available.
- **openSUSE** Leap and Tumbleweed, plus SUSE/SLES/SLED — package manager `zypper`. **Still being tested**, and the script says so when it detects you.

### Deliberately not supported

SteamOS/Holo, Artix, Parabola, Gentoo, Slackware, NixOS, Guix System, Alpine, Void, Clear Linux, Solus, Qubes, Mageia, OpenMandriva, Chimera, and the transactional openSUSE variants (MicroOS, Aeon, Kalpa, Leap Micro, SLE Micro, SL Micro). Each refusal explains what specifically does not map — read-only images, a non-systemd init, a declarative configuration, musl libc, no dependency resolution, and so on.

**A refusal does not end the run.** `identifyDistro` only detects: it prints the reason, leaves `$pkgm`, `$family` and the flags empty, and the script carries on to the menu. The menu is drawn as usual and every option then refuses individually — the Technical Setup, the purpose profiles, the drivers, the update and the server setup all check for a package manager and stop with a message, and the desktop menu refuses by name because no package list exists for an unmapped family. The practical result is that a declined distribution runs **zero** commands, which is exactly what `test.sh` asserts, but you get there through a menu rather than through an early exit.

A plan is stricter: `CARINO_SETUP_PLAN` on a declined distribution is refused outright and the script exits without drawing anything.

Anything not matched at all falls to the default arm, which reports the distribution and version it actually read from `/etc/os-release` and notes that no package manager, package family or flags were configured.

Just open your terminal and paste

```bash
bash <(curl -s https://setup.carino.systems/setup.sh)
```

### Windows

Windows 10 (build 10240 and up) and Windows 11 (build 22000 and up), through `setup.ps1`.

```powershell
iwr -useb https://setup.carino.systems/setup.ps1 | iex
```

### macOS

Homebrew-based, four use-case profiles, through `macos.sh`. Apple Silicon and Intel.

```bash
bash <(curl -s https://setup.carino.systems/macos.sh)
```

## Main features

- **Automatic distro identification**.
- **Quick setup**: install and forget.
- **Technical Setup**: repositories, essential packages, Flathub, then a desktop environment if none is running, the graphic drivers and the final tweaks.
- **Purpose Setup**: 15 purposes — Basic, Gaming, Corporate, Corporate (Microsoft only), Corporate (Google only), Development, Astronomy, Computational Neuroscience, Design, Music Production, Cybersecurity, Forensics, Scientific, Robotics, Medical Imaging. The specialised package lists exist for Fedora and Debian only; on the other families the profile installs the shared base plus its Flatpaks and says so first.
- **Menu options**: Technical Setup, Purpose Setup, install a Desktop Environment, install graphic drivers, update the system, server setup, exit.
- **Desktop Environments**: GNOME, XFCE, KDE, LXQt, Cinnamon, MATE, i3, Openbox, Budgie, Sway, Hyprland, Niri, or none. Not every family has a list for all twelve, and where the list is missing the desktop is named and refused rather than skipped silently:

  | Family | Desktops available |
  | --- | --- |
  | Fedora, Arch | all twelve |
  | Debian, openSUSE | all except Hyprland and Niri |
  | CentOS/rebuilds | all except Budgie, Sway, Hyprland and Niri |
  | Red Hat Enterprise Linux | GNOME, XFCE, KDE |
  | Amazon Linux | none |

  The CentOS row is the one that is not a refusal. `centosbudgiePackages`, `centosswayPackages`, `centoshyprlandPackages` and `centosniriPackages` are all non-empty, so nothing declines them, but no EPEL release ships `budgie-desktop`, `sway`, `waybar`, `hyprland` or `niri` — checked against the EPEL 9 and EPEL 10 package indexes and against `dnf list --available` in `quay.io/centos/centos:stream9`, where only `i3`, `openbox` and `fastfetch` resolve. Because the CentOS arm passes `--skip-broken --setopt=strict=0`, `dnf` exits 0 having installed nothing, `graphical.target` is still set and the run reports success, so ask for one of these four on CentOS and you get a machine with no session. The plan builder does not offer them there. `i3` and `openbox` are in EPEL 9 only; EPEL 10 has neither.

- **Argument support** and **unattended plans**.
- **Dry run** for every path.
- **Multilingual menus**: English, Japanese, Russian, Spanish, Finnish, Chinese, Korean, Hebrew, with automatic locale detection. Any other locale falls back to English. This applies to `setup.sh` alone.

## Arguments

*All arguments are passed straight to the script*\
bash <(curl -s https://setup.carino.systems/setup.sh) **argument**\
./setup.sh **argument**

Running it with no argument, or with an unrecognised one, opens the interactive menu.

### General arguments
- quick\
  Runs the Technical Setup, then installs the basic user, basic system and support packages plus the basic and Google flatpaks.

- simple\
  Runs the Technical Setup only.

- server\
  Configures a minimal server setup with essential development packages. This does not include the full Technical Setup.

### Graphics driver installation
Each of these runs the same `graphicDrivers` step, which identifies the card with `lspci` itself; the argument you pick does not force a vendor.

- nvidia\
  Installs Nvidia graphic drivers.

- amd\
  Installs AMD graphic drivers.

- intel\
  Installs Intel graphic drivers.

### Special programs
- svp\
  Installs Smooth Video Project for enhanced video playback.

- distrobox\
  Installs Distrobox containers for running multiple Linux distributions seamlessly.

- proton\
  Downloads and installs the latest ProtonGE release, skipping the download if you already have it.

- librewolf\
  Adds the LibreWolf repository and installs LibreWolf. Fedora and Debian families only.

- anydesk\
  Installs flatpak, enables Flathub, and installs the AnyDesk and RustDesk flatpaks.

- anydesk-repo\
  Adds the official AnyDesk repository and installs AnyDesk natively instead of as a flatpak.

### System and storage
- share\
  Prompts for a server, share and user, then mounts a Windows/CIFS share at `~/WinFiles`.

### Desktop environment setup
- desktop\
  Opens a menu to select and install a Desktop Environment from a curated list.

**Note:** updating the system is menu option 5, not an argument. There is no `update` argument in `setup.sh`; use `CARINO_SETUP_PLAN=update` below.

## Unattended runs: `CARINO_SETUP_PLAN`

`CARINO_SETUP_PLAN` is a comma-separated list of directives, executed strictly left to right. When it is set the run is non-interactive: no menu is drawn and no prompt is read, and every prompt takes its documented default and says so on stdout.

```bash
CARINO_SETUP_PLAN=technical,desktop=kde,purpose=gaming bash <(curl -s https://setup.carino.systems/setup.sh)
```

Directives:

| Directive | What it does |
| --- | --- |
| `technical` | Runs the Technical Setup: repositories, essential packages, Flathub, then drivers and tweaks. |
| `purpose=<name>` | Runs one Purpose profile by name. |
| `desktop=<name>` | Installs one desktop environment by name. |
| `drivers` | Runs the graphic driver install. |
| `update` | Runs the system update. |
| `server` | Runs the server setup. |
| `reboot=yes` / `reboot=no` | Whether to reboot at the end. Default: `no`. This is a modifier on a plan, not a step in one, so it needs something to follow: a plan whose only directive is `reboot=yes` names no action and is refused before anything is installed. |

Purpose names: `basic`, `gaming`, `corporate`, `corporate-microsoft`, `corporate-google`, `development`, `astronomy`, `compneuro`, `design`, `music`, `cybersecurity`, `forensics`, `scientific`, `robotics`.

Desktop names: `gnome`, `xfce`, `kde`, `lxqt`, `cinnamon`, `mate`, `i3`, `openbox`, `budgie`, `sway`, `hyprland`, `niri`, `none`.

Names, never numbers: the menus have been renumbered twice, so a shared plan that encoded numbers would silently start meaning something else. An unrecognised directive or an unknown name is a hard error that names the bad token, lists the valid ones and stops **before anything is installed**. The plan runs instead of the menu and the script exits when it finishes, it never falls through into the menu. A plan and a command-line argument together are refused, run one or the other.

### Which default every prompt takes under a plan

| Prompt | Default taken |
| --- | --- |
| NVIDIA / AMD / Intel driver `(y/n)` | **yes** — a driver step in the plan was asked for explicitly |
| GRUB rewrite `[y/N]` | **no** — the bootloader is left alone |
| i3 dotfiles replacement `[y/N]` | **no** — your i3 configuration is left untouched |
| Windows share `[y/N]` | **no** — a plan carries no server, folder or user to ask for |
| Desktop environment menu | **none** — add `desktop=<name>` to install one |
| Reboot `[y/N]` | **no**, unless `reboot=yes` is in the plan |

## Rehearsing a run

`dry-run` is a modifier rather than an argument, so it goes *before* whatever you were going to run and prints every privileged command instead of executing it:

```bash
./setup.sh dry-run          # opens the menu, installs nothing
./setup.sh dry-run quick    # shows exactly what quick would do on this machine
CARINO_SETUP_PLAN=technical,purpose=gaming ./setup.sh dry-run   # rehearses a plan before running it for real
```

A rehearsal creates, modifies and deletes nothing: every privileged command and every mutating coreutil (`mkdir`, `rm`, `cp`, `mv`, `ln`, `tar`, `bunzip2`, `chmod`, `tee`, `sed`) is replaced by a `PATH` shim that prints what it would have run, and no log file is written unless you name one. Detection commands — `lspci`, `uname`, `curl`, `grep` — are deliberately left real, so the rehearsal is accurate for *this* machine.

## Environment variables

| Variable | Effect |
| --- | --- |
| `CARINO_SETUP_PLAN` | The unattended plan described above. Setting it makes the whole run non-interactive. |
| `CARINO_SETUP_DRYRUN` | `1` is the environment equivalent of the `dry-run` modifier. |
| `CARINO_SETUP_LOG` | Path of the log file. Default: `carino-setup-YYYYmmdd-HHMMSS.log` in the current directory. A dry run writes no log at all unless this is set. |
| `CARINO_SETUP_OSRELEASE` | Path to read instead of `/etc/os-release`, so you can see what a Debian or an Arch user would get without owning either machine. |

```bash
printf 'NAME="Arch Linux"\n' > /tmp/osr
CARINO_SETUP_OSRELEASE=/tmp/osr ./setup.sh dry-run
```

These four are read by `setup.sh` only. They were introduced the day before this document and were briefly named `SIMPLESETUP_*`; that spelling is gone and has no alias.

## Windows: what `setup.ps1` actually needs

The three scripts are not at parity, and `setup.ps1` is the strictest of them.

- **An elevated PowerShell.** It checks the administrator token first and exits with status 1 if it does not have one. There is no unprivileged mode.
- **`Set-ExecutionPolicy Bypass -Scope Process -Force`**, which the script reminds you about but does not do for you.
- **winget**, from the App Installer package. If it is absent the profile step reports it and returns rather than failing once per package.
- **The same account at the desktop and at the UAC prompt.** It compares the SID of the running process with the owner of `explorer.exe`. If they differ it warns and asks before continuing, because every `HKCU` tweak and every user-scope winget install would land in the elevating account's profile while the desktop you are looking at sees nothing — and has its Explorer restarted anyway.

What it changes: it **writes registry values under `HKCU`** — dark theme, and taskbar items (search box, feeds, task view, widgets, chat, and the "Shortcut" suffix on new shortcuts) depending on whether it took the Windows 10 or the Windows 11 branch. It then **force-kills `explorer.exe`** to reload them. Afterwards it installs the NuGet provider and the `PSWindowsUpdate` module from PSGallery and runs `Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot`, so a full round of Windows Updates is applied; the reboot is left to you.

It offers five profiles — Basic, Gaming, Corporate, FOSS, Personal — as a prompt. Choosing exit, or typing something unrecognised, quits before Windows Update runs.

**It is not localized.** All of its output is English, regardless of the system locale. It takes no arguments, reads no `CARINO_SETUP_PLAN`, and has no dry run.

## macOS: what `macos.sh` actually needs

- **Homebrew**, which it installs from the official installer if it is missing, adding `/opt/homebrew` or `/usr/local` to `PATH` accordingly. It then runs `brew update`. If Homebrew still is not on `PATH` afterwards it exits.
- **No root and no `sudo` of its own.** Only Homebrew's own installer asks for credentials.

It offers four profiles — Basic, Gaming, Corporate, FOSS — and installs one cask or formula at a time so a single bad token cannot abort the rest. Anything that failed is listed at the end and the script exits non-zero, so CI does not read a partial install as a success.

**It is not localized**, takes no arguments, reads no `CARINO_SETUP_PLAN`, and has no dry run.

## Testing

```bash
./test.sh                       # syntax, menu-to-case parity in all 8 languages, and a dry run of every distribution
./test.sh --network             # also verifies every published URL and every Flathub identifier
./tools/check-packages.sh all   # confirms every package name still resolves upstream
```

```powershell
.\test.ps1                      # parses setup.ps1, resolves every cmdlet it calls, and checks the profile menu
```

`test.sh` refuses to pass if a printed menu stops matching the `case` that dispatches it, if a supported distribution stops producing an install command, if an unsupported one produces any command at all, or if an argument is implemented but undocumented here (or documented here but not implemented). `test.ps1` never installs anything and never writes to the registry: it parses `setup.ps1`, checks the profile menu against its `switch`, verifies the build-number gate is compared as a number, asserts the FOSS profile installs nothing proprietary, and asserts every `winget install` carries the unattended flag set. `check-packages.sh` queries the Arch, Fedora, Debian and Flathub indexes directly; it uses `dnf --whatprovides` where a package manager is available, because names such as `wget` and `gnupg` are satisfied through virtual provides rather than by a package of that name.

CI runs `test.sh --network` and `shellcheck -S error` on Linux, and `test.ps1` under both PowerShell 7 and Windows PowerShell 5.1, on every push and pull request. A separate monthly job re-checks every package name and opens an issue when one has gone.

## Known issues
- **Ubuntu derivatives like Pop_OS! have package name conflicts**
- **openSUSE support is still under test**
- **Hyprland and Niri are still being worked on**, the script says so before installing either, and they are installable on the Fedora and Arch families only. `setup.sh` also carries CentOS lists for them, but nothing in EPEL supplies the packages, so on that family they resolve to nothing and are not offered by the plan builder; the same is true of Budgie and Sway there.

### Removed functions (code still available)
- The ProtonGE menu entry was removed from the menus. The `proton` argument still installs it.
- matrox and aspeed gpu drivers

## Licensing

**Mine — GNU Affero General Public License v3.0 or later.** Everything in this
repository *except* the paths listed below. Copyright © 2026 Miguel Carino.
Full terms in [LICENSE](LICENSE).

**Not mine.** The files below are third-party works redistributed here. This
project's licence does not cover them and could not: they are not mine to
relicense. Each keeps its own terms, and each carries its own notice.

| Path | What it is | Licence | Notice |
| --- | --- | --- | --- |
| [`fonts/`](fonts/) | IBM Plex Mono, IBM Plex Sans, Red Hat Display | SIL OFL 1.1 | [`fonts/OFL.txt`](fonts/OFL.txt) |

Those files travel with any fork, mirror or repackaging of this repository, and
their notices must travel with them.
