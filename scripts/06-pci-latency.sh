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

# Function to create the PCI latency script
create_pci_script() {
    run_with_spinner "Creating PCI latency script" bash -c "
        # Create the script
        cat > /usr/bin/pci-latency << \"EOF\"
#!/usr/bin/env sh
# This script optimizes PCI latency timers for better audio performance
# - Sets sound card latency to 80 cycles for optimal audio performance
# - Resets other PCI devices to prevent audio gaps
# - Sets root bridge to 0 for better overall latency

# Check for root privileges
if [ \"\$(id -u)\" -ne 0 ]; then
    echo \"Error: This script must be run with root privileges.\" >&2
    exit 1
fi

# Reset latency timer for all PCI devices to a balanced value
setpci -v -s '*:*' latency_timer=20

# Set root bridge latency to 0 for better overall performance
setpci -v -s '0:0' latency_timer=0

# Set optimal latency for all sound cards (class 0x04)
setpci -v -d '*:*:04xx' latency_timer=80

exit 0
EOF

        # Make the script executable
        chmod +x /usr/bin/pci-latency
    "
}

# Function to create the systemd service
create_service() {
    run_with_spinner "Creating systemd service" bash -c "
        # Create the service file
        cat > /etc/systemd/system/pci-latency.service << \"EOF\"
[Unit]
Description=Adjust latency timers for PCI peripherals
Documentation=https://wiki.archlinux.org/title/Advanced_Linux_Sound_Architecture
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/pci-latency
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    "
}

# Function to verify installation
verify_installation() {
    run_with_spinner "Verifying installation" bash -c "
        errors=0
        
        # Check if script exists and is executable
        if [ ! -x \"/usr/bin/pci-latency\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} PCI latency script not found or not executable\"
            errors=\$((errors+1))
        fi
        
        # Check if service file exists
        if [ ! -f \"/etc/systemd/system/pci-latency.service\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} PCI latency service not found\"
            errors=\$((errors+1))
        fi
        
        # Check if setpci is available
        if ! command -v setpci >/dev/null 2>&1; then
            echo -e \"${RED}${BOLD}[✗]${NC} setpci command not found. Please install pciutils\"
            errors=\$((errors+1))
        fi
        
        if [ \"\$errors\" -gt 0 ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Some components were not installed correctly\"
            exit 1
        fi
    "
}

# Function to enable and start the service
enable_service() {
    run_with_spinner "Enabling PCI latency service" bash -c "
        systemctl daemon-reload
        systemctl enable pci-latency.service
        systemctl start pci-latency.service
    "
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║      PCI Latency Optimization         ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run as root"
    exit 1
fi

# Check for existing installation
if [ -f "/usr/bin/pci-latency" ] || [ -f "/etc/systemd/system/pci-latency.service" ]; then
    echo -ne "${YELLOW}${BOLD}[!]${NC} Existing PCI latency configuration detected. Would you like to reconfigure? [y/N] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Check for required package
if ! command -v setpci >/dev/null 2>&1; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Required package 'pciutils' not found. Installing..."
    run_with_spinner "Installing pciutils" pacman -S --noconfirm pciutils
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Setting up PCI latency optimization..."

# Create script and service
create_pci_script
create_service

# Verify installation
verify_installation

# Enable and start service
enable_service

echo -e "\n${GREEN}${BOLD}[✓]${NC} PCI latency optimization has been configured!"
echo -e "${BLUE}${BOLD}[i]${NC} The service will automatically start on boot"
echo -e "${YELLOW}${BOLD}[!]${NC} Changes are already active, no reboot required" 