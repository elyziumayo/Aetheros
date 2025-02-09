#!/bin/bash

# Colors and styling
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

# Package categories
DEVELOPMENT_PKGS=(
    "git"           # Version control system
    "base-devel"    # Development tools
)

SYSTEM_PKGS=(
    "fastfetch"     # System information
    "kitty"         # Terminal emulator
    "waybar"        # Status bar
    "swaync"        # Notification daemon
    "rofi-wayland"  # Application launcher
    "otf-font-awesome"  # Icon font
    "ttf-jetbrains-mono-nerd"  # Nerd font
    "ttf-jetbrains-mono"       # Monospace font
    "brightnessctl" # Brightness control
    "xarchiver"     # Archive manager
    "zsh"           # Shell
    "fzf"           # Fuzzy finder
    "zoxide"        # Smarter cd command
    "gnu-free-fonts"
    "eza"           # Modern ls replacement
)

FILE_MANAGER_PKGS=(
    "thunar"
    "thunar-volman"
    "thunar-archive-plugin"
    "thunar-media-tags-plugin"
    "gvfs"
    "gvfs-mtp"
    "tumbler"
    "ffmpegthumbnailer"
    "catfish"
    "mat2"
    "perl-image-exiftool"
)

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

# Function to install packages
install_packages() {
    local pkgs=("$@")
    local to_install=()
    local installed=()
    
    # Check which packages need to be installed
    for pkg in "${pkgs[@]}"; do
        if ! check_package_installed "$pkg"; then
            to_install+=("$pkg")
        else
            installed+=("$pkg")
        fi
    done
    
    # Show already installed packages
    if [ ${#installed[@]} -gt 0 ]; then
        echo -e "\n${BLUE}${BOLD}[i]${NC} Already installed packages:"
        for pkg in "${installed[@]}"; do
            echo -e "   ${GREEN}${BOLD}[✓]${NC} $pkg"
        done
    fi
    
    # Install missing packages
    if [ ${#to_install[@]} -gt 0 ]; then
        echo -e "\n${BLUE}${BOLD}[i]${NC} Packages to install:"
        for pkg in "${to_install[@]}"; do
            echo -e "   ${YELLOW}${BOLD}[!]${NC} $pkg"
        done
        
        echo -ne "\n${BLUE}${BOLD}[?]${NC} Would you like to install these packages? [Y/n] "
        read -n 1 -r REPLY
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
            return 1
        fi
        
        run_with_spinner "Installing packages" bash -c "pacman -S --noconfirm --needed ${to_install[*]} &>/dev/null"
        return 0
    fi
    
    return 0
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║        Package Installation            ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run with sudo"
    exit 1
fi

# Update package database
run_with_spinner "Updating package database" bash -c "pacman -Sy &>/dev/null"

# Install packages by category
echo -e "\n${BLUE}${BOLD}[i]${NC} Development Packages"
install_packages "${DEVELOPMENT_PKGS[@]}"

echo -e "\n${BLUE}${BOLD}[i]${NC} System Packages"
install_packages "${SYSTEM_PKGS[@]}"

echo -e "\n${BLUE}${BOLD}[i]${NC} File Manager Packages"
install_packages "${FILE_MANAGER_PKGS[@]}"

echo -e "\n${GREEN}${BOLD}[✓]${NC} Package installation completed!"
echo -e "${YELLOW}${BOLD}[!]${NC} Some changes may require a system restart to take effect" 
