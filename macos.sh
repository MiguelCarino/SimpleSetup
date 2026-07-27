#!/bin/bash
# Carino Setup - macOS - https://setup.carino.systems
# Run with: bash macos.sh

RED="\e[31m"; BLUE="\e[94m"; GREEN="\e[32m"; YELLOW="\e[33m"; ENDCOLOR="\e[0m"

info()    { echo -e "${BLUE}$1${ENDCOLOR}"; }
error()   { echo -e "${RED}$1${ENDCOLOR}"; }
caution() { echo -e "${YELLOW}$1${ENDCOLOR}"; }
success() { echo -e "${GREEN}$1${ENDCOLOR}"; }

failedPkgs=""

# --- Homebrew check / install ---
install_homebrew() {
    if command -v brew &>/dev/null; then
        success "Homebrew is already installed: $(brew --version | head -1)"
    else
        caution "Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/homebrew/install/HEAD/install.sh)"
        # Add brew to PATH for Apple Silicon
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"   # Intel Macs keep brew under /usr/local
        fi
        if command -v brew &>/dev/null; then
            success "Homebrew installed successfully."
        else
            error "Homebrew installation failed. Exiting."
            exit 1
        fi
    fi
    brew update || caution "brew update failed. Continuing with the currently cached formulae."
}

brewInstall() {
    local kind="$1"; shift
    local pkg
    for pkg in "$@"; do
        if [[ "$kind" == "cask" ]]; then
            brew install --cask "$pkg" || failedPkgs="$failedPkgs $pkg"   # installed one by one so a bad cask cannot abort the rest
        else
            brew install "$pkg" || failedPkgs="$failedPkgs $pkg"
        fi
    done
}

report() {
    if [[ -n "$failedPkgs" ]]; then
        error "Finished with errors. These packages did not install:$failedPkgs"
        caution "Re-run 'brew install <name>' to see the full Homebrew output for each one."
        exit 1   # non-zero so callers and CI do not read a partial install as a success
    fi
    success "Finished."
}

# --- Profile installers ---
install_basic() {
    info "Installing Basic profile packages..."
    brewInstall cask $caskBasic
    brewInstall formula $formulaBasic
}

install_gaming() {
    info "Installing Gaming profile packages..."
    brewInstall cask $caskGaming
    brewInstall formula $formulaGaming
}

install_corporate() {
    info "Installing Corporate profile packages..."
    brewInstall cask $caskCorporate
    brewInstall formula $formulaCorporate
}

install_foss() {
    info "Installing FOSS profile packages..."
    brewInstall cask $caskFoss
    brewInstall formula $formulaFoss
}

caskBasic="google-chrome vlc obs anydesk rustdesk onlyoffice the-unarchiver"
formulaBasic="openjdk p7zip"

caskGaming="vlc spotify obs steam rustdesk libreoffice mumble handbrake the-unarchiver"
formulaGaming="openjdk p7zip"

caskCorporate="webex google-chrome google-drive vlc obs anydesk rustdesk keepassxc onlyoffice forticlient firefox activitywatch handbrake the-unarchiver"
formulaCorporate="openjdk p7zip"

caskFoss="vlc obs rustdesk telegram libreoffice mumble keepassxc qbittorrent handbrake the-unarchiver"   # steam and visual-studio-code dropped: neither is open source, Steam stays in the Gaming profile
formulaFoss="git python perl openjdk p7zip"   # openjdk here is the GPL OpenJDK build, not Oracle's proprietary JDK

# --- Main ---
install_homebrew

echo ""
echo "-------------------------------------"
echo " Carino Setup - macOS"
echo "-------------------------------------"
echo "Now you must choose for a use case profile"
echo "Please select an option:"
echo "1. Basic profile. For the most basic use cases like media playback, internet browsing, office suite, file manipulation, communication and remote assistance."
echo "2. Gaming profile. Is Basic profile plus popular gaming platforms and utilities, like Steam."
echo "3. Corporate profile. Delivers the most packages for office work, videocalls, including applications for specific working ecosystems like Microsoft's, Google's and Cisco's."
echo "4. FOSS profile. Open source applications only, for general use cases. No Steam and no proprietary browsers here."
echo "5. Exit"
echo ""
read -rp "Enter option: " choice

case "$choice" in
    1) install_basic  ;;
    2) install_gaming ;;
    3) install_corporate ;;
    4) install_foss ;;
    5) info "Exiting. Nothing will be installed." ; exit 0 ;;
    *) error "Invalid option. Nothing will be installed." ; exit 1 ;;
esac

report
