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
    ("$@") &
    spinner $! "$msg"
}

# Function to check if package is installed
check_package_installed() {
    pacman -Qi "$1" &>/dev/null
}

# Function to install lz4
install_lz4() {
    if ! check_package_installed "lz4"; then
        run_with_spinner "Installing lz4" bash -c '
            pacman -Sy --noconfirm lz4 &>/dev/null
        '
    fi
}

# Function to check current compression settings
check_compression_settings() {
    if grep -q "^COMPRESSION=\"lz4\"" /etc/mkinitcpio.conf && \
       grep -q "^COMPRESSION_OPTIONS=\"-9\"" /etc/mkinitcpio.conf; then
        return 0
    fi
    return 1
}

# Function to backup mkinitcpio.conf
backup_config() {
    run_with_spinner "Creating backup" bash -c '
        cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.backup-$(date +%Y%m%d%H%M%S)
    '
}

# Function to configure compression
configure_compression() {
    run_with_spinner "Configuring initramfs compression" bash -c '
        # Remove any existing compression settings
        sed -i "/^COMPRESSION=/d" /etc/mkinitcpio.conf
        sed -i "/^COMPRESSION_OPTIONS=/d" /etc/mkinitcpio.conf
        
        # Add new compression settings
        echo "COMPRESSION=\"lz4\"" >> /etc/mkinitcpio.conf
        echo "COMPRESSION_OPTIONS=\"-9\"" >> /etc/mkinitcpio.conf
    '
}

# Function to regenerate initramfs
regenerate_initramfs() {
    run_with_spinner "Regenerating initramfs" bash -c '
        mkinitcpio -P &>/dev/null
    '
}

# Function to verify configuration
verify_config() {
    run_with_spinner "Verifying configuration" bash -c "
        errors=0
        
        # Check compression settings
        if ! grep -q '^COMPRESSION=\"lz4\"' /etc/mkinitcpio.conf; then
            echo -e \"${RED}${BOLD}[✗]${NC} COMPRESSION setting not found or incorrect\"
            errors=\$((errors+1))
        fi
        
        if ! grep -q '^COMPRESSION_OPTIONS=\"-9\"' /etc/mkinitcpio.conf; then
            echo -e \"${RED}${BOLD}[✗]${NC} COMPRESSION_OPTIONS setting not found or incorrect\"
            errors=\$((errors+1))
        fi
        
        if [ \"\$errors\" -gt 0 ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Configuration verification failed\"
            exit 1
        fi
    "
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║    Initramfs Compression Setup         ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run as root"
    exit 1
fi

# Check current configuration
if check_compression_settings; then
    echo -e "${YELLOW}${BOLD}[!]${NC} LZ4 compression is already configured"
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to reconfigure it? [y/N] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to configure LZ4 compression for faster initramfs unpacking? [Y/n] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        echo -e "${YELLOW}${BOLD}[!]${NC} Setup cancelled."
        exit 0
    fi
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Setting up initramfs LZ4 compression..."

# Install lz4 if not present
install_lz4

# Backup existing configuration
backup_config

# Configure compression
configure_compression

# Verify configuration
verify_config

# Regenerate initramfs
regenerate_initramfs

echo -e "\n${GREEN}${BOLD}[✓]${NC} Initramfs compression has been configured to use LZ4!"
echo -e "${BLUE}${BOLD}[i]${NC} The changes will take effect on next boot"
echo -e "${YELLOW}${BOLD}[!]${NC} A backup of your original configuration has been created" 
