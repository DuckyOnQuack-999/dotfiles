#!/bin/bash

# Colors and styles
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'
NC='\033[0m'

# Modern UI Icons
ICON_CHECK="✓"
ICON_WARN="⚠️"
ICON_ERROR="❌"
ICON_PACKAGE="📦"
ICON_SYSTEM="🖥️"
ICON_BACKUP="💾"
ICON_UPDATE="🔄"
ICON_CLEANUP="🧹"
ICON_NETWORK="🌐"
ICON_CONFIG="⚙️"
ICON_GPU="🎮"
ICON_CPU="⚡"
ICON_RAM="🧠"
ICON_DISK="💿"
ICON_DESKTOP="🖥️"
ICON_KERNEL="🐧"
ICON_COMPLETE="🎉"

# Configuration
BACKUP_DIR="$HOME/.config/system_backups/$(date +%Y%m%d_%H%M%S)"
IMPORTANT_CONFIGS=(
    "$HOME/.config/hypr"
    "$HOME/.config/kde"
    "$HOME/.config/environment.d"
    "$HOME/.config/plasma-workspace"
    "$HOME/.config/kwinrc"
    "$HOME/.config/waybar"
    "$HOME/.config/wlogout"
    "/etc/X11/xorg.conf.d"
)
# Log file and error tracking
LOG_FILE="$HOME/update_log_$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG="$HOME/update_errors_$(date +%Y%m%d_%H%M%S).log"
BACKUP_LOG="$HOME/backup_log_$(date +%Y%m%d_%H%M%S).log"

# Enhanced logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $timestamp - $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $timestamp - $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $timestamp - $message" | tee -a "$ERROR_LOG" ;;
        *)       echo -e "$timestamp - $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Function to handle errors
handle_error() {
    local error_msg="$1"
    local error_code="$2"
    log_message "ERROR" "$error_msg (Code: $error_code)"
    echo -e "${RED}${ICON_ERROR} Error: $error_msg${NC}"
    
    case "$error_code" in
        "PACMAN_ERROR")
            echo -e "${YELLOW}Attempting to fix pacman database...${NC}"
            sudo rm -f /var/lib/pacman/db.lck
            sudo pacman -Syy
            ;;
        "NETWORK_ERROR")
            echo -e "${YELLOW}Checking network configuration...${NC}"
            systemctl restart NetworkManager
            sleep 2
            ;;
        *)
            echo -e "${YELLOW}Unknown error occurred${NC}"
            ;;
    esac
}
# Enhanced command checker
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_message "WARN" "Command not found: $1"
        return 1
    fi
    return 0
}

# Enhanced network connectivity check
check_network() {
    echo -e "\n${CYAN}${ICON_NETWORK} Checking network connectivity...${NC}"
    local timeout=5
    if ! ping -c 1 -W $timeout 8.8.8.8 &> /dev/null; then
        if ! ping -c 1 -W $timeout 1.1.1.1 &> /dev/null; then
            handle_error "No internet connection detected" "NETWORK_ERROR"
            return 1
        fi
    fi
    echo -e "${GREEN}${ICON_CHECK} Network connection established${NC}"
    return 0
}

# Function to detect and configure environment
detect_environment() {
    echo -e "\n${CYAN}${ICON_SYSTEM} Detecting system environment...${NC}"
    
    # Session type detection
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        WAYLAND=1
        log_message "INFO" "Wayland session detected"
        echo -e "${GREEN}${ICON_CHECK} Wayland session detected${NC}"
        
        # Hyprland detection
        if pgrep -x "Hyprland" >/dev/null; then
            HYPRLAND=1
            log_message "INFO" "Hyprland compositor detected"
            echo -e "${GREEN}${ICON_CHECK} Hyprland compositor detected${NC}"
        fi
    else
        X11=1
        log_message "INFO" "X11 session detected"
        echo -e "${GREEN}${ICON_CHECK} X11 session detected${NC}"
    fi

    # Desktop environment detection
    if pgrep -x "plasmashell" >/dev/null; then
        KDE=1
        log_message "INFO" "KDE Plasma detected"
        echo -e "${GREEN}${ICON_CHECK} KDE Plasma detected${NC}"
    fi
}

# Function to check system resources
check_system_resources() {
    echo -e "\n${CYAN}${ICON_SYSTEM} Checking system resources...${NC}"
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    echo -e "${BLUE}${ICON_CPU} CPU Usage: ${cpu_usage}%${NC}"
    
    # RAM usage
    local ram_total=$(free -m | awk '/Mem:/ {print $2}')
    local ram_used=$(free -m | awk '/Mem:/ {print $3}')
    local ram_percent=$(awk "BEGIN {printf \"%.1f\", $ram_used/$ram_total*100}")
    echo -e "${BLUE}${ICON_RAM} RAM Usage: ${ram_percent}%${NC}"
    
    # Disk space
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    echo -e "${BLUE}${ICON_DISK} Disk Usage: ${disk_usage}%${NC}"
    
    if [ "$disk_usage" -gt 90 ]; then
        log_message "WARN" "Low disk space detected: ${disk_usage}%"
        echo -e "${YELLOW}${ICON_WARN} Warning: Low disk space!${NC}"
    fi
}
# Modern progress bar function
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    printf "\r${BLUE}["
    printf "%${filled}s" | tr ' ' '▓'
    printf "%${empty}s" | tr ' ' '░'
    printf "]${NC} %3d%%" $percentage
}

# System resource monitor
monitor_resources() {
    local pid=$1
    while ps -p $pid > /dev/null; do
        local cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
        local mem=$(free -m | awk '/Mem:/ {printf "%.1f", $3/$2 * 100}')
        local disk=$(df -h / | awk 'NR==2 {print $5}')
        printf "\r${CYAN}${ICON_CPU} CPU: %5s%% ${ICON_RAM} RAM: %5s%% ${ICON_DISK} Disk: %s${NC}" "$cpu" "$mem" "$disk"
        sleep 1
    done
    printf "\r%*s\r" 80 ""
}

# Backup configuration files
backup_configs() {
    echo -e "\n${BLUE}${ICON_BACKUP} Backing up system configurations...${NC}"
    mkdir -p "$BACKUP_DIR"
    
    local total=${#IMPORTANT_CONFIGS[@]}
    local current=0
    
    for config in "${IMPORTANT_CONFIGS[@]}"; do
        ((current++))
        if [ -e "$config" ]; then
            show_progress $current $total
            cp -r "$config" "$BACKUP_DIR/" 2>/dev/null
            log_message "INFO" "Backed up: $config"
        fi
    done
    echo -e "\n${GREEN}${ICON_CHECK} Backups completed: $BACKUP_DIR${NC}"
}

# Check GPU drivers and status
check_gpu_drivers() {
    echo -e "\n${CYAN}${ICON_GPU} Checking GPU configuration...${NC}"
    
    # NVIDIA
    if lspci | grep -i nvidia >/dev/null; then
        echo -e "${BLUE}NVIDIA GPU detected${NC}"
        if ! pacman -Qs nvidia >/dev/null; then
            log_message "WARN" "NVIDIA GPU detected but drivers not installed"
            echo -e "${YELLOW}${ICON_WARN} NVIDIA drivers not installed${NC}"
        else
            local nvidia_version=$(pacman -Qi nvidia | grep Version | awk '{print $3}')
            echo -e "${GREEN}${ICON_CHECK} NVIDIA drivers installed (v$nvidia_version)${NC}"
        fi
    fi
    
    # AMD
    if lspci | grep -i amd >/dev/null; then
        echo -e "${BLUE}AMD GPU detected${NC}"
        if ! pacman -Qs mesa >/dev/null; then
            log_message "WARN" "AMD GPU detected but mesa not installed"
            echo -e "${YELLOW}${ICON_WARN} Mesa drivers not installed${NC}"
        else
            local mesa_version=$(pacman -Qi mesa | grep Version | awk '{print $3}')
            echo -e "${GREEN}${ICON_CHECK} Mesa drivers installed (v$mesa_version)${NC}"
        fi
    fi
}

# Print fancy header
echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       ${BOLD}System-Wide Update Manager v3.0${NC}${BLUE}              ║${NC}"
echo -e "${BLUE}║       ${DIM}Modern Update Solution for Manjaro${NC}${BLUE}           ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"

# System information header
echo -e "\n${CYAN}${ICON_SYSTEM} System Information:${NC}"
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}• Kernel:${NC} $(uname -r)"
echo -e "${BLUE}• Architecture:${NC} $(uname -m)"
echo -e "${BLUE}• Hostname:${NC} $(hostname)"
echo -e "${BLUE}• User:${NC} $USER"

# Start logging
log_message "Starting system update process"

# Check for root privileges
if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}Don't run this script as root/sudo directly${NC}"
    exit 1
fi

# Check network connectivity
echo -e "\n${YELLOW}Checking network connectivity...${NC}"
check_network

# Backup reminder
echo -e "\n${YELLOW}⚠️  Reminder: Consider backing up important data before proceeding${NC}"
read -p "Press Enter to continue or Ctrl+C to cancel..."

# System health check
echo -e "\n${BLUE}Performing system health check...${NC}"
df -h / | tail -n 1 | awk '{ print $5 }' | cut -d'%' -f1 | {
    read usage
    if [ "$usage" -gt 90 ]; then
        echo -e "${RED}Warning: Low disk space! ($usage% used)${NC}"
        read -p "Continue anyway? (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

    log_message "Starting system package updates"
    echo -e "\n${CYAN}${ICON_PACKAGE} Updating system packages...${NC}"

    # Start resource monitoring in background
    monitor_resources $$ &
    monitor_pid=$!

    if ! sudo pacman -Syu --noconfirm; then
        kill $monitor_pid 2>/dev/null
        handle_error "System package update failed" "PACMAN_ERROR"
        exit 1
    fi

    kill $monitor_pid 2>/dev/null
    echo -e "${GREEN}${ICON_CHECK} System packages updated successfully${NC}"
# Update AUR packages with progress monitoring
if check_command yay; then
    echo -e "\n${CYAN}${ICON_PACKAGE} Updating AUR packages (yay)...${NC}"
    log_message "Updating AUR packages using yay"
    monitor_resources $$ &
    monitor_pid=$!
    if ! yay -Sua --noconfirm; then
        kill $monitor_pid 2>/dev/null
        handle_error "AUR update failed" "AUR_ERROR"
    fi
    kill $monitor_pid 2>/dev/null
    echo -e "${GREEN}${ICON_CHECK} AUR packages updated successfully${NC}"
elif check_command paru; then
    echo -e "\n${CYAN}${ICON_PACKAGE} Updating AUR packages (paru)...${NC}"
    log_message "Updating AUR packages using paru"
    monitor_resources $$ &
    monitor_pid=$!
    if ! paru -Sua --noconfirm; then
        kill $monitor_pid 2>/dev/null
        handle_error "AUR update failed" "AUR_ERROR"
    fi
    kill $monitor_pid 2>/dev/null
    echo -e "${GREEN}${ICON_CHECK} AUR packages updated successfully${NC}"
fi

# Update Flatpak packages with progress monitoring
if check_command flatpak; then
    echo -e "\n${CYAN}${ICON_PACKAGE} Updating Flatpak packages...${NC}"
    log_message "Updating Flatpak packages"
    monitor_resources $$ &
    monitor_pid=$!
    if ! flatpak update -y; then
        kill $monitor_pid 2>/dev/null
        handle_error "Flatpak update failed" "FLATPAK_ERROR"
    else
        flatpak uninstall --unused -y
    fi
    kill $monitor_pid 2>/dev/null
    echo -e "${GREEN}${ICON_CHECK} Flatpak packages updated successfully${NC}"
fi

# Update Snap packages
if check_command snap; then
    echo -e "\n${GREEN}📦 Updating Snap packages...${NC}"
    log_message "Updating Snap packages"
    sudo snap refresh
fi

# System cleanup with enhanced visualization
echo -e "\n${CYAN}${ICON_CLEANUP} Performing system cleanup...${NC}"
log_message "Starting system cleanup"

# Clean package cache with progress
echo -e "${BLUE}${ICON_PACKAGE} Cleaning package cache...${NC}"
cache_size_before=$(du -sh /var/cache/pacman/pkg | cut -f1)
if sudo pacman -Sc --noconfirm; then
    cache_size_after=$(du -sh /var/cache/pacman/pkg | cut -f1)
    log_message "Package cache cleaned (Before: $cache_size_before, After: $cache_size_after)"
    echo -e "${GREEN}${ICON_CHECK} Package cache cleaned ($cache_size_before → $cache_size_after)${NC}"
fi

# Remove orphaned packages with details
echo -e "${BLUE}${ICON_PACKAGE} Checking for orphaned packages...${NC}"
if orphans=$(pacman -Qtdq); then
    orphan_count=$(echo "$orphans" | wc -l)
    echo -e "${YELLOW}Found $orphan_count orphaned packages${NC}"
    if sudo pacman -Rns $(pacman -Qtdq) --noconfirm; then
        log_message "$orphan_count orphaned packages removed"
        echo -e "${GREEN}${ICON_CHECK} Orphaned packages removed successfully${NC}"
    fi
else
    echo -e "${GREEN}${ICON_CHECK} No orphaned packages found${NC}"
fi

# Clean journal logs older than 7 days
# Journal cleanup with size reporting
echo -e "${BLUE}${ICON_CLEANUP} Cleaning system journals...${NC}"
journal_size_before=$(du -sh /var/log/journal 2>/dev/null | cut -f1)
if sudo journalctl --vacuum-time=7d; then
    journal_size_after=$(du -sh /var/log/journal 2>/dev/null | cut -f1)
    log_message "Journal logs cleaned (Before: $journal_size_before, After: $journal_size_after)"
    echo -e "${GREEN}${ICON_CHECK} Journal cleaned ($journal_size_before → $journal_size_after)${NC}"
fi

# Comprehensive system verification
echo -e "\n${CYAN}${ICON_SYSTEM} Performing final system verification...${NC}"

# Check system services
echo -e "${BLUE}${ICON_CONFIG} Verifying system services...${NC}"
failed_services=$(systemctl --failed)
if echo "$failed_services" | grep -q "0 loaded units listed"; then
    echo -e "${GREEN}${ICON_CHECK} All system services are running normally${NC}"
else
    echo -e "${RED}${ICON_ERROR} Failed services detected:${NC}"
    echo "$failed_services" | grep "failed" | sed 's/^/  /'
    log_message "ERROR" "Failed system services detected"
fi

# Verify Wayland/Hyprland status if applicable
if [ "$WAYLAND" = "1" ]; then
    echo -e "${BLUE}${ICON_DESKTOP} Verifying Wayland components...${NC}"
    if [ "$HYPRLAND" = "1" ]; then
        if pgrep -x "Hyprland" >/dev/null; then
            echo -e "${GREEN}${ICON_CHECK} Hyprland is running properly${NC}"
        else
            echo -e "${YELLOW}${ICON_WARN} Hyprland service state inconsistent${NC}"
        fi
        
        # Check Hyprland-specific components
        for comp in "waybar" "wlogout" "hyprctl"; do
            if command -v $comp >/dev/null; then
                echo -e "${GREEN}${ICON_CHECK} $comp is available${NC}"
            else
                echo -e "${YELLOW}${ICON_WARN} $comp not found${NC}"
            fi
        done
    fi
fi

# Update complete
echo -e "\n${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         System Update Complete! ${ICON_COMPLETE}          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"

# Detailed Summary
echo -e "\n${CYAN}${ICON_SYSTEM} Update Summary:${NC}"
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}• Update Time:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BLUE}• System Status:${NC} $(systemctl is-system-running)"
echo -e "${BLUE}• Desktop Environment:${NC} $([[ "$KDE" = "1" ]] && echo "KDE Plasma" || echo "Other")"
echo -e "${BLUE}• Display Server:${NC} $([[ "$WAYLAND" = "1" ]] && echo "Wayland" || echo "X11")"
echo -e "${BLUE}• Compositor:${NC} $([[ "$HYPRLAND" = "1" ]] && echo "Hyprland" || echo "Other")"
echo -e "${BLUE}• Kernel Version:${NC} $(uname -r)"
echo -e "${BLUE}• Log Files:${NC}"
echo -e "  - Main Log: $LOG_FILE"
echo -e "  - Error Log: $ERROR_LOG"
echo -e "  - Backup Log: $BACKUP_LOG"

# Reboot recommendation if kernel was updated
# Smart reboot detection
echo -e "\n${CYAN}${ICON_SYSTEM} Checking for pending updates...${NC}"
reboot_needed=0

# Check kernel updates
if [ -f "/usr/lib/modules/$(uname -r)/vmlinuz" ]; then
    if ! pacman -Q linux | grep -q "$(uname -r)"; then
        echo -e "${YELLOW}${ICON_KERNEL} Kernel update detected${NC}"
        reboot_needed=1
        log_message "Kernel update detected"
    fi
fi

# Check for Wayland/Hyprland updates
if [ "$WAYLAND" = "1" ]; then
    if [ "$HYPRLAND" = "1" ] && pacman -Qqu | grep -q "^hyprland"; then
        echo -e "${YELLOW}${ICON_DESKTOP} Hyprland update detected${NC}"
        reboot_needed=1
        log_message "Hyprland update detected"
    fi
fi

# Check for graphics driver updates
if pacman -Qqu | grep -qE "^nvidia|^mesa"; then
    echo -e "${YELLOW}${ICON_GPU} Graphics driver update detected${NC}"
    reboot_needed=1
    log_message "Graphics driver update detected"
fi

# Display reboot recommendation
if [ $reboot_needed -eq 1 ]; then
    echo -e "\n${YELLOW}${ICON_WARN} System reboot is recommended to apply the following updates:${NC}"
    [ -n "$(pacman -Qqu | grep "^linux")" ] && echo -e "  ${ICON_KERNEL} Kernel updates"
    [ -n "$(pacman -Qqu | grep "^hyprland")" ] && echo -e "  ${ICON_DESKTOP} Hyprland updates"
    [ -n "$(pacman -Qqu | grep -E "^nvidia|^mesa")" ] && echo -e "  ${ICON_GPU} Graphics driver updates"
else
    echo -e "\n${GREEN}${ICON_CHECK} No reboot required${NC}"
fi

log_message "Update process completed successfully"
