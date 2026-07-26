# SimpleSetup
*Simple setup* scripts (not short though) **for Linux, Windows and macOS systems**. So the user doesn't need to worry about choices besides their actual use case.

**Systems supported:**

**Linux** (families as matched by `identifyDistro` in `setup.sh`):
- **Debian** family — Debian, Ubuntu (and the Ubuntu flavours, which all report `NAME=Ubuntu`), Pop!_OS, Linux Mint, LMDE, Zorin, elementary, Kali, Parrot, Devuan, Raspbian / Raspberry Pi OS, MX, antiX, Deepin, KDE neon, Trisquel, PureOS, TUXEDO, PikaOS, Armbian, SparkyLinux, Q4OS. Package manager `apt`.
- **Fedora** family — Fedora, Nobara, Risi, Ultramarine, plus the atomic/image-based variants Silverblue, Kinoite, Sericea, Onyx, Bazzite, Bluefin, Aurora and Universal Blue. Package manager `dnf`, and `rpm-ostree` is used automatically wherever it is present.
- **Red Hat Enterprise Linux** — package manager `dnf`, with the extra RHEL package set.
- **CentOS** family, i.e. CentOS Stream and the RHEL rebuilds — Rocky, AlmaLinux, Oracle Linux, EuroLinux, Circle Linux, Springdale, Anolis, OpenCloudOS, TencentOS, Alibaba Cloud Linux, CloudLinux. Package manager `dnf`.
- **Amazon Linux** — package manager `dnf`, but **headless only**: it carries no EPEL, no CRB and no desktop groups, so only the essential and server paths run. The script cautions you about this on detection.
- **Arch** family — Arch, Manjaro, EndeavourOS, Garuda, CachyOS, ArcoLinux, RebornOS, Archcraft. Package manager `pacman` with `--noconfirm --needed`; the package lists are replaced with Arch-specific ones rather than appended, and all the desktop environments are available.
- **openSUSE** Leap and Tumbleweed, plus SUSE/SLES/SLED — package manager `zypper`. **Still being tested**, the script says so when it detects you.

**Deliberately not supported.** The script detects these, prints a reason and stops rather than guessing: SteamOS/Holo, Artix, Parabola, Gentoo, Slackware, NixOS, Guix System, Alpine, Void, Clear Linux, Solus, Qubes, Mageia, OpenMandriva, Chimera, and the transactional openSUSE variants (MicroOS, Aeon, Kalpa, Leap Micro, SLE Micro, SL Micro). Each refusal explains what specifically does not map — read-only images, a non-systemd init, a declarative configuration, musl libc, no dependency resolution, and so on.

Anything not matched at all falls to the default arm, which reports the distribution and version it actually read from `/etc/os-release` and notes that no package manager, package family or flags were configured, so every install would be a no-op.

Just open your Terminal and paste
```bash
bash <(curl -s https://setup.carino.systems/setup.sh)
```

**Windows**:
- **Windows 10**
- **Windows 11**

Just open **Terminal** and paste
```powershell
iwr -useb https://setup.carino.systems/setup.ps1 | iex
```

**macOS**:
- Homebrew-based, four use-case profiles. Tested on Apple Silicon and Intel.

Just open **Terminal** and paste
```bash
bash <(curl -s https://setup.carino.systems/macos.sh)
```

## Main Features
- **Automatic distro identification**.
- **Quick setup**: Install and forget.
- **Technical Setup**: Installs necessary packages for a decent hardware experience and basic user features (e.g., Nvidia drivers, Rocm/Hip, non-free repos, Flathub, Desktop Environment if missing, dark theme, dot files, etc).
- **Purpose Setup**: 14 purposes — Basic, Gaming, Corporate, Corporate (Microsoft only), Corporate (Google only), Development, Astronomy, Computational Neuroscience, Design, Music Production, Cybersecurity, Forensics, Scientific, Robotics.
- **Menu options**: Technical Setup, Purpose Setup, install a Desktop Environment, install graphic drivers, update the system, server setup, exit.
- **Desktop Environments**: GNOME, XFCE, KDE, LXQt, Cinnamon, MATE, i3, Openbox, Budgie, Sway, Hyprland, Niri, or none.
- **Argument support**
- **Multilingual menus**: English, Japanese, Russian, Spanish, Finnish, Chinese, Korean, Hebrew, with automatic locale detection. Any other locale falls back to English.

## Arguments
*All arguments are passed straight to the script*\
bash <(curl -s https://setup.carino.systems/setup.sh) **argument**\
./setup.sh **argument**

Running it with no argument, or with an unrecognised one, opens the interactive menu.

### General Arguments
- quick\
  Runs the Technical Setup, then installs the basic user, basic system and support packages plus the basic and Google flatpaks.

- simple\
  Runs the Technical Setup only.

- server\
  Configures a minimal server setup with essential development packages. This does not include the full Technical Setup.

### Graphics Driver Installation
- nvidia\
  Installs Nvidia graphic drivers.

- amd\
  Installs AMD graphic drivers.

- intel\
  Installs Intel graphic drivers.

### Special Programs
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

### System and Storage
- share\
  Prompts for a server, share and user, then mounts a Windows/CIFS share at `~/WinFiles`.

### Desktop Environment Setup
- desktop\
  Opens a menu to select and install a Desktop Environment from a curated list.

**Note:** updating the system is menu option 5, not an argument. There is no `update` argument in `setup.sh`.

## Known Issues
- **Ubuntu derivatives like Pop_OS! have package name conflicts**
- **openSUSE support is still under test**

### Removed functions (code still available)
- The ProtonGE menu entry was removed from the menus. The `proton` argument still installs it.
- matrox and aspeed gpu drivers

## License

Licensed under the **GNU Affero General Public License v3.0 or later** (AGPL-3.0-or-later) — see [LICENSE](LICENSE). Copyright © 2026 Miguel Carino.
