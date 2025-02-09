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
            printf "\r${BLUE}${BOLD}[${spinstr:$i:1}]${NC} ${msg}"
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
    {
        "$@"
    } >/dev/null 2>&1 &
    spinner $! "$msg"
}

# Ensure we have sudo privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run with sudo"
    exit 1
fi

# Get real user
REAL_USER="$SUDO_USER"
if [ -z "$REAL_USER" ]; then
    echo -e "${RED}${BOLD}[✗]${NC} Could not determine the real user"
    exit 1
fi

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║         YAY AUR Helper Setup           ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}\n"

# Check if yay is already installed first
if pacman -Qi yay &>/dev/null; then
    echo -e "${BLUE}${BOLD}[i]${NC} This script will reinstall the Yay AUR helper."
else
    echo -e "${BLUE}${BOLD}[i]${NC} This script will install the Yay AUR helper."
fi

echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to proceed? [y/N] "
read -n 1 -r REPLY
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Operation cancelled by user"
    exit 0
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Setting up Yay AUR helper..."

# Check if yay is already installed
if pacman -Qi yay &>/dev/null; then
    run_with_spinner "Removing existing installation" \
        pacman -Rns --noconfirm yay
fi

run_with_spinner "Installing dependencies" \
    pacman -Sy --noconfirm --needed git base-devel

# Prepare build directory
BUILD_DIR="/tmp/yay-build"
run_with_spinner "Preparing build environment" \
    bash -c "rm -rf '$BUILD_DIR' && mkdir -p '$BUILD_DIR' && chown '$REAL_USER:$(id -gn $REAL_USER)' '$BUILD_DIR'"

# Clone and build
cd "$BUILD_DIR" || exit 1
run_with_spinner "Cloning Yay repository" \
    sudo -u "$REAL_USER" git clone --quiet https://aur.archlinux.org/yay.git .

run_with_spinner "Building Yay package" \
    sudo -u "$REAL_USER" makepkg -s --noconfirm

run_with_spinner "Installing Yay" \
    pacman -U --noconfirm yay-*.pkg.tar.zst

run_with_spinner "Cleaning up" \
    rm -rf "$BUILD_DIR"

# Verify and finish
if pacman -Qi yay &>/dev/null; then
    echo -e "\n${GREEN}${BOLD}[✓]${NC} Yay has been installed successfully!"
    echo -e "${BLUE}${BOLD}[i]${NC} You can now use yay to install packages from the AUR"
    echo -e "${YELLOW}${BOLD}[!]${NC} Example usage: yay -S package-name\n"
else
    echo -e "\n${RED}${BOLD}[✗]${NC} Installation verification failed\n"
    exit 1
fi
