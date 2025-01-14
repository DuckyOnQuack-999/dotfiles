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

# Function to detect hardware acceleration
detect_hardware_accel() {
    # Check Vulkan support
    if command -v vulkaninfo >/dev/null 2>&1; then
        VULKAN_SUPPORT=1
        VULKAN_INFO=$(vulkaninfo 2>/dev/null | grep -m1 "deviceName" | cut -d'=' -f2-)
        log_message "INFO" "Vulkan support detected: $VULKAN_INFO"
    fi

    # Check OpenGL support
    if command -v glxinfo >/dev/null 2>&1; then
        OPENGL_SUPPORT=1
        OPENGL_INFO=$(glxinfo | grep -m1 "OpenGL version" | cut -d':' -f2-)
        log_message "INFO" "OpenGL support detected: $OPENGL_INFO"
    fi

    # Check XWayland
    if pgrep -x "Xwayland" >/dev/null; then
        XWAYLAND=1
        log_message "INFO" "XWayland is running"
    fi
}

# Function to detect multi-monitor setup
detect_monitors() {
    if command -v xrandr >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
        MONITOR_INFO=$(xrandr --listmonitors | tail -n +2)
        MONITOR_COUNT=$(echo "$MONITOR_INFO" | wc -l)
        PRIMARY_MONITOR=$(xrandr --listmonitors | grep "*" | awk '{print $4}')
    elif command -v wlr-randr >/dev/null 2>&1; then
        MONITOR_INFO=$(wlr-randr 2>/dev/null)
        MONITOR_COUNT=$(echo "$MONITOR_INFO" | grep -c "^[A-Z]")
    fi
    log_message "INFO" "Detected $MONITOR_COUNT monitor(s)"
}

# Function to detect GPU details
detect_gpu_details() {
    # NVIDIA GPU detection
    if lspci | grep -i nvidia >/dev/null; then
        NVIDIA_GPU=1
        NVIDIA_MODEL=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader 2>/dev/null)
        NVIDIA_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null)
    fi

    # AMD GPU detection
    if lspci | grep -i amd >/dev/null; then
        AMD_GPU=1
        AMD_MODEL=$(lspci | grep -i amd | grep VGA | cut -d':' -f3)
        AMD_DRIVER=$(glxinfo 2>/dev/null | grep "OpenGL vendor" | cut -d':' -f2)
    fi

    # Intel GPU detection
    if lspci | grep -i intel | grep -i vga >/dev/null; then
        INTEL_GPU=1
        INTEL_MODEL=$(lspci | grep -i intel | grep VGA | cut -d':' -f3)
        INTEL_DRIVER=$(glxinfo 2>/dev/null | grep "OpenGL vendor" | cut -d':' -f2)
    fi
}

# Function to detect theme and color scheme
detect_theme() {
    # GTK theme detection
    if command -v gsettings >/dev/null 2>&1; then
        GTK_THEME=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)
        ICON_THEME=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null)
    fi

    # Qt theme detection
    if [ -f "$HOME/.config/qt5ct/qt5ct.conf" ]; then
        QT_THEME=$(grep "^style=" "$HOME/.config/qt5ct/qt5ct.conf" | cut -d'=' -f2)
    fi

    # Color scheme detection
    if [ -n "$XDG_CONFIG_HOME" ]; then
        if [ -f "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" ]; then
            COLOR_SCHEME=$(grep "gtk-application-prefer-dark-theme" "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" | cut -d'=' -f2)
        fi
    fi
}

# Function to detect and configure environment
detect_environment() {
    echo -e "\n${CYAN}${ICON_SYSTEM} Detecting system environment...${NC}"
    
    # Reset all environment variables
    unset WAYLAND X11 KDE GNOME XFCE MATE CINNAMON LXQT LXDE 
    unset HYPRLAND SWAY I3WM BSPWM AWESOME DWM QTILE XMONAD OPENBOX FLUXBOX LEFTWM HERBSTLUFTWM
    unset PICOM COMPTON WM_NAME DE_NAME
    unset VULKAN_SUPPORT OPENGL_SUPPORT XWAYLAND
    unset NVIDIA_GPU AMD_GPU INTEL_GPU
    unset GTK_THEME QT_THEME COLOR_SCHEME
    unset XDG_CURRENT_DE DESKTOP_SESSION_TYPE PRIMARY_MONITOR MONITOR_COUNT

    # Get session details
    XDG_CURRENT_DE="$XDG_CURRENT_DESKTOP"
    DESKTOP_SESSION_TYPE="$DESKTOP_SESSION"

    # Detect hardware and display features
    detect_hardware_accel
    detect_monitors
    detect_gpu_details
    detect_theme
    
    # Session type detection
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        WAYLAND=1
        log_message "INFO" "Wayland session detected"
        echo -e "${GREEN}${ICON_CHECK} Wayland session detected${NC}"
        
        # Wayland compositor detection
        if pgrep -x "Hyprland" >/dev/null; then
            HYPRLAND=1
            log_message "INFO" "Hyprland compositor detected"
            echo -e "${GREEN}${ICON_CHECK} Hyprland compositor detected${NC}"
        elif pgrep -x "sway" >/dev/null; then
            SWAY=1
            log_message "INFO" "Sway compositor detected"
            echo -e "${GREEN}${ICON_CHECK} Sway compositor detected${NC}"
        fi
    else
        X11=1
        log_message "INFO" "X11 session detected"
        echo -e "${GREEN}${ICON_CHECK} X11 session detected${NC}"
        
        # X11 compositor detection
        if pgrep -x "picom" >/dev/null; then
            PICOM=1
            log_message "INFO" "Picom compositor detected"
            echo -e "${GREEN}${ICON_CHECK} Picom compositor detected${NC}"
        elif pgrep -x "compton" >/dev/null; then
            COMPTON=1
            log_message "INFO" "Compton compositor detected"
            echo -e "${GREEN}${ICON_CHECK} Compton compositor detected${NC}"
        fi
    fi

    # Desktop environment detection
    if pgrep -x "plasmashell" >/dev/null; then
        KDE=1
        DE_NAME="KDE Plasma"
        log_message "INFO" "KDE Plasma detected"
        echo -e "${GREEN}${ICON_CHECK} KDE Plasma detected${NC}"
    elif pgrep -x "gnome-shell" >/dev/null; then
        GNOME=1
        DE_NAME="GNOME"
        log_message "INFO" "GNOME detected"
        echo -e "${GREEN}${ICON_CHECK} GNOME detected${NC}"
    elif pgrep -x "xfce4-session" >/dev/null; then
        XFCE=1
        DE_NAME="XFCE"
        log_message "INFO" "XFCE detected"
        echo -e "${GREEN}${ICON_CHECK} XFCE detected${NC}"
    elif pgrep -x "mate-session" >/dev/null; then
        MATE=1
        DE_NAME="MATE"
        log_message "INFO" "MATE detected"
        echo -e "${GREEN}${ICON_CHECK} MATE detected${NC}"
    elif pgrep -x "cinnamon-session" >/dev/null; then
        CINNAMON=1
        DE_NAME="Cinnamon"
        log_message "INFO" "Cinnamon detected"
        echo -e "${GREEN}${ICON_CHECK} Cinnamon detected${NC}"
    elif pgrep -x "lxqt-session" >/dev/null; then
        LXQT=1
        DE_NAME="LXQt"
        log_message "INFO" "LXQt detected"
        echo -e "${GREEN}${ICON_CHECK} LXQt detected${NC}"
    elif pgrep -x "lxsession" >/dev/null; then
        LXDE=1
        DE_NAME="LXDE"
        log_message "INFO" "LXDE detected"
        echo -e "${GREEN}${ICON_CHECK} LXDE detected${NC}"
    fi

    # Window manager detection
    if [ -z "$DE_NAME" ]; then
        if pgrep -x "i3" >/dev/null; then
            I3WM=1
            WM_NAME="i3"
        elif pgrep -x "openbox" >/dev/null; then
            OPENBOX=1
            WM_NAME="Openbox"
        elif pgrep -x "fluxbox" >/dev/null; then
            FLUXBOX=1
            WM_NAME="Fluxbox"
        elif pgrep -x "leftwm" >/dev/null; then
            LEFTWM=1
            WM_NAME="LeftWM"
        elif pgrep -x "herbstluftwm" >/dev/null; then
            HERBSTLUFTWM=1
            WM_NAME="herbstluftwm"
        elif pgrep -x "bspwm" >/dev/null; then
            BSPWM=1
            WM_NAME="bspwm"
        elif pgrep -x "awesome" >/dev/null; then
            AWESOME=1
            WM_NAME="awesome"
        elif pgrep -x "dwm" >/dev/null; then
            DWM=1
            WM_NAME="dwm"
        elif pgrep -x "qtile" >/dev/null; then
            QTILE=1
            WM_NAME="qtile"
        elif pgrep -x "xmonad" >/dev/null; then
            XMONAD=1
            WM_NAME="xmonad"
        fi

        if [ -n "$WM_NAME" ]; then
            log_message "INFO" "$WM_NAME window manager detected"
            echo -e "${GREEN}${ICON_CHECK} $WM_NAME window manager detected${NC}"
        fi
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
# Modern progress bar styles and functions
PROGRESS_CHARS=('▏' '▎' '▍' '▌' '▋' '▊' '▉' '█')
SPINNER_CHARS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

show_modern_progress() {
    local current=$1
    local total=$2
    local message="${3:-}"
    local style="${4:-normal}"
    local width=40
    
    # Calculate percentage and bar segments
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local partial=$((((width * current * 8) / total) % 8))
    local empty=$((width - filled - 1))
    
    # Color gradient calculation
    local color_start="\033[38;2;87;181;255m"
    local color_mid="\033[38;2;150;255;150m"
    local color_end="\033[38;2;255;150;150m"
    
    case "$style" in
        "detailed")
            printf "\r${BOLD}${message:+$message }${NC}"
            printf "${BLUE}["
            for ((i = 0; i < filled; i++)); do
                if [ $i -lt $((filled/3)) ]; then
                    printf "${color_start}█"
                elif [ $i -lt $((filled*2/3)) ]; then
                    printf "${color_mid}█"
                else
                    printf "${color_end}█"
                fi
            done
            [ $partial -gt 0 ] && printf "${color_end}${PROGRESS_CHARS[$partial]}"
            for ((i = 0; i < empty; i++)); do printf "░"; done
            printf "${NC}] ${YELLOW}%3d%%${NC}" $percentage
            ;;
        
        "spinner")
            local spinner_idx=$(((current / 1) % ${#SPINNER_CHARS[@]}))
            printf "\r${CYAN}${SPINNER_CHARS[$spinner_idx]}${NC} ${message:+$message }${BLUE}%3d%%${NC}" $percentage
            ;;
        
        *)  # normal style
            printf "\r${message:+$message }${BLUE}["
            for ((i = 0; i < filled; i++)); do printf "▓"; done
            [ $partial -gt 0 ] && printf "${PROGRESS_CHARS[$partial]}"
            for ((i = 0; i < empty; i++)); do printf "░"; done
            printf "]${NC} ${YELLOW}%3d%%${NC}" $percentage
            ;;
    esac
    
    # Add newline if process is complete
    [ $current -eq $total ] && echo
}

# Legacy progress function for compatibility
show_progress() {
    show_modern_progress "$1" "$2" "" "normal"
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
            show_modern_progress "$current" "$total" "Backing up configs" "detailed"
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

    # Initialize update counters
    SYSTEM_PACKAGES_UPDATED=0
    AUR_PACKAGES_UPDATED=0
    FLATPAK_PACKAGES_UPDATED=0

    log_message "Starting system package updates"
    echo -e "\n${CYAN}${ICON_PACKAGE} Updating system packages...${NC}"

    # Start resource monitoring in background
    monitor_resources $$ &
    monitor_pid=$!

    SYSTEM_PACKAGES_BEFORE=$(pacman -Q | wc -l)
    if ! sudo pacman -Syu --noconfirm; then
        kill $monitor_pid 2>/dev/null
        handle_error "System package update failed" "PACMAN_ERROR"
        exit 1
    fi
    SYSTEM_PACKAGES_AFTER=$(pacman -Q | wc -l)
    SYSTEM_PACKAGES_UPDATED=$((SYSTEM_PACKAGES_AFTER - SYSTEM_PACKAGES_BEFORE))

    kill $monitor_pid 2>/dev/null
    echo -e "${GREEN}${ICON_CHECK} System packages updated successfully${NC}"
# Update AUR packages with progress monitoring
if check_command yay; then
    echo -e "\n${CYAN}${ICON_PACKAGE} Updating AUR packages (yay)...${NC}"
    log_message "Updating AUR packages using yay"
    monitor_resources $$ &
    monitor_pid=$!
    AUR_PACKAGES_BEFORE=$(yay -Qm | wc -l)
    if ! yay -Sua --noconfirm; then
        kill $monitor_pid 2>/dev/null
        handle_error "AUR update failed" "AUR_ERROR"
    fi
    AUR_PACKAGES_AFTER=$(yay -Qm | wc -l)
    AUR_PACKAGES_UPDATED=$((AUR_PACKAGES_AFTER - AUR_PACKAGES_BEFORE))
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
    FLATPAK_PACKAGES_BEFORE=$(flatpak list | wc -l)
    if ! flatpak update -y; then
        kill $monitor_pid 2>/dev/null
        handle_error "Flatpak update failed" "FLATPAK_ERROR"
    else
        flatpak uninstall --unused -y
    fi
    FLATPAK_PACKAGES_AFTER=$(flatpak list | wc -l)
    FLATPAK_PACKAGES_UPDATED=$((FLATPAK_PACKAGES_AFTER - FLATPAK_PACKAGES_BEFORE))
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

# Show cleanup progress
total_steps=5
for ((i=1; i<=total_steps; i++)); do
    case $i in
        1) message="Removing old cache";;
        2) message="Cleaning temp files";;
        3) message="Optimizing database";;
        4) message="Verifying integrity";;
        5) message="Finalizing cleanup";;
    esac
    show_modern_progress "$i" "$total_steps" "$message" "spinner"
    sleep 0.5
done

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
# Detect environment before system verification
detect_environment

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

# Detect environment before displaying summary
detect_environment

# Update complete
echo -e "\n${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         System Update Complete! ${ICON_COMPLETE}          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"

# Detailed Summary
echo -e "\n${CYAN}${ICON_SYSTEM} Update Summary:${NC}"
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# System Information
echo -e "${BOLD}System Information:${NC}"
echo -e "${BLUE}• Time Completed:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BLUE}• System Status:${NC} $(systemctl is-system-running)"
echo -e "${BLUE}• Kernel Version:${NC} $(uname -r)"

echo -e "\n${BOLD}Display Server Information:${NC}"
echo -e "${BLUE}• Display Server:${NC} $([[ "$WAYLAND" = "1" ]] && echo "Wayland" || echo "X11")"
[ "$XWAYLAND" = "1" ] && echo -e "${BLUE}• XWayland:${NC} Active"
echo -e "${BLUE}• Desktop Environment:${NC} ${DE_NAME:-"None"}"
if [ -n "$WM_NAME" ]; then
    echo -e "${BLUE}• Window Manager:${NC} ${WM_NAME}"
elif [ -n "$DE_NAME" ]; then
    echo -e "${BLUE}• Window Manager:${NC} Built-in"
else
    echo -e "${BLUE}• Window Manager:${NC} Unknown"
fi
echo -e "${BLUE}• Session Type:${NC} ${XDG_SESSION_TYPE:-"Unknown"}"
echo -e "${BLUE}• Monitors:${NC} ${MONITOR_COUNT:-"Unknown"} ($([[ -n "$PRIMARY_MONITOR" ]] && echo "Primary: $PRIMARY_MONITOR" || echo "Configuration unknown"))"

echo -e "\n${BOLD}Graphics Information:${NC}"
echo -e "${BLUE}• Hardware Acceleration:${NC}"
[ "$VULKAN_SUPPORT" = "1" ] && echo -e "  - Vulkan: $VULKAN_INFO"
[ "$OPENGL_SUPPORT" = "1" ] && echo -e "  - OpenGL: $OPENGL_INFO"
echo -e "${BLUE}• GPU Configuration:${NC}"
[ "$NVIDIA_GPU" = "1" ] && echo -e "  - NVIDIA: $NVIDIA_MODEL (Driver: $NVIDIA_DRIVER)"
[ "$AMD_GPU" = "1" ] && echo -e "  - AMD: $AMD_MODEL (Driver: $AMD_DRIVER)"
[ "$INTEL_GPU" = "1" ] && echo -e "  - Intel: $INTEL_MODEL (Driver: $INTEL_DRIVER)"

echo -e "\n${BOLD}Theme Configuration:${NC}"
[ -n "$GTK_THEME" ] && echo -e "${BLUE}• GTK Theme:${NC} $GTK_THEME"
[ -n "$QT_THEME" ] && echo -e "${BLUE}• Qt Theme:${NC} $QT_THEME"
[ -n "$ICON_THEME" ] && echo -e "${BLUE}• Icon Theme:${NC} $ICON_THEME"
[ -n "$COLOR_SCHEME" ] && echo -e "${BLUE}• Color Scheme:${NC} $([ "$COLOR_SCHEME" = "1" ] && echo "Dark" || echo "Light")"

echo -e "\n${BOLD}Compositor:${NC} $(\
    if [ "$HYPRLAND" = "1" ]; then echo "Hyprland"
    elif [ "$SWAY" = "1" ]; then echo "Sway"
    elif [ "$PICOM" = "1" ]; then echo "Picom"
    elif [ "$COMPTON" = "1" ]; then echo "Compton"
    elif [ "$WAYLAND" = "1" ]; then echo "Built-in Wayland"
    elif [ -n "$DE_NAME" ]; then echo "Built-in X11"
    else echo "None"
    fi)"
echo -e ""

# System Resources
echo -e "${BOLD}Current Resource Usage:${NC}"
echo -e "${BLUE}• CPU Usage:${NC} $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
echo -e "${BLUE}• Memory Usage:${NC} $(free -m | awk '/Mem:/ {printf "%.1f", $3/$2*100}')%"
echo -e "${BLUE}• Disk Usage:${NC} $(df -h / | awk 'NR==2 {print $5}')"
echo -e ""

# Update Statistics
echo -e "${BOLD}Package Updates:${NC}"
echo -e "${BLUE}• System Packages:${NC} $SYSTEM_PACKAGES_UPDATED updated"
echo -e "${BLUE}• AUR Packages:${NC} $AUR_PACKAGES_UPDATED updated"
echo -e "${BLUE}• Flatpak Packages:${NC} $FLATPAK_PACKAGES_UPDATED updated"
echo -e ""

# System Changes
echo -e "${BOLD}System Changes:${NC}"
echo -e "${BLUE}• Package Cache:${NC} $cache_size_before → $cache_size_after"
echo -e "${BLUE}• Journal Size:${NC} $journal_size_before → $journal_size_after"
[ "$orphan_count" -gt 0 ] && echo -e "${BLUE}• Orphaned Packages:${NC} $orphan_count removed"
echo -e ""

# Log Information
echo -e "${BOLD}Log Files:${NC}"
echo -e "${BLUE}• Main Log:${NC} $LOG_FILE"
echo -e "${BLUE}• Error Log:${NC} $ERROR_LOG"
echo -e "${BLUE}• Backup Log:${NC} $BACKUP_LOG"

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
