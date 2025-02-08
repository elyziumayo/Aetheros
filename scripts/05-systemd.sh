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

# Function to configure journald
configure_journald() {
    run_with_spinner "Configuring journald settings" bash -c "
        # Create journald configuration directory if it doesn't exist
        mkdir -p /etc/systemd/journald.conf.d

        # Create journald configuration
        cat > /etc/systemd/journald.conf.d/00-journal-size.conf << \"EOF\"
[Journal]
# Limit journal size to 50MB
SystemMaxUse=50M
# Compress journals
Compress=yes
# Forward to syslog
ForwardToSyslog=no
# Split journals by user
SplitMode=uid
# Sync before writing
SyncIntervalSec=5m
EOF
    "
}

# Function to configure system limits
configure_system_limits() {
    run_with_spinner "Configuring system limits" bash -c "
        # Create system.conf.d directory if it doesn't exist
        mkdir -p /etc/systemd/system.conf.d

        # Create system limits configuration
        cat > /etc/systemd/system.conf.d/limits.conf << \"EOF\"
[Manager]
# Default timeouts
DefaultTimeoutStartSec=15s
DefaultTimeoutStopSec=10s
# System-wide file descriptor limits
DefaultLimitNOFILE=2048:2097152
# Optimize memory management
DefaultLimitMEMLOCK=infinity
# Optimize core dumps
DefaultLimitCORE=0
EOF
    "
}

# Function to configure user limits
configure_user_limits() {
    run_with_spinner "Configuring user limits" bash -c "
        # Create user.conf.d directory if it doesn't exist
        mkdir -p /etc/systemd/user.conf.d

        # Create user limits configuration
        cat > /etc/systemd/user.conf.d/limits.conf << \"EOF\"
[Manager]
# User-specific file descriptor limits
DefaultLimitNOFILE=1024:1048576
# Optimize memory management for user services
DefaultLimitMEMLOCK=infinity
# Disable core dumps for user services
DefaultLimitCORE=0
EOF
    "
}

# Function to verify settings
verify_settings() {
    run_with_spinner "Verifying systemd settings" bash -c "
        errors=0
        
        # Check if configuration files exist
        if [ ! -f \"/etc/systemd/journald.conf.d/00-journal-size.conf\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Journald configuration not found\"
            errors=\$((errors+1))
        fi
        
        if [ ! -f \"/etc/systemd/system.conf.d/limits.conf\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} System limits configuration not found\"
            errors=\$((errors+1))
        fi
        
        if [ ! -f \"/etc/systemd/user.conf.d/limits.conf\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} User limits configuration not found\"
            errors=\$((errors+1))
        fi
        
        if [ \"\$errors\" -gt 0 ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Some configurations were not applied correctly\"
            exit 1
        fi
    "
}

# Function to restart systemd-journald
restart_services() {
    run_with_spinner "Restarting systemd-journald" bash -c '
        systemctl restart systemd-journald
    '
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║       Systemd Optimization Setup       ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run as root"
    exit 1
fi

# Check for existing configurations
if [ -f "/etc/systemd/journald.conf.d/00-journal-size.conf" ] || \
   [ -f "/etc/systemd/system.conf.d/limits.conf" ] || \
   [ -f "/etc/systemd/user.conf.d/limits.conf" ]; then
    echo -ne "${YELLOW}${BOLD}[!]${NC} Existing configurations detected. Would you like to reconfigure? [y/N] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Applying systemd optimizations..."

# Configure all components
configure_journald
configure_system_limits
configure_user_limits

# Verify configurations
verify_settings

# Restart services
restart_services

echo -e "\n${GREEN}${BOLD}[✓]${NC} Systemd settings have been optimized!"
echo -e "${BLUE}${BOLD}[i]${NC} Changes will persist across reboots"
echo -e "${YELLOW}${BOLD}[!]${NC} Some changes may require a reboot to take full effect" 