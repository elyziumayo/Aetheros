#!/bin/bash

# Colors and styling
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

# Get real user's home directory and username
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo ~$REAL_USER)
DOTFILES_REPO="https://github.com/elysiumayo/Arch-dotfiles.git"
DOTFILES_DIR="${REAL_HOME}/Arch-dotfiles"

# Function to run git commands as real user
git_clone_as_user() {
    sudo -u "$REAL_USER" git clone "$1" "$2"
}

# Main script
clear
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║        Dotfiles Installation           ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════╝${NC}\n"

# Initial prompt
echo -ne "${BLUE}${BOLD}[?]${NC} Would you like to clone your dotfiles? [Y/n] "
read -n 1 -r REPLY
echo

if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Operation cancelled."
    exit 1
fi

# Remove existing dotfiles directory if it exists
if [ -d "$DOTFILES_DIR" ]; then
    echo -e "${YELLOW}${BOLD}[!]${NC} Removing existing dotfiles directory..."
    sudo -u "$REAL_USER" rm -rf "$DOTFILES_DIR"
fi

# Clone the repository
echo -e "${BLUE}${BOLD}[i]${NC} Cloning dotfiles repository..."
if git_clone_as_user "$DOTFILES_REPO" "$DOTFILES_DIR"; then
    echo -e "${GREEN}${BOLD}[✓]${NC} Dotfiles cloned successfully!"
    # Fix ownership
    chown -R "$REAL_USER:$(id -gn $REAL_USER)" "$DOTFILES_DIR"
else
    echo -e "${RED}${BOLD}[✗]${NC} Failed to clone dotfiles"
    exit 1
fi 
