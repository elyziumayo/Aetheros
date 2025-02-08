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

# Function to create AMD configuration
create_amd_config() {
    run_with_spinner "Creating AMD GPU configuration" bash -c "
        cat > /etc/modprobe.d/amdgpu.conf << \"EOF\"
# Force using of the amdgpu driver for Southern Islands (GCN 1.0+) and Sea Islands (GCN 2.x) generations
options amdgpu si_support=1 cik_support=1
options radeon si_support=0 cik_support=0
EOF
    "
}

# Function to create NVIDIA configuration
create_nvidia_config() {
    run_with_spinner "Creating NVIDIA GPU configuration" bash -c "
        cat > /etc/modprobe.d/nvidia.conf << \"EOF\"
# NVreg_UsePageAttributeTable=1 (Default 0)
# - Activates PAT for better memory management
# - Improves CPU performance through efficient memory architecture utilization

# NVreg_InitializeSystemMemoryAllocations=0 (Default 1)
# - Disables clearing system memory allocation before GPU use
# - Improves performance at the cost of security
# - Set to 1 for default secure behavior

# NVreg_DynamicPowerManagement=0x02
# - Enables dynamic power management for mobile GPUs
# - Allows dGPU power-down during idle

# NVreg_EnableGpuFirmware=0 (Default 1)
# - Disables GSP Firmware on closed source kernel modules
# - Ignored by open kernel modules

# nvidia_drm.modeset=1 (default 0)
# - Enables modesetting support
# - Required for Wayland and PRIME Offload

# NVreg_RegistryDwords=RMIntrLockingMode=1 (default 0)
# - Experimental frame-pacing improvement
# - Benefits high refresh rate monitors with VRR/VR

options nvidia NVreg_UsePageAttributeTable=1 \\
    NVreg_InitializeSystemMemoryAllocations=0 \\
    NVreg_DynamicPowerManagement=0x02 \\
    NVreg_EnableGpuFirmware=0 \\
    NVreg_RegistryDwords=RMIntrLockingMode=1
options nvidia_drm modeset=1
EOF
    "
}

# Function to create blacklist configuration
create_blacklist_config() {
    run_with_spinner "Creating hardware watchdog blacklist" bash -c "
        cat > /etc/modprobe.d/blacklist.conf << \"EOF\"
# Blacklist the Intel TCO Watchdog/Timer module
blacklist iTCO_wdt

# Blacklist the AMD SP5100 TCO Watchdog/Timer module (Required for Ryzen CPUs)
blacklist sp5100_tco
EOF
    "
}

# Function to verify configuration
verify_configuration() {
    run_with_spinner "Verifying configuration files" bash -c "
        errors=0
        
        # Check if blacklist configuration exists
        if [ ! -f \"/etc/modprobe.d/blacklist.conf\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Blacklist configuration not found\"
            errors=\$((errors+1))
        fi
        
        # Check if selected GPU configuration exists
        if [ \"\$1\" = \"nvidia\" ] && [ ! -f \"/etc/modprobe.d/nvidia.conf\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} NVIDIA configuration not found\"
            errors=\$((errors+1))
        elif [ \"\$1\" = \"amd\" ] && [ ! -f \"/etc/modprobe.d/amdgpu.conf\" ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} AMD configuration not found\"
            errors=\$((errors+1))
        fi
        
        if [ \"\$errors\" -gt 0 ]; then
            echo -e \"${RED}${BOLD}[✗]${NC} Some files were not created correctly\"
            exit 1
        fi
    "
}

# Function to update initramfs with loading animation
update_initramfs() {
    run_with_spinner "Updating initramfs" bash -c "
        # Run mkinitcpio for all presets
        if ! mkinitcpio -P >/dev/null 2>&1; then
            echo -e \"${RED}${BOLD}[✗]${NC} Failed to update initramfs\"
            exit 1
        fi
    "
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║        GPU Configuration Setup         ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[✗]${NC} This script must be run as root"
    exit 1
fi

# Initial prompt
echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to configure your GPU drivers? [Y/n] "
read -n 1 -r REPLY
echo
if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
    echo -e "${YELLOW}${BOLD}[!]${NC} GPU configuration cancelled."
    exit 0
fi

# Check for existing configuration
if [ -f "/etc/modprobe.d/nvidia.conf" ] || [ -f "/etc/modprobe.d/amdgpu.conf" ]; then
    echo -ne "${YELLOW}${BOLD}[!]${NC} Existing GPU configuration detected. Would you like to reconfigure? [y/N] "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Ask for GPU type
while true; do
    echo -e "\n${BLUE}${BOLD}[?]${NC} What type of GPU do you have?"
    echo -e "1) NVIDIA"
    echo -e "2) AMD"
    echo -ne "\nEnter your choice (1 or 2): "
    read -r choice
    
    case $choice in
        1)
            gpu_type="nvidia"
            break
            ;;
        2)
            gpu_type="amd"
            break
            ;;
        *)
            echo -e "${RED}${BOLD}[✗]${NC} Invalid choice. Please enter 1 or 2."
            ;;
    esac
done

echo -e "\n${BLUE}${BOLD}[i]${NC} Setting up GPU configuration..."

# Create configurations
create_blacklist_config

if [ "$gpu_type" = "nvidia" ]; then
    create_nvidia_config
else
    create_amd_config
fi

# Verify configuration
verify_configuration "$gpu_type"

# Update initramfs with loading animation
if ! update_initramfs; then
    echo -e "\n${RED}${BOLD}[✗]${NC} Configuration failed due to initramfs update error"
    exit 1
fi

echo -e "\n${GREEN}${BOLD}[✓]${NC} GPU configuration has been set up!"
echo -e "${BLUE}${BOLD}[i]${NC} Configuration has been applied and initramfs has been updated"
echo -e "${YELLOW}${BOLD}[!]${NC} Please reboot your system to apply the changes" 