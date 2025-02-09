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

# Function to detect CPU architecture
detect_cpu_arch() {
    # Get CPU flags
    local cpu_flags=$(grep -m1 '^flags' /proc/cpuinfo)
    
    # Check for x86-64-v4 (AVX-512)
    if echo "$cpu_flags" | grep -q "avx512f"; then
        echo "x86-64-v4"
    # Check for x86-64-v3 (AVX2)
    elif echo "$cpu_flags" | grep -q "avx2"; then
        echo "x86-64-v3"
    # Check for x86-64-v2 (SSE4.2)
    elif echo "$cpu_flags" | grep -q "sse4_2"; then
        echo "x86-64-v2"
    else
        echo "unsupported"
    fi
}

# Function to check if ALHP is installed
check_alhp() {
    pacman -Qi alhp-keyring &>/dev/null
}

# Function to install and configure chaotic-aur temporarily
setup_chaotic() {
    run_with_spinner "Setting up temporary Chaotic AUR" bash -c '
        pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com &>/dev/null &&
        pacman-key --lsign-key 3056513887B78AEB &>/dev/null &&
        pacman -U "https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst" --noconfirm &>/dev/null &&
        pacman -U "https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst" --noconfirm &>/dev/null &&
        echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >> /etc/pacman.conf &&
        pacman -Sy &>/dev/null
    '
}

# Function to remove chaotic-aur
remove_chaotic() {
    run_with_spinner "Removing temporary Chaotic AUR" bash -c '
        sed -i "/\[chaotic-aur\]/,+1d" /etc/pacman.conf &&
        pacman -R chaotic-keyring chaotic-mirrorlist --noconfirm &>/dev/null
    '
}

# Function to configure ALHP repositories
configure_alhp() {
    local arch=$1
    local temp_file=$(mktemp)
    
    run_with_spinner "Configuring ALHP repositories" bash -c "
        # Read existing pacman.conf
        cat /etc/pacman.conf > '$temp_file' &&
        
        # Remove any existing ALHP configurations
        sed -i '/\[core-$arch\]/,+1d' '$temp_file' &&
        sed -i '/\[extra-$arch\]/,+1d' '$temp_file' &&
        sed -i '/\[multilib-$arch\]/,+1d' '$temp_file' &&
        
        # Add ALHP repositories in correct positions
        sed -i '/\[core\]/i [core-$arch]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n' '$temp_file' &&
        sed -i '/\[extra\]/i [extra-$arch]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n' '$temp_file' &&
        
        if grep -q '\[multilib\]' '$temp_file'; then
            sed -i '/\[multilib\]/i [multilib-$arch]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n' '$temp_file'
        fi &&
        
        # Apply the changes
        mv '$temp_file' /etc/pacman.conf
    "
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║        ALHP Installation Script        ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}"
echo

# Detect CPU architecture
arch=$(detect_cpu_arch)
if [ "$arch" == "unsupported" ]; then
    echo -e "${RED}${BOLD}[✗]${NC} Your CPU architecture is not supported by ALHP."
    exit 1
fi

echo -e "${BLUE}${BOLD}[i]${NC} Detected CPU architecture: $arch"

# Check if ALHP is already installed
if check_alhp; then
    echo -ne "${YELLOW}${BOLD}[!]${NC} ALHP is already installed on your system. Do you want to reconfigure it? [y/N] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to install ALHP for better performance? [Y/n] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        echo -e "${YELLOW}${BOLD}[!]${NC} Installation cancelled."
        exit 0
    fi
fi

# Install ALHP
echo -e "\n${BLUE}${BOLD}[i]${NC} Starting ALHP installation..."

# Setup chaotic-aur temporarily
setup_chaotic

# Install ALHP packages
run_with_spinner "Installing ALHP packages" bash -c '
    pacman -S alhp-keyring alhp-mirrorlist --noconfirm &>/dev/null
'

# Remove chaotic-aur
remove_chaotic

# Configure ALHP
configure_alhp "$arch"

# Update package database
run_with_spinner "Updating package database" bash -c '
    pacman -Sy &>/dev/null
'

# Final system update
run_with_spinner "Updating system with ALHP repositories" bash -c '
    pacman -Syu --noconfirm &>/dev/null
'

# Cleanup backup files
run_with_spinner "Cleaning up" bash -c '
    rm -f /etc/pacman.conf.* /etc/pacman.d/*.old /etc/pacman.d/*.bak &>/dev/null
'

echo -e "\n${GREEN}${BOLD}[✓]${NC} ALHP has been successfully installed and configured!" 