#!/bin/bash

# Aetheros
# Author: elysiumayo
# Description: Master script to manage Arch Linux setup scripts

# Colors and styling
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Function to print styled headers
print_header() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔════════════════════════════════════════════╗"
    echo "║         Arch Linux Setup Manager           ║"
    echo "╚════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Function to print styled menu items
print_menu_item() {
    echo -e "${CYAN}[$1]${NC} ${BOLD}$2${NC}"
}

# Function to ensure sudo privileges and maintain them
ensure_sudo() {
    echo -e "${YELLOW}${BOLD}[INFO]${NC} Requesting sudo privileges..."
    sudo -v
    # Keep sudo privileges alive in the background
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done 2>/dev/null &
}

# Function to create scripts directory if it doesn't exist
ensure_scripts_dir() {
    if [ ! -d "scripts" ]; then
        echo -e "${YELLOW}${BOLD}[INFO]${NC} Creating scripts directory..."
        mkdir -p scripts
    fi
}

# Function to set execute permissions for all scripts
set_permissions() {
    echo -e "${YELLOW}${BOLD}[INFO]${NC} Setting execute permissions for scripts..."
    find scripts -type f -name "*.sh" -exec sudo chmod +x {} \;
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC} Permissions set successfully!"
    sleep 2
}

# Function to list all available scripts
list_scripts() {
    local scripts=(scripts/*.sh)
    if [ ${#scripts[@]} -eq 0 ] || [ ! -e "${scripts[0]}" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} No scripts found in the scripts directory!"
        echo -e "${YELLOW}[INFO]${NC} Please add your scripts to the 'scripts' directory."
        read -p "Press Enter to continue..."
        return
    fi

    echo -e "\n${PURPLE}${BOLD}Available Scripts:${NC}"
    local i=1
    for script in scripts/*.sh; do
        if [ -f "$script" ]; then
            echo -e "${CYAN}$i)${NC} $(basename "$script")"
            ((i++))
        fi
    done
    echo
    read -p "Press Enter to continue..."
}

# Function to run a specific script
run_script() {
    local scripts=(scripts/*.sh)
    if [ ${#scripts[@]} -eq 0 ] || [ ! -e "${scripts[0]}" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} No scripts found in the scripts directory!"
        read -p "Press Enter to continue..."
        return
    fi

    echo -e "\n${PURPLE}${BOLD}Select a script to run:${NC}"
    local i=1
    declare -A script_map
    for script in scripts/*.sh; do
        if [ -f "$script" ]; then
            echo -e "${CYAN}$i)${NC} $(basename "$script")"
            script_map[$i]=$script
            ((i++))
        fi
    done

    echo -e "\n${YELLOW}Enter the number of the script to run (or 0 to cancel):${NC}"
    read -r choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -gt 0 ] && [ "$choice" -lt "$i" ]; then
        selected_script="${script_map[$choice]}"
        echo -e "${YELLOW}${BOLD}[INFO]${NC} Running: $selected_script"
        sudo bash "$selected_script"
        echo -e "${GREEN}${BOLD}[SUCCESS]${NC} Script execution completed!"
        read -p "Press Enter to continue..."
    elif [ "$choice" != "0" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} Invalid selection!"
        read -p "Press Enter to continue..."
    fi
}

# Function to run all scripts
run_all_scripts() {
    local scripts=(scripts/*.sh)
    if [ ${#scripts[@]} -eq 0 ] || [ ! -e "${scripts[0]}" ]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} No scripts found in the scripts directory!"
        read -p "Press Enter to continue..."
        return
    fi

    echo -e "${YELLOW}${BOLD}[INFO]${NC} Running all scripts..."
    for script in scripts/*.sh; do
        if [ -f "$script" ]; then
            echo -e "\n${PURPLE}${BOLD}Executing:${NC} $(basename "$script")"
            sudo bash "$script"
        fi
    done
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC} All scripts executed successfully!"
    read -p "Press Enter to continue..."
}

# Main menu loop
main_menu() {
    while true; do
        print_header
        echo -e "${BOLD}Please select an option:${NC}\n"
        print_menu_item "1" "List Available Scripts"
        print_menu_item "2" "Run Specific Script"
        print_menu_item "3" "Run All Scripts"
        print_menu_item "4" "Set Script Permissions"
        print_menu_item "5" "Exit"
        echo

        read -p "Enter your choice (1-5): " choice
        echo

        case $choice in
            1) list_scripts ;;
            2) run_script ;;
            3) run_all_scripts ;;
            4) set_permissions ;;
            5) echo -e "${GREEN}${BOLD}Thank you for using Arch Linux Setup Manager!${NC}"
               exit 0 ;;
            *) echo -e "${RED}${BOLD}[ERROR]${NC} Invalid option. Please try again."
               sleep 2 ;;
        esac
    done
}

# Initial setup
print_header
ensure_sudo
ensure_scripts_dir
main_menu
