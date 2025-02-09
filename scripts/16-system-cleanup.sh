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

# Function to clean pacman cache
clean_pacman_cache() {
    run_with_spinner "Cleaning pacman cache" bash -c '
        # Remove all cached versions except latest
        paccache -rk1 &>/dev/null
        # Remove all cached versions of uninstalled packages
        paccache -ruk0 &>/dev/null
        # Clean pacman cache
        yes | pacman -Scc &>/dev/null
    '
}

# Function to clean yay cache
clean_yay_cache() {
    if check_package_installed "yay"; then
        run_with_spinner "Cleaning yay cache" bash -c "
            if command -v yay &>/dev/null; then
                yay -Scc --noconfirm &>/dev/null
            fi
            rm -rf \"${REAL_HOME}/.cache/yay\"
        "
    fi
}

# Function to clean user cache
clean_user_cache() {
    run_with_spinner "Cleaning user cache" bash -c "
        # Clean various cache directories
        find \"${REAL_HOME}/.cache/\" -type f -atime +30 -delete &>/dev/null
        find \"${REAL_HOME}/.local/share/Trash/\" -type f -delete &>/dev/null
        rm -rf \"${REAL_HOME}/.local/share/Trash/*\"
        rm -rf \"${REAL_HOME}/.cache/thumbnails/*\"
    "
}

# Function to clean system temp files
clean_temp_files() {
    run_with_spinner "Cleaning temporary files" bash -c '
        # Clean /tmp
        find /tmp -type f -atime +10 -delete &>/dev/null
        # Clean /var/tmp
        find /var/tmp -type f -atime +10 -delete &>/dev/null
        # Clean systemd journal
        journalctl --vacuum-time=7d &>/dev/null
        # Clean old log files
        find /var/log -type f -name "*.old" -delete &>/dev/null
        find /var/log -type f -name "*.gz" -delete &>/dev/null
    '
}

# Function to clean package orphans
clean_package_orphans() {
    run_with_spinner "Removing orphaned packages" bash -c '
        # Remove orphaned packages
        if [ -n "$(pacman -Qtdq 2>/dev/null)" ]; then
            pacman -Rns $(pacman -Qtdq) --noconfirm &>/dev/null
        fi
    '
}

# Function to clean broken symlinks
clean_broken_symlinks() {
    run_with_spinner "Cleaning broken symlinks" bash -c "
        # Clean broken symlinks in user home
        find \"${REAL_HOME}\" -xtype l -delete &>/dev/null
        # Clean broken symlinks in common directories
        find /usr/lib -xtype l -delete &>/dev/null
        find /usr/bin -xtype l -delete &>/dev/null
    "
}

# Function to clean old config files
clean_old_configs() {
    run_with_spinner "Cleaning old configuration files" bash -c "
        # Clean old config backups
        find \"${REAL_HOME}\" -type f -name \"*.old\" -delete &>/dev/null
        find \"${REAL_HOME}\" -type f -name \"*.bak\" -delete &>/dev/null
        find /etc -type f -name \"*.old\" -delete &>/dev/null
        find /etc -type f -name \"*.bak\" -delete &>/dev/null
    "
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║        System Cleanup Utility          ║${NC}"
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

# Initial prompt
echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to perform a system cleanup? [Y/n] "
read -n 1 -r REPLY
echo
if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Cleanup cancelled."
    exit 1
fi

# Install paccache if not installed
if ! command -v paccache &>/dev/null; then
    run_with_spinner "Installing pacman-contrib" bash -c "pacman -S --noconfirm pacman-contrib &>/dev/null"
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Starting system cleanup..."

# Perform cleanup operations
clean_pacman_cache
clean_yay_cache
clean_user_cache
clean_temp_files
clean_package_orphans
clean_broken_symlinks
clean_old_configs

echo -e "\n${GREEN}${BOLD}[✓]${NC} System cleanup completed!"
echo -e "${YELLOW}${BOLD}[!]${NC} You may want to reboot to ensure all changes take effect" 