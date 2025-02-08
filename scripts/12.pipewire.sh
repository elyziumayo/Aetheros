#!/bin/bash

# Colors and styling
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

# Get real user's home directory and runtime directory
REAL_HOME=$(eval echo ~${SUDO_USER})
RUNTIME_DIR="/run/user/$(id -u ${SUDO_USER})"

# Function to run command as real user
run_as_user() {
    local cmd="$1"
    DBUS_SESSION_BUS_ADDRESS="unix:path=${RUNTIME_DIR}/bus" \
    XDG_RUNTIME_DIR="${RUNTIME_DIR}" \
    sudo -u "${SUDO_USER}" -E bash -c "$cmd"
}

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

# Function to detect maximum sample rate
detect_sample_rate() {
    local max_rate=48000
    local rates=$(run_as_user "pactl list sinks 2>/dev/null | grep 'Sample Specification' -B 2")
    
    if echo "$rates" | grep -q "192000"; then
        max_rate=192000
    elif echo "$rates" | grep -q "96000"; then
        max_rate=96000
    fi
    
    echo "$max_rate"
}

# Function to remove existing PipeWire configuration
remove_existing_config() {
    # First remove packages silently
    yes | pacman -Rdd --noconfirm pipewire pipewire-pulse pipewire-jack lib32-pipewire gst-plugin-pipewire wireplumber realtime-privileges &>/dev/null || true

    run_with_spinner "Removing existing PipeWire" bash -c "
        # Stop and disable services
        run_as_user \"systemctl --user stop pipewire.socket pipewire.service pipewire-pulse.service wireplumber.service\" &>/dev/null || true
        run_as_user \"systemctl --user disable pipewire.socket pipewire.service pipewire-pulse.service wireplumber.service\" &>/dev/null || true

        # Kill processes
        pkill -9 pipewire &>/dev/null || true
        pkill -9 wireplumber &>/dev/null || true

        # Remove configuration directories
        rm -rf /etc/pipewire /etc/wireplumber \"${REAL_HOME}/.config/pipewire\" \"${REAL_HOME}/.config/wireplumber\" &>/dev/null || true

        # Verify removal
        if [ -d \"${REAL_HOME}/.config/pipewire\" ] || [ -d \"/etc/pipewire\" ]; then
            echo \"Failed to remove all PipeWire configurations\" >&2
            exit 1
        fi
    "
}

# Function to install required packages
install_packages() {
    run_with_spinner "Installing PipeWire" bash -c '
        pacman -Sy --noconfirm &>/dev/null
        yes | pacman -S --noconfirm --needed --overwrite "*" \
            pipewire pipewire-pulse pipewire-jack lib32-pipewire \
            gst-plugin-pipewire wireplumber realtime-privileges \
            alsa-lib alsa-utils alsa-firmware alsa-card-profiles alsa-plugins &>/dev/null
    '
}

# Function to configure realtime privileges
configure_realtime() {
    run_with_spinner "Configuring realtime privileges" bash -c "gpasswd -a ${SUDO_USER} realtime &>/dev/null"
}

# Function to create PipeWire configuration
create_pipewire_config() {
    # Define run_as_user function for the subshell
    local run_as_user_cmd='run_as_user() {
        local cmd="$1"
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u '${SUDO_USER}')/bus" \
        XDG_RUNTIME_DIR="/run/user/$(id -u '${SUDO_USER}')" \
        sudo -u "'${SUDO_USER}'" -E bash -c "$cmd"
    }'

    # Create configuration directories first
    run_with_spinner "Creating PipeWire directories" bash -c "
        ${run_as_user_cmd}
        run_as_user \"mkdir -p ${REAL_HOME}/.config/pipewire/pipewire.conf.d\"
        run_as_user \"mkdir -p ${REAL_HOME}/.config/pipewire/pipewire-pulse.conf.d\"
        run_as_user \"mkdir -p ${REAL_HOME}/.config/pipewire/client-rt.conf.d\"
    "

    # Create the configuration file
    local config_file="${REAL_HOME}/.config/pipewire/pipewire.conf.d/10-sound.conf"
    run_with_spinner "Creating PipeWire configuration" bash -c "
        ${run_as_user_cmd}
        cat > /tmp/pipewire-config.tmp << 'EOF'
context.properties = {
    default.clock.rate = 48000
    default.clock.allowed-rates = [ 44100 48000 88200 96000 ]
    default.clock.min-quantum = 16
    default.clock.quantum = 4096
    default.clock.max-quantum = 8192
}
EOF
        run_as_user \"cp /tmp/pipewire-config.tmp '${config_file}'\"
        rm -f /tmp/pipewire-config.tmp

        # Configure 5.1 upmixing if available
        if [ -f /usr/share/pipewire/client-rt.conf.avail/20-upmix.conf ]; then
            run_as_user \"cp '/usr/share/pipewire/client-rt.conf.avail/20-upmix.conf' '${REAL_HOME}/.config/pipewire/pipewire-pulse.conf.d/'\"
            run_as_user \"cp '/usr/share/pipewire/client-rt.conf.avail/20-upmix.conf' '${REAL_HOME}/.config/pipewire/client-rt.conf.d/'\"
        fi

        # Verify configuration
        if [ ! -f '${config_file}' ]; then
            echo 'Failed to create PipeWire configuration' >&2
            exit 1
        fi
    "
}

# Function to enable PipeWire services
enable_services() {
    # Define run_as_user function for the subshell
    local run_as_user_cmd='run_as_user() {
        local cmd="$1"
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u '${SUDO_USER}')/bus" \
        XDG_RUNTIME_DIR="/run/user/$(id -u '${SUDO_USER}')" \
        sudo -u "'${SUDO_USER}'" -E bash -c "$cmd"
    }'

    run_with_spinner "Enabling PipeWire services" bash -c "
        ${run_as_user_cmd}
        # First reload daemon
        run_as_user \"systemctl --user daemon-reload\" || exit 1
        
        # Then enable and start services
        run_as_user \"systemctl --user enable --now pipewire.socket\" || exit 1
        run_as_user \"systemctl --user enable --now pipewire.service\" || exit 1
        run_as_user \"systemctl --user enable --now pipewire-pulse.service\" || exit 1
        run_as_user \"systemctl --user enable --now wireplumber.service\" || exit 1
        
        # Wait for services to start
        sleep 2
    "
}

# Function to verify setup
verify_setup() {
    # Define run_as_user function for the subshell
    local run_as_user_cmd='run_as_user() {
        local cmd="$1"
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u '${SUDO_USER}')/bus" \
        XDG_RUNTIME_DIR="/run/user/$(id -u '${SUDO_USER}')" \
        sudo -u "'${SUDO_USER}'" -E bash -c "$cmd"
    }'

    run_with_spinner "Verifying PipeWire setup" bash -c "
        ${run_as_user_cmd}
        # Check if services are running
        if ! run_as_user \"systemctl --user is-active pipewire.service\" &>/dev/null; then
            echo 'PipeWire service is not running' >&2
            exit 1
        fi
        if ! run_as_user \"systemctl --user is-active wireplumber.service\" &>/dev/null; then
            echo 'Wireplumber service is not running' >&2
            exit 1
        fi
    "
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║     PipeWire Audio Configuration       ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run with sudo"
    exit 1
fi

# Check if SUDO_USER is set
if [ -z "$SUDO_USER" ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run with sudo, not as root directly"
    exit 1
fi

# Check for existing installation
if check_package_installed "pipewire" || [ -d "${REAL_HOME}/.config/pipewire" ]; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Existing PipeWire installation detected"
fi

# Single prompt for all cases
echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to configure PipeWire for low latency audio? [Y/n] "
read -n 1 -r REPLY
echo
if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Setup cancelled."
    exit 0
fi

echo -e "\n${BLUE}${BOLD}[i]${NC} Setting up PipeWire..."

# Remove existing installation if present
if check_package_installed "pipewire" || [ -d "${REAL_HOME}/.config/pipewire" ]; then
    remove_existing_config
fi

# Install packages
install_packages

# Configure realtime privileges
configure_realtime

# Create PipeWire configuration
create_pipewire_config

# Enable services
enable_services

# Verify setup
verify_setup

echo -e "\n${GREEN}${BOLD}[✓]${NC} PipeWire has been configured successfully!"
echo -e "${YELLOW}${BOLD}[!]${NC} Please reboot your system for all changes to take effect" 
