#!/bin/bash

# Colors and styling
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

# Spinner function for visual feedback
spinner() {
    local pid=$1
    local msg="$2"
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    tput civis  # Hide cursor
    while kill -0 $pid 2>/dev/null; do
        for i in $(seq 0 9); do
            printf "\r${BLUE}${BOLD}[${spinstr:$i:1}]${NC} ${msg}   "
            sleep 0.1
        done
    done
    wait $pid
    local exit_status=$?
    if [ $exit_status -eq 0 ]; then
        printf "\r${GREEN}${BOLD}[✓]${NC} ${msg}\n"
    else
        printf "\r${RED}${BOLD}[✗]${NC} ${msg}\n"
        exit $exit_status
    fi
    tput cnorm  # Show cursor
}

# Function to run command with spinner
run_with_spinner() {
    local msg="$1"
    shift
    ("$@" > /dev/null 2>&1) &
    spinner $! "$msg"
}

# Function to show info
info() {
    echo -e "${BLUE}${BOLD}[i]${NC} $1"
}

# Function to show success
success() {
    echo -e "${GREEN}${BOLD}[✓]${NC} $1"
}

# Function to show warning
warning() {
    echo -e "${YELLOW}${BOLD}[!]${NC} $1"
}

# Function to show error and exit
error() {
    echo -e "${RED}${BOLD}[✗]${NC} $1"
    exit 1
}

# Check if root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
fi

# Get real user
REAL_USER="${SUDO_USER:-$(logname)}"
[ -z "$REAL_USER" ] && error "Could not determine the real user"

# Clear screen and show header
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║         YAY AUR Helper Setup           ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}\n"

# Check installation status and prompt
YAY_INSTALLED=$(pacman -Qi yay &>/dev/null && echo 1 || echo 0)
if [ "$YAY_INSTALLED" = "1" ]; then
    info "Found existing Yay installation"
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to reinstall? [y/N]: "
    read -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && warning "Operation cancelled by user" && exit 0
    info "Starting clean reinstallation..."
else
    info "No existing Yay installation found"
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to install Yay? [Y/n]: "
    read -n 1 -r
    echo
    [[ $REPLY =~ ^[Nn]$ ]] && warning "Operation cancelled by user" && exit 0
    info "Starting installation..."
fi

# Check for existing chaotic-aur
CHAOTIC_INSTALLED=0
if pacman -Qi chaotic-keyring &>/dev/null; then
    CHAOTIC_INSTALLED=1
    info "Found existing chaotic-aur installation"
else
    # Add chaotic-aur repo
    run_with_spinner "Adding chaotic-aur key" pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    run_with_spinner "Signing chaotic-aur key" pacman-key --lsign-key 3056513887B78AEB
    run_with_spinner "Installing chaotic-aur packages" pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

    # Add repo to pacman.conf if not already there
    if ! grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
        run_with_spinner "Configuring repository" bash -c 'echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >> /etc/pacman.conf'
    fi
fi

# Install yay
run_with_spinner "Installing Yay" pacman -Sy --noconfirm yay

# Cleanup chaotic-aur if we installed it
if [ "$CHAOTIC_INSTALLED" = "0" ]; then
    run_with_spinner "Removing chaotic-aur repository" bash -c '
        sed -i "/\[chaotic-aur\]/,+1d" /etc/pacman.conf
        pacman -Rns --noconfirm chaotic-keyring chaotic-mirrorlist
        rm -f /etc/pacman.d/chaotic-mirrorlist
        pacman-key --delete 3056513887B78AEB
        rm -rf /etc/pacman.d/gnupg/openpgp-revocs.d/3056513887B78AEB.rev
        rm -rf /etc/pacman.d/gnupg/private-keys-v1.d/3056513887B78AEB.key
        rm -f /var/cache/pacman/pkg/chaotic-*
    '
fi

# Configure yay
run_with_spinner "Configuring Yay" bash -c '
    mkdir -p "/home/$REAL_USER/.config/yay"
    cat > "/home/$REAL_USER/.config/yay/config.json" << EOF
{
    "cleanafter": true,
    "sudoloop": true,
    "sudoflags": "-S",
    "redownload": false,
    "noredownload": true,
    "batchinstall": true,
    "combinedupgrade": true,
    "useask": false
}
EOF
    chown -R "$REAL_USER:$(id -gn $REAL_USER)" "/home/$REAL_USER/.config/yay"
'

echo
success "Yay has been installed successfully!"
info "You can now use yay to install packages from the AUR"
warning "Example usage: yay -S package-name"
echo
