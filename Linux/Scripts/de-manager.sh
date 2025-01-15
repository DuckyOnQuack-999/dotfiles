#!/bin/bash

# Desktop Environment Manager Script
# This script helps manage and monitor desktop environments and window managers
# Author: AI Assistant
# Version: 1.0

# Color definitions for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display help menu
show_help() {
    echo -e "${BLUE}Desktop Environment Manager - Help Menu${NC}"
    echo "Usage: $0 [option]"
    echo "Options:"
    echo "  -l, --list         List all installed desktop environments and window managers"
    echo "  -c, --current      Show current running desktop environment/window manager"
    echo "  -b, --backup       Backup configurations for all environments"
    echo "  -i, --info         Show system information about current environment"
    echo "  -m, --memory       Show memory usage of current DE/WM"
    echo "  -k, --check        Check for common configuration issues"
    echo "  -h, --help         Show this help message"
}

# Function to list all installed desktop environments and window managers
list_environments() {
    echo -e "${BLUE}Installed Desktop Environments:${NC}"
    # Check common paths for .desktop files
    find /usr/share/xsessions /usr/share/wayland-sessions -name "*.desktop" 2>/dev/null | \
    while read -r session; do
        name=$(grep "^Name=" "$session" | cut -d= -f2)
        echo -e "${GREEN}→${NC} $name ($(basename "$session"))"
    done
}

# Function to show current desktop environment
show_current() {
    echo -e "${BLUE}Current Desktop Environment/Window Manager:${NC}"
    # Try multiple methods to detect current DE/WM
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        echo -e "${GREEN}→${NC} XDG_CURRENT_DESKTOP: $XDG_CURRENT_DESKTOP"
    elif [ -n "$DESKTOP_SESSION" ]; then
        echo -e "${GREEN}→${NC} DESKTOP_SESSION: $DESKTOP_SESSION"
    elif [ -n "$GDMSESSION" ]; then
        echo -e "${GREEN}→${NC} GDMSESSION: $GDMSESSION"
    else
        wmname=$(wmctrl -m 2>/dev/null | grep "Name:" | cut -d: -f2)
        if [ -n "$wmname" ]; then
            echo -e "${GREEN}→${NC} Window Manager: $wmname"
        else
            echo -e "${RED}Could not detect current desktop environment${NC}"
        fi
    fi
}

# Function to backup configurations
backup_configs() {
    backup_dir="$HOME/de-configs-backup-$(date +%Y%m%d-%H%M%S)"
    echo -e "${BLUE}Backing up configurations to: $backup_dir${NC}"
    
    mkdir -p "$backup_dir"
    
    # Backup common config directories
    configs=(
        ".config/plasma*"
        ".config/gnome*"
        ".config/xfce4"
        ".config/cinnamon"
        ".config/mate"
        ".config/sway"
        ".config/hypr"
        ".config/i3"
        ".config/awesome"
        ".config/qtile"
        ".config/bspwm"
        ".config/herbstluftwm"
    )

    for config in "${configs[@]}"; do
        if compgen -G "$HOME/$config" > /dev/null; then
            echo -e "${GREEN}→${NC} Backing up $config"
            cp -r "$HOME/$config" "$backup_dir/" 2>/dev/null
        fi
    done

    echo -e "${GREEN}Backup completed${NC}"
}

# Function to show system information
show_system_info() {
    echo -e "${BLUE}System Information:${NC}"
    echo -e "${GREEN}→${NC} OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo -e "${GREEN}→${NC} Kernel: $(uname -r)"
    echo -e "${GREEN}→${NC} Display Server: $XDG_SESSION_TYPE"
    echo -e "${GREEN}→${NC} Session Type: $XDG_SESSION_TYPE"
    echo -e "${GREEN}→${NC} Display: $DISPLAY"
    echo -e "${GREEN}→${NC} GPU Driver: $(glxinfo 2>/dev/null | grep "OpenGL vendor" | cut -d: -f2)"
}

# Function to show memory usage
show_memory_usage() {
    echo -e "${BLUE}Memory Usage for Desktop Environment Processes:${NC}"
    
    # Get current DE/WM name
    current_de=${XDG_CURRENT_DESKTOP:-$DESKTOP_SESSION}
    current_de_lower=$(echo "$current_de" | tr '[:upper:]' '[:lower:]')
    
    # Define process patterns based on DE/WM
    case "$current_de_lower" in
        *gnome*)
            pattern="gnome-shell|gdm|gnome-session"
            ;;
        *plasma*|*kde*)
            pattern="plasma|kwin|plasmashell"
            ;;
        *xfce*)
            pattern="xfce4|xfwm4"
            ;;
        *i3*)
            pattern="i3|i3bar"
            ;;
        *)
            pattern="$current_de_lower"
            ;;
    esac
    
    ps aux | grep -E "$pattern" | grep -v grep | \
        awk '{sum+=$6} END {printf "Total Memory Usage: %.2f MB\n", sum/1024}'
}

# Function to check for common issues
check_issues() {
    echo -e "${BLUE}Checking for Common Issues:${NC}"
    
    # Check if important processes are running
    echo -e "\n${GREEN}Checking Critical Processes:${NC}"
    for proc in dbus-daemon pulseaudio systemd-logind; do
        if pgrep -x "$proc" >/dev/null; then
            echo -e "${GREEN}✓${NC} $proc is running"
        else
            echo -e "${RED}✗${NC} $proc is not running"
        fi
    done
    
    # Check common config files
    echo -e "\n${GREEN}Checking Configuration Files:${NC}"
    for conf in ".xinitrc" ".xsession" ".Xresources"; do
        if [ -f "$HOME/$conf" ]; then
            echo -e "${GREEN}✓${NC} $conf exists"
        else
            echo -e "${RED}✗${NC} $conf is missing"
        fi
    done
    
    # Check for broken symlinks in config directories
    echo -e "\n${GREEN}Checking for Broken Symlinks in .config:${NC}"
    find "$HOME/.config" -xtype l 2>/dev/null | while read -r link; do
        echo -e "${RED}✗${NC} Broken symlink found: $link"
    done
}

# Main script logic
case "$1" in
    -l|--list)
        list_environments
        ;;
    -c|--current)
        show_current
        ;;
    -b|--backup)
        backup_configs
        ;;
    -i|--info)
        show_system_info
        ;;
    -m|--memory)
        show_memory_usage
        ;;
    -k|--check)
        check_issues
        ;;
    -h|--help)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac

exit 0

