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

# Function to check if systemd-oomd is already enabled
check_oomd_status() {
    systemctl is-enabled systemd-oomd &>/dev/null
}

# Function to enable and start systemd-oomd
enable_oomd() {
    run_with_spinner "Enabling and starting systemd-oomd" bash -c '
        systemctl enable --now systemd-oomd &>/dev/null
    '
}

# Function to verify systemd-oomd is running
verify_oomd() {
    local status
    status=$(systemctl is-active systemd-oomd)
    
    if [ "$status" != "active" ]; then
        echo -e "${RED}${BOLD}[✗]${NC} systemd-oomd is not running (status: $status)"
        return 1
    fi
    
    echo -e "${GREEN}${BOLD}[✓]${NC} systemd-oomd is running"
    return 0
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║        systemd-oomd Setup              ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run as root"
    exit 1
fi

# Check current status
if check_oomd_status; then
    echo -ne "${YELLOW}${BOLD}[!]${NC} systemd-oomd is already enabled. Would you like to reconfigure it? [y/N] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to enable systemd-oomd for better memory management? [Y/n] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        echo -e "${YELLOW}${BOLD}[!]${NC} Setup cancelled."
        exit 0
    fi
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Setting up systemd-oomd..."

# Enable and start systemd-oomd
enable_oomd

# Wait a moment for the service to start
sleep 2

# Verify setup
if ! verify_oomd; then
    echo -e "${RED}${BOLD}[✗]${NC} Failed to configure systemd-oomd"
    echo -e "${YELLOW}${BOLD}[!]${NC} Please check the service status with: systemctl status systemd-oomd"
    exit 1
fi

echo -e "\n${GREEN}${BOLD}[✓]${NC} systemd-oomd has been configured!"
echo -e "${BLUE}${BOLD}[i]${NC} The service is now running and will start automatically on boot"
echo -e "${YELLOW}${BOLD}[!]${NC} You can check the service status with: systemctl status systemd-oomd" 