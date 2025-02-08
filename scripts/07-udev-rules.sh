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

# Function to create ZRAM udev rules
create_zram_rules() {
    run_with_spinner "Creating ZRAM udev rules" bash -c "
        cat > /etc/udev/rules.d/99-zram.rules << \"EOF\"
# ZRAM swappiness optimization
TEST!=\"/dev/zram0\", GOTO=\"zram_end\"

# Optimize swappiness for ZRAM
# High value (150) to prefer swapping anonymous pages to ZRAM
# This keeps the page cache intact and improves overall performance
# as uncompressing from ZRAM is faster than reading from disk
SYSCTL{vm.swappiness}=\"150\"

LABEL=\"zram_end\"
EOF
    "
}

# Function to create disk scheduler rules
create_disk_rules() {
    run_with_spinner "Creating disk scheduler rules" bash -c "
        cat > /etc/udev/rules.d/60-ioschedulers.rules << \"EOF\"
# SATA Active Link Power Management
ACTION==\"add\", SUBSYSTEM==\"scsi_host\", KERNEL==\"host*\", \\
    ATTR{link_power_management_policy}==\"*\", \\
    ATTR{link_power_management_policy}=\"max_performance\"

# HDD - Use BFQ scheduler for better throughput
ACTION==\"add|change\", KERNEL==\"sd[a-z]*\", ATTR{queue/rotational}==\"1\", \\
    ATTR{queue/scheduler}=\"bfq\"

# SSD - Use mq-deadline for better latency
ACTION==\"add|change\", KERNEL==\"sd[a-z]*|mmcblk[0-9]*\", ATTR{queue/rotational}==\"0\", \\
    ATTR{queue/scheduler}=\"mq-deadline\"

# NVMe SSD - No scheduler for direct hardware access
ACTION==\"add|change\", KERNEL==\"nvme[0-9]*\", ATTR{queue/rotational}==\"0\", \\
    ATTR{queue/scheduler}=\"none\"

# HDD power management
ACTION==\"add|change\", KERNEL==\"sd[a-z]\", ATTR{queue/rotational}==\"1\", \\
    RUN+=\"/usr/bin/hdparm -B 254 -S 0 /dev/%k\"
EOF
    "
}

# Function to create audio device rules
create_audio_rules() {
    run_with_spinner "Creating audio device rules" bash -c "
        cat > /etc/udev/rules.d/40-audio.rules << \"EOF\"
# Give audio group access to RTC and HPET
KERNEL==\"rtc0\", GROUP=\"audio\"
KERNEL==\"hpet\", GROUP=\"audio\"

# CPU DMA latency control for audio
DEVPATH==\"/devices/virtual/misc/cpu_dma_latency\", \\
    OWNER=\"root\", GROUP=\"audio\", MODE=\"0660\"
EOF
    "
}

# Function to verify rules
verify_rules() {
    run_with_spinner "Verifying udev rules" bash -c "
        errors=0
        
        # Check if rule files exist
        if [ ! -f \"/etc/udev/rules.d/99-zram.rules\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} ZRAM rules not found\"
            errors=\$((errors+1))
        fi
        
        if [ ! -f \"/etc/udev/rules.d/60-ioschedulers.rules\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} I/O scheduler rules not found\"
            errors=\$((errors+1))
        fi
        
        if [ ! -f \"/etc/udev/rules.d/40-audio.rules\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Audio rules not found\"
            errors=\$((errors+1))
        fi
        
        if [ \"\$errors\" -gt 0 ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Some rules were not created correctly\"
            exit 1
        fi
    "
}

# Function to apply rules
apply_rules() {
    run_with_spinner "Applying udev rules" bash -c "
        # Reload udev rules
        udevadm control --reload-rules
        
        # Trigger rules for existing devices
        udevadm trigger
    "
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║        System udev Rules Setup         ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run as root"
    exit 1
fi

# Check for existing rules
if [ -f "/etc/udev/rules.d/99-zram.rules" ] || \
   [ -f "/etc/udev/rules.d/60-ioschedulers.rules" ] || \
   [ -f "/etc/udev/rules.d/40-audio.rules" ]; then
    echo -ne "${YELLOW}${BOLD}[!]${NC} Existing udev rules detected. Would you like to reconfigure? [y/N] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Check for required packages
if ! command -v hdparm >/dev/null 2>&1; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Required package 'hdparm' not found. Installing..."
    run_with_spinner "Installing hdparm" pacman -S --noconfirm hdparm
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Setting up system udev rules..."

# Create all rules
create_zram_rules
create_disk_rules
create_audio_rules

# Verify rules
verify_rules

# Apply rules
apply_rules

echo -e "\n${GREEN}${BOLD}[✓]${NC} System udev rules have been configured!"
echo -e "${BLUE}${BOLD}[i]${NC} Rules will be applied to all new devices"
echo -e "${YELLOW}${BOLD}[!]${NC} Some changes may require a reboot to take full effect" 