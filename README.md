# Carino Setup

Setup scripts **for Linux, Windows and macOS**, so the user does not have to worry about choices besides their actual use case.

Site: <https://setup.carino.systems>

![Carino Setup](screenshot.webp)

> The GitHub repository is still literally named `SimpleSetup`. Only the owner can rename it, so every `https://github.com/MiguelCarino/SimpleSetup` link is left exactly as it is and keeps working. Renaming the repository is a pending owner action; nothing in this repository depends on it.

## One-liners

```bash
bash <(curl -s https://setup.carino.systems/setup.sh)      # Linux
```

```powershell
iwr -useb https://setup.carino.systems/setup.ps1 | iex     # Windows 10 and 11, elevated PowerShell
```

```bash
bash <(curl -s https://setup.carino.systems/macos.sh)      # macOS, Homebrew, Apple Silicon and Intel
```

The rest of this page is about `setup.sh`: one plain bash file in 14 numbered sections (0–13). All the package names are kept together in section 4 as arrays named `<group>_<family>`. `setup.ps1` (Windows) and `macos.sh` (macOS) are separate and simpler. They take no arguments and have no plan and no dry run.

## What it does, in order

Run it as your normal user. It runs each command that changes the system through `sudo`, `doas` or `run0`, prints the command first, and puts user files in the home of the real user (`SUDO_USER` when started with sudo).

1. **Check the system.** It reads `/etc/os-release` and finds the family from `ID`, then from `ID_LIKE`. It then prints a table: distribution, family, package manager, kernel, architecture, CPU, every GPU (with the NVIDIA generation), laptop, virtual machine, Secure Boot, atomic, desktop session, free disk, internet, and which user the files are for. It refuses NixOS (and prints a `configuration.nix` snippet instead), SteamOS, transactional openSUSE (MicroOS, Aeon, Kalpa), any distribution it does not recognise, and a machine with no root and no `sudo`/`doas`/`run0`. When it refuses, nothing has run.
2. **Base setup and drivers** (asks, default yes):
   - adds the repositories that codecs and drivers need
   - upgrades the whole system
   - installs the base packages, codecs, firmware and CPU microcode (no firmware or microcode in a VM)
   - installs Flatpak and adds Flathub
   - installs the GPU drivers:
     - **NVIDIA** asks first. Turing and newer get the open module, Maxwell and Pascal the 580 branch, and Kepler the 470 branch where the family packages it. With Secure Boot on, it prints the MOK enrolment steps first.
     - **AMD and Intel** get Mesa, Vulkan and VA-API.
     - **In a VM**, it installs guest tools instead.
3. **Desktop.** The menu appears only when no desktop session or display manager is found. It lists the 12 desktops, `none` and Carino Hyprland, and the default is `none`.
4. **Purpose profiles.** It lists the 15 purposes and accepts several numbers (`2 6`). Each profile installs the basic applications, its own native list where the family has one, and its Flatpaks.
5. **Carino Hyprland.** It asks *"Install the Carino Hyprland desktop configuration?"* (default no). It asks only where Hyprland 0.55 or newer can be installed. Everywhere else it prints one line saying why not.
6. **Summary.** It shows what was done, skipped or failed, then asks whether to reboot (default no).

A failed package never stops the run. Names the package manager cannot find are listed and skipped. If a batch fails, each package is retried on its own.

## Supported distributions

| Family | Examples | Base | Drivers | Profiles (native lists) | Carino Hyprland |
| --- | --- | --- | --- | --- | --- |
| Fedora | Fedora, Nobara, Ultramarine, Risi | RPM Fusion, OpenH264, full ffmpeg | NVIDIA open / 580xx / 470xx (akmods), AMD, Intel | all | yes, COPR `lionheartp/Hyprland` |
| Fedora Atomic | Silverblue, Kinoite, Bazzite, Bluefin, Aurora | a few tools, layered with `rpm-ostree` (reboot) | NVIDIA layered (Universal Blue images: rebase to `-nvidia`); Mesa comes with the image | Flatpaks only | no |
| Enterprise Linux | RHEL, AlmaLinux, Rocky, CentOS Stream, Oracle, Amazon | CRB, EPEL, RPM Fusion free (Oracle: its own EPEL and CodeReady repositories; Amazon: none) | NVIDIA Turing+ (AlmaLinux repository; others get instructions), AMD, Intel | Fedora lists, missing names skipped | no |
| Debian | Debian, LMDE, MX, Kali, Parrot, Devuan, Raspberry Pi OS | contrib + non-free | NVIDIA open / 580, AMD, Intel | all | Debian 13 (backports), forky, sid, and derivatives that name one of them in `DEBIAN_CODENAME` (LMDE 7) |
| Ubuntu | Ubuntu, Mint, Pop!_OS, elementary, Zorin, KDE neon, TUXEDO | universe, multiverse, restricted | `ubuntu-drivers` (Pop!_OS: `system76-driver-nvidia`), AMD, Intel | Debian lists | 24.04 and 26.04 bases, derivatives included (PPA `cppiber/hyprland`); Ubuntu 26.10+ itself |
| Arch | Arch, Manjaro, EndeavourOS, CachyOS, Garuda | asks to enable `[multilib]` | NVIDIA Turing+ (older: AUR, says so), AMD, Intel | all | yes |
| openSUSE | Tumbleweed, Slowroll, Leap, SLES | asks to add Packman (openSUSE only, not SLES) | NVIDIA G07 / G06 from NVIDIA's repository (openSUSE only), AMD, Intel | basic, gaming, corporate, development | Tumbleweed, Slowroll |
| Solus | Solus | short base list | NVIDIA (current driver) | Flatpaks only | yes |
| Alpine | Alpine, postmarketOS | community repository | AMD, Intel (no NVIDIA on musl) | basic, development | no (ships 0.54) |
| Void | Void, glibc and musl | nonfree (+ multilib) | NVIDIA Turing+ on glibc, AMD, Intel | basic | no |
| Gentoo | Gentoo, Funtoo | base packages only | printed steps (USE flags) | Flatpaks only | no (steps printed) |
| Mageia | Mageia, OpenMandriva | nonfree + tainted on Mageia (OpenMandriva: enable non-free in `om-repo-picker`) | NVIDIA via the Control Center | Flatpaks only | no |
| *refused* | NixOS, SteamOS, MicroOS / Aeon / Kalpa, anything unknown | — | — | — | — |

"All" means every purpose that has a list of its own: 13 of the 15. Corporate (Microsoft only) and Corporate (Google only) install the basic applications plus Flatpaks on every family. The desktops have package lists on Fedora, Arch and openSUSE (all 12), Debian and Ubuntu (all but Niri), EL (GNOME, XFCE, KDE, LXQt, Cinnamon, MATE) and Solus (Hyprland); Mageia has none. The [plan builder](https://setup.carino.systems) shows the exact packages for each family and profile.

## Arguments

```bash
bash <(curl -s https://setup.carino.systems/setup.sh) <argument>
./setup.sh <argument>
```

| Argument | What it does |
| --- | --- |
| *(none)* | Interactive: the six steps above |
| `quick` | Base setup, then the Basic profile's native apps and the basic and Google Flatpaks |
| `simple` | Base setup only (repositories, upgrade, base packages, codecs, firmware, drivers) |
| `server` | Base, server and development packages, then enables SSH and Cockpit and opens them in firewalld |
| `drivers`, `nvidia`, `amd`, `intel` | GPU drivers only, after the repositories they need. All four are the same, because the GPU is detected |
| `desktop` | The desktop menu, even when a desktop is already running |
| `hyprland` | Carino Hyprland only |
| `distrobox` | Fedora, Ubuntu and Debian distrobox containers |
| `anydesk` | AnyDesk and RustDesk Flatpaks |
| `librewolf` | LibreWolf: repository on Fedora/EL/Debian/Ubuntu, Flatpak elsewhere |
| `share` | Asks first, then mounts a Windows (SMB) shared folder at `~/WinFiles` |
| `proton` | The latest GE-Proton into Steam's `compatibilitytools.d` (Flatpak Steam too) |
| `update` | Refreshes and upgrades packages and Flatpaks |
| `help` | Prints the usage text |

Any other argument, or more than one argument after `dry-run`, prints the usage text and exits with status 2.

### Unattended: `CARINO_SETUP_PLAN`

```bash
CARINO_SETUP_PLAN=technical,desktop=carino-hyprland,purpose=gaming,purpose=development bash <(curl -s https://setup.carino.systems/setup.sh)
```

The tokens are comma-separated and run left to right:

| Token | What it does |
| --- | --- |
| `technical` | Base setup (including drivers), then the desktop menu, which takes `none` |
| `drivers`, `update`, `server` | Same as the arguments |
| `desktop=<name>` | `gnome` `xfce` `kde` `lxqt` `cinnamon` `mate` `i3` `openbox` `budgie` `sway` `hyprland` `niri` `carino-hyprland` `none` |
| `hyprland` | Same as `desktop=carino-hyprland`. (`desktop=hyprland` installs plain Hyprland, without the Carino configuration.) |
| `purpose=<name>` | `basic` `gaming` `corporate` `corporate-microsoft` `corporate-google` `development` `astronomy` `compneuro` `design` `music` `cybersecurity` `forensics` `scientific` `robotics` `imagenology` (may repeat) |
| `reboot=yes` / `reboot=no` | Reboot at the end or not. Without it, the final prompt takes its default, no |

All tokens are checked before anything runs. If one token is unknown, the plan has no action (only `reboot=`), or a plan is combined with an argument, the whole run is refused with status 2. Under a plan, or when stdin is not a terminal, every question takes its default and says so:

| Question | Default |
| --- | --- |
| Base setup / NVIDIA driver / `[multilib]` / Packman | yes |
| Desktop menu (interactive flow, or after `technical`) | 13 (`none`) |
| Purpose profiles (interactive flow without a terminal) | 1 (Basic) |
| Distrobox containers after Development, SSH + Cockpit after `server` | yes |
| Carino Hyprland, Windows share, reboot | no |

## Dry run

```bash
./setup.sh dry-run                 # or --dry-run, or CARINO_SETUP_DRYRUN=1
./setup.sh dry-run quick
CARINO_SETUP_PLAN=technical,purpose=gaming ./setup.sh dry-run
```

Every command that changes the system goes through one function, `run`. In a dry run, `run` prints the command as `(dry-run) $ ...` and does not run it. File writes are printed with their content. Detection still runs for real (`lspci`, `/sys`, `df`, and `curl -sI https://flathub.org`), so the plan matches this machine. To make no network request, set `CARINO_SETUP_NET=0`.

## Logs

Each run writes `carino-setup-YYYYmmdd-HHMMSS.log` in the current directory, with colours stripped. If that directory is not writable, the log goes to `/tmp`. `CARINO_SETUP_LOG=<file>` picks the path. A dry run writes no log unless `CARINO_SETUP_LOG` is set.

| Variable | Effect |
| --- | --- |
| `CARINO_SETUP_PLAN` | The unattended plan above |
| `CARINO_SETUP_DRYRUN=1` | Same as `dry-run` |
| `CARINO_SETUP_LOG=<file>` | Log path |
| `CARINO_SETUP_OSRELEASE=<file>` | Read this instead of `/etc/os-release`, to see what another distribution would get |
| `CARINO_SETUP_ATOMIC`, `_GPU`, `_NVGEN`, `_VIRT`, `_NET` | Test hooks: force atomic, the GPU list (`"nvidia amd intel"`), the NVIDIA branch (`open`, `580`, `470`) or the VM type; `_NET=0` skips the internet check |

## Carino Hyprland

Carino Hyprland is a complete Hyprland desktop: an ALT-based keymap, a waybar bar, a lock screen, idle handling, notifications, a launcher, clipboard history, screenshots, fonts and a wallpaper. It needs Hyprland **0.55 or newer**, because the configuration is `hyprland.lua`. Use the `hyprland` argument, the `desktop=carino-hyprland` (or `hyprland`) plan token, the desktop menu, or answer yes at the end of the interactive run. Steps:

1. Adds the Hyprland source where one is needed (COPR on Fedora, `trixie-backports` on Debian 13, the PPA on Ubuntu 24.04/26.04 bases).
2. Installs the `hypr_<family>` packages, then checks that `Hyprland --version` is at least 0.55.
3. Finds the bundle: [`hyprland/`](hyprland/) next to the script, or downloaded from this repository.
4. Moves any existing `~/.config` folder that the bundle also ships (`hypr`, `waybar`, `wofi`, `mako`, `kitty`, `cliphist`, `themes`) to `~/.config/carino-backup-<timestamp>/`.
5. Copies the bundle into your home folder, creates `~/Pictures/Screenshots`, runs `fc-cache -f` and prints the main keys.

Then log out and choose Hyprland at the login screen. The script does not install a login manager for it: with none, type `Hyprland` on a text console after logging in. To undo, move the folders back from the backup folder. Keys, contents and requirements are in [hyprland/README.md](hyprland/README.md).

## Tests

```bash
./test.sh                          # syntax, shellcheck, every distribution fixture, plans, purposes, desktops, arguments, package tables
./test.sh --network                # also asks Flathub about every Flatpak id
./tools/check-packages.sh cheap    # array coverage, Flathub ids, Arch repositories (HTTP only)
./tools/check-packages.sh containers   # resolves every name in Fedora, Debian, Ubuntu, openSUSE, AlmaLinux and Alpine containers
```

```powershell
.\test.ps1                         # parses setup.ps1 and checks its profile menu
```

`test.sh` runs `setup.sh` only as a dry run, against twenty `os-release` fixtures. CI (`checks.yml`) runs `test.sh --network`, the coverage check and `shellcheck -S warning` on every push and pull request, and runs `test.ps1` under PowerShell 7 and 5.1. `packages.yml` runs the cheap package check when a package list changes. Each month it runs the container check and opens an issue if a name has gone.

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
| [`hyprland/.local/share/fonts/carino/`](hyprland/.local/share/fonts/carino/) | Orbitron, Rajdhani SemiBold, Share Tech Mono | SIL OFL 1.1 | `OFL-Orbitron.txt`, `OFL-Rajdhani.txt`, `OFL-ShareTechMono.txt` (beside the fonts) |

Those files travel with any fork, mirror or repackaging of this repository, and
their notices must travel with them.
