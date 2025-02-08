#!/bin/bash

# Colors and styling
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

# Get real user's home directory
REAL_HOME=$(eval echo ~${SUDO_USER})
BUILD_DIR="${REAL_HOME}/.cache/yay-build"

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
    ("$@") &
    spinner $! "$msg"
}

# Function to check if package is installed
check_package_installed() {
    pacman -Qi "$1" &>/dev/null
}

# Function to install base dependencies
install_dependencies() {
    run_with_spinner "Installing base dependencies" bash -c '
        pacman -Sy --noconfirm --needed git base-devel &>/dev/null
    '
}

# Function to clean up build directory
cleanup_build() {
    run_with_spinner "Cleaning up build directory" bash -c "
        rm -rf \"${BUILD_DIR}\"
    "
}

# Function to build and install yay
install_yay() {
    # Create build directory and set permissions
    run_with_spinner "Preparing build environment" bash -c "
        mkdir -p \"${BUILD_DIR}\"
        chown -R ${SUDO_USER}:$(id -gn ${SUDO_USER}) \"${BUILD_DIR}\"
    "

    # Clone yay repository
    run_with_spinner "Cloning yay repository" bash -c "
        cd \"${BUILD_DIR}\" && sudo -u ${SUDO_USER} git clone https://aur.archlinux.org/yay.git &>/dev/null
    "

    # Build and install yay
    echo -e "${BLUE}${BOLD}[i]${NC} Building yay package..."
    
    # Create a temporary sudoers file for makepkg
    echo "${SUDO_USER} ALL=(ALL) NOPASSWD: /usr/bin/pacman" > /etc/sudoers.d/yay-temp
    
    # Build and install as the user
    if ! sudo -u ${SUDO_USER} bash -c "cd \"${BUILD_DIR}/yay\" && makepkg -si --noconfirm" &>/dev/null; then
        rm -f /etc/sudoers.d/yay-temp
        echo -e "${RED}${BOLD}[✗]${NC} Build failed"
        exit 1
    fi
    
    # Remove temporary sudoers file
    rm -f /etc/sudoers.d/yay-temp
    
    echo -e "${GREEN}${BOLD}[✓]${NC} Build completed successfully"
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║         YAY AUR Helper Setup           ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run with sudo"
    exit 1
fi

# Check if SUDO_USER is set
if [ -z "$SUDO_USER" ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run with sudo, not as root directly"
    exit 1
fi

# Check for existing yay installation
if check_package_installed "yay"; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Yay is already installed on your system"
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to reinstall it? [y/N] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to install Yay AUR helper? [Y/n] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        echo -e "${YELLOW}${BOLD}[!]${NC} Installation cancelled."
        exit 0
    fi
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Setting up Yay..."

# Clean up any existing build directory
cleanup_build

# Install dependencies
install_dependencies

# Install yay
install_yay

# Final cleanup
cleanup_build

echo -e "\n${GREEN}${BOLD}[✓]${NC} Yay has been installed successfully!"
echo -e "${BLUE}${BOLD}[i]${NC} You can now use yay to install packages from the AUR"
echo -e "${YELLOW}${BOLD}[!]${NC} Example usage: yay -S package-name" 
