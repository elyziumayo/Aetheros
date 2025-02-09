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

# Function to apply tmpfiles configurations
apply_tmpfiles_settings() {
    run_with_spinner "Configuring tmpfiles settings" bash -c '
        # Create tmpfiles.d directory if it does not exist
        mkdir -p /etc/tmpfiles.d

        # Configure coredump cleanup
        cat > /etc/tmpfiles.d/coredump.conf << "EOF"
# Clear all coredumps that were created more than 3 days ago
d /var/lib/systemd/coredump 0755 root root 3d
EOF

        # Configure zswap disable
        cat > /etc/tmpfiles.d/disable-zswap.conf << "EOF"
# We ship using ZRAM by default, and zswap may prevent it from working
# properly or keeping a proper count of compressed pages via zramctl
w! /sys/module/zswap/parameters/enabled - - - - N
EOF

        # Configure interrupt frequency
        cat > /etc/tmpfiles.d/optimize-interruptfreq.conf << "EOF"
# Increase the highest requested RTC interrupt frequency
# https://wiki.archlinux.org/title/Professional_audio#System_configuration
w! /sys/class/rtc/rtc0/max_user_freq - - - - 3072
w! /proc/sys/dev/hpet/max-user-freq  - - - - 3072
EOF

        # Configure THP shrinker
        cat > /etc/tmpfiles.d/thp-shrinker.conf << "EOF"
# THP Shrinker has been added in the 6.12 Kernel
# Default Value is 511
# THP=always policy vastly overprovisions THPs in sparsely accessed memory areas, resulting in excessive memory pressure and premature OOM killing
# 409 means that any THP that has more than 409 out of 512 (80%) zero filled filled pages will be split.
# This reduces the memory usage, when THP=always used and the memory usage goes down to around the same usage as when madvise is used, while still providing an equal performance improvement
w! /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 409
EOF

        # Configure THP settings
        cat > /etc/tmpfiles.d/thp.conf << "EOF"
# Improve performance for applications that use tcmalloc
# https://github.com/google/tcmalloc/blob/master/docs/tuning.md#system-level-optimizations
w! /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise
EOF

        # Apply settings
        systemd-tmpfiles --create --prefix=/etc/tmpfiles.d
    '
}

# Function to verify settings
verify_settings() {
    run_with_spinner "Verifying tmpfiles settings" bash -c "
        errors=0
        
        # Check if configuration files exist
        for conf in coredump.conf disable-zswap.conf optimize-interruptfreq.conf thp-shrinker.conf thp.conf; do
            if [ ! -f \"/etc/tmpfiles.d/\$conf\" ]; then
                echo -e \"${RED}${BOLD}[✗]${NC} \$conf not found\"
                errors=\$((errors+1))
            fi
        done
        
        if [ \"\$errors\" -gt 0 ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Some configurations were not applied correctly\"
            exit 1
        fi
    "
}

# Function to check current configuration status
check_current_status() {
    # Check if all config files exist
    for conf in coredump.conf disable-zswap.conf optimize-interruptfreq.conf thp-shrinker.conf thp.conf; do
        if [ ! -f "/etc/tmpfiles.d/$conf" ]; then
            return 1
        fi
    done
    
    return 0
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║      Tmpfiles Configuration Setup      ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run as root"
    exit 1
fi

# Check current status and existing configurations
if check_current_status; then
    echo -e "${GREEN}${BOLD}[✓]${NC} Current tmpfiles configuration is properly set up."
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to reconfigure anyway? [y/N] "
    CONFIGS_EXIST=1
elif [ -d "/etc/tmpfiles.d" ] && [ "$(ls -A /etc/tmpfiles.d/)" ]; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Existing tmpfiles configuration found but may not be complete."
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to reconfigure? [y/N] "
    CONFIGS_EXIST=1
else
    echo -e "${RED}${BOLD}[✗]${NC} No tmpfiles configuration found."
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to configure tmpfiles? [Y/n] "
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
    run_with_spinner "Removing existing configurations" bash -c 'rm -f /etc/tmpfiles.d/{coredump,disable-zswap,optimize-interruptfreq,thp-shrinker,thp}.conf'
else
    # For new installation, proceed unless explicit no
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        echo -e "${YELLOW}${BOLD}[!]${NC} Setup cancelled."
        exit 0
    fi
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Applying tmpfiles configurations..."

# Apply settings
apply_tmpfiles_settings

# Verify settings
verify_settings

echo -e "\n${GREEN}${BOLD}[✓]${NC} Tmpfiles configuration has been completed!"
echo -e "${BLUE}${BOLD}[i]${NC} Changes will persist across reboots"
echo -e "${YELLOW}${BOLD}[!]${NC} Some changes may require a reboot to take full effect" 
