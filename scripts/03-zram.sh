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
    local pkg="$1"
    pacman -Ss "^${pkg}$" &>/dev/null
}

# Function to remove package if installed
remove_package() {
    local pkg="$1"
    if check_package_installed "$pkg"; then
        run_with_spinner "Removing $pkg" bash -c "pacman -R --noconfirm $pkg &>/dev/null"
    fi
}

# Function to check if zram is currently active
check_zram_active() {
    lsmod | grep -q "^zram" || [ -d "/sys/class/zram-control" ]
}

# Function to stop and cleanup existing zram
cleanup_existing_zram() {
    run_with_spinner "Stopping existing ZRAM devices" bash -c '
        # Stop all zram swap devices
        for swap in $(swapon --show=NAME --noheadings | grep zram); do
            swapoff "$swap" &>/dev/null || true
        done

        # Remove existing zram devices
        for zram in /dev/zram*; do
            if [ -e "$zram" ]; then
                echo 1 > "/sys/class/block/$(basename $zram)/reset" 2>/dev/null || true
            fi
        done

        # Stop and disable existing zram services
        systemctl stop systemd-zram-setup@* &>/dev/null || true
        systemctl disable systemd-zram-setup@* &>/dev/null || true
        systemctl stop zramswap.service &>/dev/null || true
        systemctl disable zramswap.service &>/dev/null || true

        # Remove old config files
        rm -f /etc/systemd/zram-generator.conf &>/dev/null || true
        rm -f /etc/systemd/zram-generator.conf.d/*.conf &>/dev/null || true
    '
}

# Function to install zram-generator
install_zram() {
    if ! check_package_available "zram-generator"; then
        echo -e "${RED}${BOLD}[✗]${NC} Package 'zram-generator' not found in repositories."
        echo -e "${YELLOW}${BOLD}[!]${NC} Attempting to sync package databases..."
        
        run_with_spinner "Updating package databases" bash -c '
            pacman -Sy &>/dev/null
        '
        
        if ! check_package_available "zram-generator"; then
            echo -e "${RED}${BOLD}[✗]${NC} Failed to find zram-generator package."
            echo -e "${YELLOW}${BOLD}[!]${NC} Please make sure you have the correct repositories enabled."
            exit 1
        fi
    fi

    run_with_spinner "Installing ZRAM Generator" bash -c '
        pacman -S --noconfirm zram-generator &>/dev/null
    '
}

# Function to configure zram
configure_zram() {
    run_with_spinner "Configuring ZRAM" bash -c '
        # Create the configuration file
        cat > /etc/systemd/zram-generator.conf << "EOF"
[zram0]
compression-algorithm = zstd lz4 (type=huge)
zram-size = ram
swap-priority = 100
fs-type = swap
EOF
    '
}

# Function to apply zram configuration
apply_zram() {
    run_with_spinner "Applying ZRAM configuration" bash -c '
        # Reload systemd to pick up new configuration
        systemctl daemon-reload

        # Try to find the correct service name
        if systemctl list-unit-files | grep -q "systemd-zram-setup@"; then
            # Use template service
            systemctl stop systemd-zram-setup@zram0.service &>/dev/null || true
            systemctl disable systemd-zram-setup@zram0.service &>/dev/null || true
            # Redirect both stdout and stderr to suppress warnings
            systemctl enable systemd-zram-setup@zram0.service &>/dev/null || true
            systemctl start systemd-zram-setup@zram0.service &>/dev/null || true
        else
            # Manual setup if service is not available
            echo "Service not found, setting up ZRAM manually..." >&2
            
            # Ensure zram module is loaded
            modprobe zram

            # Wait for zram0 device
            while [ ! -e "/dev/zram0" ]; do
                sleep 0.1
            done

            # Configure zram0
            echo zstd | tee /sys/block/zram0/comp_algorithm >/dev/null
            echo $(grep MemTotal /proc/meminfo | awk "{print \$2 * 1024}") | tee /sys/block/zram0/disksize >/dev/null
            
            # Setup swap
            mkswap -f /dev/zram0 >/dev/null
            swapon -p 100 /dev/zram0
        fi

        # Wait for ZRAM device to be ready
        sleep 2
    '
}

# Function to check zram status
check_zram_status() {
    # Check if ZRAM is active in swap
    if swapon --show | grep -q zram; then
        return 0
    fi
    return 1
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║         ZRAM Configuration             ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run as root"
    exit 1
fi

# Check for existing installations and configurations
NEEDS_INSTALL=true
if check_package_installed "zram-generator" || check_zram_active; then
    echo -ne "${YELLOW}${BOLD}[!]${NC} Existing ZRAM installation detected. Would you like to remove and reconfigure it? [y/N] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    # Clean up existing installation
    cleanup_existing_zram
    remove_package "zram-generator"
else
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to configure ZRAM for better system performance? [Y/n] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        echo -e "${YELLOW}${BOLD}[!]${NC} Configuration cancelled."
        exit 0
    fi
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Installing and configuring ZRAM..."

# Install fresh copy of zram-generator
install_zram

# Configure ZRAM
configure_zram

# Apply configuration
apply_zram

# Show status
echo -e "\n${GREEN}${BOLD}[✓]${NC} ZRAM has been successfully configured!"
echo -e "${BLUE}${BOLD}[i]${NC} Current ZRAM Status:"

# Check if ZRAM is working
if check_zram_status; then
    run_with_spinner "Checking ZRAM status" bash -c '
        echo
        echo "ZRAM Devices:"
        swapon --show | grep zram
        echo
        echo "ZRAM Statistics:"
        zramctl
        echo
        echo "Compression Algorithm:"
        cat /sys/block/zram0/comp_algorithm | grep -o "\[.*\]" || echo "Current: zstd"
    '
else
    echo -e "${RED}${BOLD}[✗]${NC} ZRAM is not active. Manual intervention required:"
    echo -e "1. Check if zram module is loaded: lsmod | grep zram"
    echo -e "2. Verify /dev/zram0 exists: ls -l /dev/zram0"
    echo -e "3. Check dmesg for errors: dmesg | grep zram"
    echo -e "4. Try manual setup: modprobe zram && echo zstd > /sys/block/zram0/comp_algorithm"
fi 
