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

# Function to apply udev rules
apply_udev_rules() {
    run_with_spinner "Configuring udev rules" bash -c '
        # Create rules directory if it does not exist
        mkdir -p /etc/udev/rules.d

        # Configure IO scheduler rules
        cat > /etc/udev/rules.d/60-scheduler.rules << "EOF"
# Set scheduler for NVMe
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
# Set scheduler for SSD and eMMC
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="bfq"
# Set scheduler for rotating disks
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF

        # Configure IO queue rules
        cat > /etc/udev/rules.d/60-ioscheduler.rules << "EOF"
# Increase the number of I/O requests that can be queued for NVMe devices
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/nr_requests}="2048"
# Increase the number of I/O requests that can be queued for SATA/eMMC devices
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/nr_requests}="512"
# Set optimal read-ahead size for NVMe devices
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/read_ahead_kb}="2048"
# Set optimal read-ahead size for SATA/eMMC devices
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/read_ahead_kb}="512"
EOF

        # Configure power saving rules
        cat > /etc/udev/rules.d/60-power.rules << "EOF"
# Enable ASPM power management for PCIe devices
ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
# Enable SATA power management
ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", ATTR{link_power_management_policy}="med_power_with_dipm"
# Enable USB autosuspend
ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="auto"
# Enable runtime power management for network devices
ACTION=="add", SUBSYSTEM=="net", TEST=="power/control", ATTR{power/control}="auto"
EOF

        # Reload udev rules
        udevadm control --reload
        udevadm trigger
    '
}

# Function to verify settings
verify_settings() {
    run_with_spinner "Verifying udev rules" bash -c "
        errors=0
        
        # Check if configuration files exist
        for rule in 60-scheduler.rules 60-ioscheduler.rules 60-power.rules; do
            if [ ! -f \"/etc/udev/rules.d/\$rule\" ]; then
                echo -e \"${RED}${BOLD}[✗]${NC} \$rule not found\"
                errors=\$((errors+1))
            fi
        done
        
        if [ \"\$errors\" -gt 0 ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Some rules were not applied correctly\"
            exit 1
        fi
    "
}

# Function to check current configuration status
check_current_status() {
    # Check if all rule files exist
    for rule in 60-scheduler.rules 60-ioscheduler.rules 60-power.rules; do
        if [ ! -f "/etc/udev/rules.d/$rule" ]; then
            return 1
        fi
    done
    
    return 0
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║         Udev Rules Configuration       ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run as root"
    exit 1
fi

# Check current status and existing configurations
if check_current_status; then
    echo -e "${GREEN}${BOLD}[✓]${NC} Current udev rules are properly configured."
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to reconfigure anyway? [y/N] "
    CONFIGS_EXIST=1
elif [ -d "/etc/udev/rules.d" ] && [ "$(ls -A /etc/udev/rules.d/)" ]; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Existing udev rules found but may not be complete."
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to reconfigure? [y/N] "
    CONFIGS_EXIST=1
else
    echo -e "${RED}${BOLD}[✗]${NC} No udev rules configuration found."
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to configure udev rules? [Y/n] "
    CONFIGS_EXIST=0
fi

read -n 1 -r REPLY
echo

if [ $CONFIGS_EXIST -eq 1 ]; then
    # For existing configs, require explicit yes
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}${BOLD}[!]${NC} Setup cancelled."
        exit 0
    fi
    # Clean up old configurations before proceeding
    run_with_spinner "Removing existing rules" bash -c 'rm -f /etc/udev/rules.d/{60-scheduler,60-ioscheduler,60-power}.rules'
else
    # For new installation, proceed unless explicit no
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        echo -e "${YELLOW}${BOLD}[!]${NC} Setup cancelled."
        exit 0
    fi
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Applying udev rules..."

# Apply settings
apply_udev_rules

# Verify settings
verify_settings

echo -e "\n${GREEN}${BOLD}[✓]${NC} Udev rules have been configured!"
echo -e "${BLUE}${BOLD}[i]${NC} Changes will persist across reboots"
echo -e "${YELLOW}${BOLD}[!]${NC} Some changes may require a reboot to take full effect" 
