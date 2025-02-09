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

# Function to check if package exists in repos
check_package_available() {
    pacman -Ss "^${1}$" &>/dev/null
}

# Function to install irqbalance
install_irqbalance() {
    if ! check_package_available "irqbalance"; then
        run_with_spinner "Updating package database" bash -c "pacman -Sy --noconfirm &>/dev/null"
    fi
    
    run_with_spinner "Installing irqbalance" bash -c "pacman -S --noconfirm irqbalance &>/dev/null"
}

# Function to configure irqbalance
configure_irqbalance() {
    run_with_spinner "Configuring irqbalance" bash -c "
        # Create override directory if it doesn't exist
        mkdir -p /etc/systemd/system/irqbalance.service.d

        # Create override configuration
        cat > /etc/systemd/system/irqbalance.service.d/override.conf << \"EOF\"
[Service]
Environment=IRQBALANCE_ARGS=\"--foreground\"
Type=simple
Restart=always
RestartSec=2
EOF

        # Reload systemd to apply changes
        systemctl daemon-reload &>/dev/null
    "
}

# Function to enable and start irqbalance
enable_irqbalance() {
    run_with_spinner "Enabling and starting irqbalance service" bash -c "
        # Stop any existing instance
        systemctl stop irqbalance &>/dev/null || true
        
        # Enable and start the service
        systemctl enable --now irqbalance &>/dev/null
        
        # Give the service some time to start
        sleep 2
        
        # Verify it's running
        if ! systemctl is-active --quiet irqbalance; then
            # Try restarting if initial start failed
            systemctl restart irqbalance &>/dev/null
            sleep 2
        fi
    "
}

# Function to verify setup
verify_setup() {
    run_with_spinner "Verifying setup" bash -c "
        errors=0
        
        # Check if package is installed
        if ! pacman -Qi irqbalance &>/dev/null; then
            echo -e \"${RED}${BOLD}[✗]${NC} irqbalance package not installed\" >&2
            errors=\$((errors+1))
        fi
        
        # Check if service is enabled
        if ! systemctl is-enabled --quiet irqbalance; then
            echo -e \"${RED}${BOLD}[✗]${NC} irqbalance service not enabled\" >&2
            errors=\$((errors+1))
        fi
        
        # Check if service is active
        if ! systemctl is-active --quiet irqbalance; then
            # Get service status for debugging
            status=\$(systemctl status irqbalance 2>&1)
            echo -e \"${RED}${BOLD}[✗]${NC} irqbalance service not active\" >&2
            echo \"Service status: \$status\" >&2
            errors=\$((errors+1))
        fi
        
        if [ \"\$errors\" -gt 0 ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Setup verification failed\" >&2
            exit 1
        fi
    "
}

# Function to show service status
show_status() {
    local status=$(systemctl is-active irqbalance)
    local enabled=$(systemctl is-enabled irqbalance)
    
    echo -e "\n${BLUE}${BOLD}[i]${NC} IRQ Balance Status:"
    echo -e "   Status: ${GREEN}${BOLD}$status${NC}"
    echo -e "   Startup: ${GREEN}${BOLD}$enabled${NC}"
}

# Function to remove existing configuration
remove_existing_config() {
    run_with_spinner "Removing existing configuration" bash -c "
        systemctl stop irqbalance &>/dev/null || true
        systemctl disable irqbalance &>/dev/null || true
        rm -rf /etc/systemd/system/irqbalance.service.d
        pacman -R --noconfirm irqbalance &>/dev/null || true
        systemctl daemon-reload
    "
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║        IRQ Balance Setup               ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run as root"
    exit 1
fi

# Initial prompt
echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to set up IRQ balancing? [Y/n] "
read -n 1 -r REPLY
echo
if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Setup cancelled."
    exit 0
fi

# Check and handle existing installation
if check_package_installed "irqbalance"; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Existing installation detected, removing..."
    remove_existing_config
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Setting up IRQ balancing..."

# Install and configure
install_irqbalance
configure_irqbalance
enable_irqbalance

# Verify setup
verify_setup

# Show status
show_status

echo -e "\n${GREEN}${BOLD}[✓]${NC} IRQ balancing has been set up!"
echo -e "${BLUE}${BOLD}[i]${NC} The service is now running and will start automatically on boot"
echo -e "${YELLOW}${BOLD}[!]${NC} You can check the service status with: systemctl status irqbalance" 
