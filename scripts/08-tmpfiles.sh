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

# Function to create tmpfiles configuration
create_tmpfiles_conf() {
    run_with_spinner "Creating tmpfiles configuration" bash -c "
        cat > /etc/tmpfiles.d/99-sysctl.conf << \"EOF\"
# Clear coredumps older than 3 days
d /var/lib/systemd/coredump 0755 root root 3d

# Disable zswap when using ZRAM
w! /sys/module/zswap/parameters/enabled - - - - N

# Increase RTC interrupt frequency for pro audio
w! /sys/class/rtc/rtc0/max_user_freq - - - - 3072
w! /proc/sys/dev/hpet/max-user-freq  - - - - 3072

# THP Shrinker optimization (Kernel 6.12+)
# Split THPs that are 80% zero filled to reduce memory usage
w! /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 409

# Optimize THP for tcmalloc performance
w! /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise
EOF
    "
}

# Function to create documentation
create_documentation() {
    run_with_spinner "Creating documentation" bash -c "
        cat > /etc/tmpfiles.d/README.md << \"EOF\"
# System Performance Configuration

This configuration optimizes various system parameters for better performance:

## Coredump Management
- Automatically cleans up coredumps older than 3 days
- Helps prevent disk space exhaustion from debug files

## ZRAM Optimization
- Disables zswap when using ZRAM
- Prevents interference with ZRAM compression tracking

## Audio Performance
- Sets RTC and HPET frequencies to 3072Hz
- Improves timer precision for professional audio

## Memory Management
- Optimizes Transparent Huge Pages (THP)
- Reduces memory usage with THP shrinker
- Improves tcmalloc performance
- Prevents excessive memory pressure

For more information:
- https://wiki.archlinux.org/title/Professional_audio
- https://github.com/google/tcmalloc/blob/master/docs/tuning.md
EOF
    "
}

# Function to verify configuration
verify_configuration() {
    run_with_spinner "Verifying configuration" bash -c "
        errors=0
        
        # Check if configuration file exists
        if [ ! -f \"/etc/tmpfiles.d/99-sysctl.conf\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Tmpfiles configuration not found\"
            errors=\$((errors+1))
        fi
        
        # Check if documentation exists
        if [ ! -f \"/etc/tmpfiles.d/README.md\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Documentation not found\"
            errors=\$((errors+1))
        fi
        
        if [ \"\$errors\" -gt 0 ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Some files were not created correctly\"
            exit 1
        fi
    "
}

# Function to apply configuration
apply_configuration() {
    run_with_spinner "Applying configuration" bash -c "
        # Process tmpfiles configuration
        systemd-tmpfiles --create --remove
        
        # Verify key settings
        if [ -f /sys/module/zswap/parameters/enabled ]; then
            current=\$(cat /sys/module/zswap/parameters/enabled)
            if [ \"\$current\" != \"N\" ]; then
                echo -e \"${YELLOW}${BOLD}[!]${NC} zswap setting not applied, may require reboot\"
            fi
        fi
        
        if [ -f /sys/kernel/mm/transparent_hugepage/defrag ]; then
            current=\$(cat /sys/kernel/mm/transparent_hugepage/defrag)
            if [[ \"\$current\" != *\"[defer+madvise]\"* ]]; then
                echo -e \"${YELLOW}${BOLD}[!]${NC} THP setting not applied, may require reboot\"
            fi
        fi
    "
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║    System Performance Configuration    ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run as root"
    exit 1
fi

# Check for existing configuration
if [ -f "/etc/tmpfiles.d/99-sysctl.conf" ]; then
    echo -ne "${YELLOW}${BOLD}[!]${NC} Existing configuration detected. Would you like to reconfigure? [y/N] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Setting up system performance configuration..."

# Create configuration
create_tmpfiles_conf
create_documentation

# Verify configuration
verify_configuration

# Apply configuration
apply_configuration

echo -e "\n${GREEN}${BOLD}[✓]${NC} System performance parameters have been configured!"
echo -e "${BLUE}${BOLD}[i]${NC} Configuration will persist across reboots"
echo -e "${YELLOW}${BOLD}[!]${NC} Some changes may require a reboot to take full effect" 