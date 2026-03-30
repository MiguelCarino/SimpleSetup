#!/bin/bash
# macOS Setup Script
# Run with: bash macos.sh

RED="\e[31m"; BLUE="\e[94m"; GREEN="\e[32m"; YELLOW="\e[33m"; ENDCOLOR="\e[0m"

info()    { echo -e "${BLUE}$1${ENDCOLOR}"; }
error()   { echo -e "${RED}$1${ENDCOLOR}"; }
caution() { echo -e "${YELLOW}$1${ENDCOLOR}"; }
success() { echo -e "${GREEN}$1${ENDCOLOR}"; }

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
        fi
        if command -v brew &>/dev/null; then
            success "Homebrew installed successfully."
        else
            error "Homebrew installation failed. Exiting."
            exit 1
        fi
    fi
    brew update
}

# --- Profile installers ---
install_basic() {
    info "Installing Basic profile packages..."
    brew install --cask \
        google-chrome \
        vlc \
        obs \
        anydesk \
        rustdesk \
        onlyoffice \
        the-unarchiver
    brew install \
        openjdk \
        p7zip
}

install_gaming() {
    info "Installing Gaming profile packages..."
    brew install --cask \
        vlc \
        spotify \
        obs \
        steam \
        rustdesk \
        libreoffice \
        mumble \
        handbrake \
        the-unarchiver
    brew install \
        openjdk \
        p7zip
}

install_corporate() {
    info "Installing Corporate profile packages..."
    brew install --cask \
        webex \
        google-chrome \
        google-drive \
        vlc \
        obs \
        anydesk \
        rustdesk \
        keepassxc \
        onlyoffice \
        forticlient \
        firefox \
        activitywatch \
        handbrake \
        the-unarchiver
    brew install \
        openjdk \
        p7zip
}

install_foss() {
    caution "FOSS profile – still a work in progress."
    info "Installing FOSS profile packages..."
    brew install --cask \
        vlc \
        obs \
        rustdesk \
        telegram \
        libreoffice \
        steam \
        mumble \
        visual-studio-code \
        keepassxc \
        qbittorrent \
        handbrake \
        the-unarchiver
    brew install \
        git \
        python \
        perl \
        openjdk \
        p7zip
}

# --- Main ---
install_homebrew

echo ""
echo "-------------------------------------"
echo " macOS Setup Script"
echo "-------------------------------------"
echo "Now you must choose for a use case profile"
echo "Please select an option:"
echo "1. Basic profile. For the most basic use cases like media playback, internet browsing, office suite, file manipulation, communication and remote assistance."
echo "2. Gaming profile. Is Basic profile plus popular gaming platforms and utilities, like Steam."
echo "3. Corporate profile. Delivers the most packages for office work, videocalls, including applications for specific working ecosystems like Microsoft's, Google's and Cisco's."
echo "4. FOSS profile. Includes ONLY open source alternatives for general use cases. Still on the works."
echo "6. Exit"
echo ""
read -rp "Enter option: " choice

case "$choice" in
    1) install_basic  ;;
    2) install_gaming ;;
    3) install_corporate ;;
    4) install_foss ;;
    6) info "Exiting. Nothing will be installed." ; exit 0 ;;
    *) error "Invalid option. Nothing will be installed." ; exit 1 ;;
esac

success "Finished."
