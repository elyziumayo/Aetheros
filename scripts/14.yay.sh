#!/bin/bash

# Colors and styling
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

# Get real user
REAL_USER="${SUDO_USER}"
if [ -z "$REAL_USER" ]; then
    error "Could not determine the real user"
fi

# Spinner function for visual feedback
spinner() {
    local pid=$1
    local msg="$2"
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    tput civis  # Hide cursor
    while kill -0 $pid 2>/dev/null; do
        for i in $(seq 0 9); do
            printf "\r${BLUE}${BOLD}[${spinstr:$i:1}]${NC} ${msg}   " # Added extra spaces to clear any residual output
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
    ("$@" > /dev/null 2>&1) &  # Redirect both stdout and stderr to /dev/null
    spinner $! "$msg"
}

# Function to handle errors
error() {
    echo -e "${RED}${BOLD}[✗]${NC} $1"
    exit 1
}

# Function to show info
info() {
    echo -e "${BLUE}${BOLD}[i]${NC} $1"
}

# Function to show warning
warning() {
    echo -e "${YELLOW}${BOLD}[!]${NC} $1"
}

# Function to show success
success() {
    echo -e "${GREEN}${BOLD}[✓]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
fi

# Clear screen and show header
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║         YAY AUR Helper Setup           ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}\n"

# Check current installation
if pacman -Qi yay &>/dev/null || pacman -Qi yay-bin &>/dev/null; then
    info "This script will reinstall the Yay AUR helper."
else
    info "This script will install the Yay AUR helper."
fi

# Prompt for confirmation
echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to proceed? [y/N] "
read -n 1 -r REPLY
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    warning "Operation cancelled by user"
    exit 0
fi

info "Setting up Yay AUR helper..."

# Install dependencies
if ! run_with_spinner "Installing dependencies" pacman -Sy --noconfirm --needed git base-devel go; then
    error "Failed to install dependencies"
fi

# Remove existing installations
if pacman -Qi yay &>/dev/null; then
    if ! run_with_spinner "Removing existing yay" bash -c "yes | pacman -Rdd --noconfirm yay || yes | pacman -Rns --noconfirm yay"; then
        warning "Could not remove existing yay installation cleanly, attempting to force remove..."
        if ! run_with_spinner "Force removing yay" bash -c "rm -f /usr/bin/yay && yes | pacman -Rdd --noconfirm yay 2>/dev/null || true"; then
            warning "Failed to remove yay completely, continuing anyway..."
        fi
    fi
fi

if pacman -Qi yay-bin &>/dev/null; then
    if ! run_with_spinner "Removing existing yay-bin" bash -c "yes | pacman -Rdd --noconfirm yay-bin || yes | pacman -Rns --noconfirm yay-bin"; then
        warning "Could not remove existing yay-bin installation cleanly, attempting to force remove..."
        if ! run_with_spinner "Force removing yay-bin" bash -c "rm -f /usr/bin/yay && yes | pacman -Rdd --noconfirm yay-bin 2>/dev/null || true"; then
            warning "Failed to remove yay-bin completely, continuing anyway..."
        fi
    fi
fi

# Prepare build directory
BUILD_DIR="/tmp/yay-build"
if ! run_with_spinner "Preparing build environment" bash -c "rm -rf '$BUILD_DIR' && mkdir -p '$BUILD_DIR' && chown '$REAL_USER:$(id -gn $REAL_USER)' '$BUILD_DIR'"; then
    error "Failed to prepare build environment"
fi

# Save current directory
ORIG_DIR=$(pwd)

# Clone repository
cd "$BUILD_DIR" || error "Failed to change to build directory"
if ! run_with_spinner "Cloning Yay repository" sudo -u "$REAL_USER" git clone --quiet https://aur.archlinux.org/yay.git .; then
    cd "$ORIG_DIR" || true
    error "Failed to clone yay repository"
fi

# Set up build permissions
if ! run_with_spinner "Setting up build permissions" bash -c "chown -R '$REAL_USER:$(id -gn $REAL_USER)' '$BUILD_DIR' && chmod -R u+rwX '$BUILD_DIR'"; then
    cd "$ORIG_DIR" || true
    error "Failed to set build permissions"
fi

# Set up temporary sudo rules
echo "$REAL_USER ALL=(ALL) NOPASSWD: /usr/bin/pacman" > /etc/sudoers.d/11-install-yay
echo "$REAL_USER ALL=(ALL) NOPASSWD: /usr/bin/yay" >> /etc/sudoers.d/11-install-yay
chmod 440 /etc/sudoers.d/11-install-yay

# Build package
if ! run_with_spinner "Building Yay package" sudo -u "$REAL_USER" bash -c 'cd "'$BUILD_DIR'" && makepkg -s --noconfirm --noprogressbar'; then
    rm -f /etc/sudoers.d/11-install-yay
    cd "$ORIG_DIR" || true
    error "Failed to build yay package"
fi

# Install package
if ! run_with_spinner "Installing Yay package" bash -c "yes | pacman -U --noconfirm '$BUILD_DIR'/yay-*.pkg.tar.zst"; then
    rm -f /etc/sudoers.d/11-install-yay
    cd "$ORIG_DIR" || true
    error "Failed to install yay package"
fi

# Clean up
cd "$ORIG_DIR" || true
rm -rf "$BUILD_DIR"

# Verify installation
if ! pacman -Qi yay &>/dev/null; then
    rm -f /etc/sudoers.d/11-install-yay
    error "Installation verification failed"
fi

# Configure yay
HOME_DIR=$(eval echo ~"$REAL_USER")
if ! run_with_spinner "Configuring yay" bash -c "
    # Create yay config directory
    mkdir -p '$HOME_DIR/.config/yay'
    chown -R '$REAL_USER:$(id -gn $REAL_USER)' '$HOME_DIR/.config/yay'
    
    # Write yay configuration directly
    cat > '$HOME_DIR/.config/yay/config.json' << EOF
{
    \"answerclean\": \"All\",
    \"answerdiff\": \"None\",
    \"answeredit\": \"None\",
    \"cleanafter\": true,
    \"sudoflags\": \"-S\",
    \"sudoloop\": true
}
EOF
    chown '$REAL_USER:$(id -gn $REAL_USER)' '$HOME_DIR/.config/yay/config.json'
"; then
    rm -f /etc/sudoers.d/11-install-yay
    warning "Failed to configure yay, but installation was successful"
fi

# Clean up sudo rules
rm -f /etc/sudoers.d/11-install-yay

# Show success message
echo
success "Yay has been installed successfully!"
info "You can now use yay to install packages from the AUR"
warning "Example usage: yay -S package-name"
echo
