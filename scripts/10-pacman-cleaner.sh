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

# Function to create service file
create_service() {
    run_with_spinner "Creating pacman-cleaner service" bash -c "
        cat > /etc/systemd/system/pacman-cleaner.service << \"EOF\"
[Unit]
Description=Cleans pacman cache

[Service]
Type=oneshot
ExecStart=/usr/bin/pacman -Scc --noconfirm

[Install]
WantedBy=multi-user.target
EOF
    "
}

# Function to create timer file
create_timer() {
    run_with_spinner "Creating pacman-cleaner timer" bash -c "
        cat > /etc/systemd/system/pacman-cleaner.timer << \"EOF\"
[Unit]
Description=Run clean of pacman cache every week

[Timer]
OnCalendar=weekly
AccuracySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
    "
}

# Function to enable and start timer
enable_timer() {
    run_with_spinner "Enabling and starting pacman-cleaner timer" bash -c "
        systemctl daemon-reload
        systemctl enable pacman-cleaner.timer
        systemctl start pacman-cleaner.timer
    "
}

# Function to verify setup
verify_setup() {
    run_with_spinner "Verifying setup" bash -c "
        errors=0
        
        # Check if service file exists
        if [ ! -f \"/etc/systemd/system/pacman-cleaner.service\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Service file not found\"
            errors=\$((errors+1))
        fi
        
        # Check if timer file exists
        if [ ! -f \"/etc/systemd/system/pacman-cleaner.timer\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Timer file not found\"
            errors=\$((errors+1))
        fi
        
        # Check if timer is enabled and active
        if ! systemctl is-enabled pacman-cleaner.timer >/dev/null 2>&1; then
            echo -e \"${RED}${BOLD}[✗]${NC} Timer is not enabled\"
            errors=\$((errors+1))
        fi
        
        if ! systemctl is-active pacman-cleaner.timer >/dev/null 2>&1; then
            echo -e \"${RED}${BOLD}[✗]${NC} Timer is not active\"
            errors=\$((errors+1))
        fi
        
        if [ \"\$errors\" -gt 0 ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Setup verification failed\"
            exit 1
        fi
    "
}

# Function to show timer status
show_timer_status() {
    echo -e "\n${BLUE}${BOLD}[i]${NC} Current timer status:"
    systemctl list-timers pacman-cleaner.timer
}

# Function to remove existing configuration
remove_existing_config() {
    run_with_spinner "Removing existing configuration" bash -c "
        systemctl stop pacman-cleaner.timer &>/dev/null || true
        systemctl disable pacman-cleaner.timer &>/dev/null || true
        rm -f /etc/systemd/system/pacman-cleaner.service
        rm -f /etc/systemd/system/pacman-cleaner.timer
        systemctl daemon-reload
    "
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║     Pacman Cache Cleaner Setup         ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run as root"
    exit 1
fi

# Initial prompt
echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to set up automatic pacman cache cleaning? [Y/n] "
read -n 1 -r REPLY
echo
if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Setup cancelled."
    exit 0
fi

# Check and handle existing configuration
if [ -f "/etc/systemd/system/pacman-cleaner.service" ] || [ -f "/etc/systemd/system/pacman-cleaner.timer" ]; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Existing configuration detected, removing..."
    remove_existing_config
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Setting up pacman cache cleaner..."

# Create service and timer
create_service
create_timer

# Enable and start timer
enable_timer

# Verify setup
verify_setup

# Show timer status
show_timer_status

echo -e "\n${GREEN}${BOLD}[✓]${NC} Pacman cache cleaner has been set up!"
echo -e "${BLUE}${BOLD}[i]${NC} Cache will be cleaned automatically every week"
echo -e "${YELLOW}${BOLD}[!]${NC} You can check the timer status with: systemctl list-timers pacman-cleaner.timer" 