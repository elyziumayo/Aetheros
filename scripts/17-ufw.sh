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

# Function to install UFW
install_ufw() {
    run_with_spinner "Installing UFW" bash -c '
        pacman -Sy --noconfirm ufw &>/dev/null
    '
}

# Function to configure UFW rules
configure_ufw() {
    run_with_spinner "Configuring UFW rules" bash -c '
        # Reset UFW to default state
        ufw --force reset &>/dev/null

        # Configure default policies
        ufw default deny incoming &>/dev/null
        ufw default allow outgoing &>/dev/null

        # Configure specific rules
        ufw limit 22/tcp &>/dev/null  # SSH with rate limiting
        ufw allow 80/tcp &>/dev/null  # HTTP
        ufw allow 443/tcp &>/dev/null # HTTPS
    '
}

# Function to enable UFW
enable_ufw() {
    run_with_spinner "Enabling UFW" bash -c '
        # Enable and start UFW service
        systemctl enable ufw &>/dev/null
        systemctl start ufw &>/dev/null
        
        # Enable UFW
        ufw --force enable &>/dev/null
        
        # Wait for service to fully start
        sleep 2
    '
}

# Function to verify UFW status
verify_ufw() {
    run_with_spinner "Verifying UFW configuration" bash -c "
        errors=0
        
        # Check if UFW is installed
        if ! command -v ufw &>/dev/null; then
            echo -e \"${RED}${BOLD}[✗]${NC} UFW is not installed\"
            errors=\$((errors+1))
        fi
        
        # Check if UFW is active
        if ! systemctl is-active ufw &>/dev/null; then
            echo -e \"${RED}${BOLD}[✗]${NC} UFW service is not active\"
            errors=\$((errors+1))
        fi
        
        # Check if UFW is enabled
        if [ \"\$(ufw status | grep -o 'Status: active')\" != \"Status: active\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} UFW is not enabled\"
            errors=\$((errors+1))
        fi
        
        if [ \"\$errors\" -gt 0 ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} UFW verification failed\"
            exit 1
        fi
    "
}

# Function to show UFW status
show_ufw_status() {
    echo -e "\n${BLUE}${BOLD}[i]${NC} Current UFW Status:"
    ufw status verbose
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║        UFW Firewall Setup              ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run as root"
    exit 1
fi

# Check for existing UFW installation
if check_package_installed "ufw"; then
    echo -e "${YELLOW}${BOLD}[!]${NC} UFW is already installed"
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to reconfigure it? [y/N] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to install and configure UFW? [Y/n] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        echo -e "${YELLOW}${BOLD}[!]${NC} Setup cancelled."
        exit 0
    fi
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Setting up UFW firewall..."

# Install UFW if not present
if ! check_package_installed "ufw"; then
    install_ufw
fi

# Configure and enable UFW
configure_ufw
enable_ufw

# Give the service a moment to fully start
sleep 2

# Verify configuration
verify_ufw

# Show final status
show_ufw_status

echo -e "\n${GREEN}${BOLD}[✓]${NC} UFW has been configured successfully!"
echo -e "${BLUE}${BOLD}[i]${NC} The firewall is now active and will start automatically on boot"
echo -e "${YELLOW}${BOLD}[!]${NC} You can check the firewall status anytime with: ufw status" 
