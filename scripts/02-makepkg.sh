#!/bin/bash

# Colors and styling
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

# Get real user's home directory
REAL_HOME=$(eval echo ~${SUDO_USER:-$USER})

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

# Function to check if makepkg.conf exists
check_makepkg_conf() {
    [ -f "${REAL_HOME}/.makepkg.conf" ]
}

# Function to backup existing makepkg.conf
backup_makepkg_conf() {
    if [ -f "${REAL_HOME}/.makepkg.conf" ]; then
        run_with_spinner "Backing up existing makepkg.conf" bash -c "
            cp '${REAL_HOME}/.makepkg.conf' '${REAL_HOME}/.makepkg.conf.backup-$(date +%Y%m%d%H%M%S)'
        "
    fi
}

# Function to configure makepkg.conf
configure_makepkg() {
    run_with_spinner "Configuring makepkg.conf" bash -c '
        cat > '"${REAL_HOME}"'/.makepkg.conf << "EOFMAKEPKG"
# Core compilation flags
CFLAGS="-march=native -mtune=native -O3 -pipe \
        -fno-plt -fexceptions -fopenmp \
        -falign-functions=32 -fno-math-errno -fno-trapping-math \
        -fomit-frame-pointer -fstack-clash-protection \
        -fPIC -Wp,-D_FORTIFY_SOURCE=2 \
        -fcf-protection=none -mharden-sls=none \
        -fno-semantic-interposition \
        -fgraphite-identity -floop-nest-optimize \
        -fdevirtualize-at-ltrans -fipa-pta \
        -ffast-math -funroll-loops"

# C++ specific flags
CXXFLAGS="$CFLAGS -Wp,-D_GLIBCXX_ASSERTIONS \
          -fvisibility-inlines-hidden"

# Kernel-specific flags
export CFLAGS_KERNEL="$CFLAGS"
export CXXFLAGS_KERNEL="$CXXFLAGS"
export CFLAGS_MODULE="$CFLAGS"
export CXXFLAGS_MODULE="$CXXFLAGS"
export KBUILD_CFLAGS="$CFLAGS"
export KCFLAGS="-O3"
export KCPPFLAGS="$KCFLAGS"

# Linker optimizations (CMake compatible)
LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now"

# LTO flags
LTOFLAGS="-flto=auto"

# Rust optimizations
RUSTFLAGS="-C opt-level=3 -C target-cpu=native \
           -C codegen-units=1 -C lto=fat"

# Maximum parallel builds
MAKEFLAGS="-j$(nproc)"
NINJAFLAGS="-j$(nproc)"

# Environment setup
export CC="gcc"
export CXX="g++"
export AR="gcc-ar"
export NM="gcc-nm"
export RANLIB="gcc-ranlib"

# Makepkg options
OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug lto)
EOFMAKEPKG
        chown ${SUDO_USER:-$USER}:$(id -gn ${SUDO_USER:-$USER}) '"${REAL_HOME}"'/.makepkg.conf
'
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║      Makepkg Config Optimization       ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}"
echo

# Ensure we're not running as root directly
if [ "$EUID" -eq 0 ] && [ -z "$SUDO_USER" ]; then
    echo -e "${RED}${BOLD}[✗]${NC} Please run this script with sudo, not as root directly."
    exit 1
fi

# Check if makepkg.conf already exists
if check_makepkg_conf; then
    echo -ne "${YELLOW}${BOLD}[!]${NC} Existing makepkg.conf found. Do you want to reconfigure it? [y/N] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to optimize your makepkg configuration? [Y/n] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        echo -e "${YELLOW}${BOLD}[!]${NC} Configuration cancelled."
        exit 0
    fi
fi

# Backup existing configuration if it exists
backup_makepkg_conf

# Configure makepkg.conf
configure_makepkg

# Cleanup old backups (keep only last 5)
run_with_spinner "Cleaning up old backups" bash -c "
    ls -t '${REAL_HOME}/.makepkg.conf.backup-'* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
"

echo -e "\n${GREEN}${BOLD}[✓]${NC} Makepkg configuration has been optimized!" 