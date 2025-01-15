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
METRICS_DIR="$HOME/.local/share/system_metrics"
JSON_LOG="$HOME/.local/share/update_logs/updates.json"
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

# Enhanced logging function with JSON support
log_message() {
    local level="$1"
    local message="$2"
    local component="${3:-system}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Standard log output
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $timestamp - $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $timestamp - $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $timestamp - $message" | tee -a "$ERROR_LOG" ;;
        *)       echo -e "$timestamp - $message" | tee -a "$LOG_FILE" ;;
    esac
    
    # JSON structured logging
    mkdir -p "$(dirname "$JSON_LOG")"
    local json_entry=$(printf '{"timestamp":"%s","level":"%s","component":"%s","message":"%s"}\n' \
        "$timestamp" "$level" "$component" "$message")
    echo "$json_entry" >> "$JSON_LOG"
}

# Component evaluation function
evaluate_component() {
    local component="$1"
    local detailed="${2:-false}"
    echo -e "\n${BLUE}${ICON_CONFIG} Evaluating component: $component${NC}"
    
    # Get component status
    local status="unknown"
    local version=""
    local cpu_usage=""
    local mem_usage=""
    
    # Check if component is running
    if pgrep -x "$component" >/dev/null; then
        status="running"
        pid=$(pgrep -x "$component")
        cpu_usage=$(ps -p $pid -o %cpu --no-headers)
        mem_usage=$(ps -p $pid -o %mem --no-headers)
        version=$(pacman -Q "$component" 2>/dev/null | awk '{print $2}')
    fi
    
    # Create detailed report
    local report="Status: $status"
    [ -n "$version" ] && report="$report\nVersion: $version"
    [ -n "$cpu_usage" ] && report="$report\nCPU Usage: $cpu_usage%"
    [ -n "$mem_usage" ] && report="$report\nMemory Usage: $mem_usage%"
    
    # Log component state
    log_message "INFO" "Component $component evaluation: $status" "$component"
    
    if [ "$detailed" = "true" ]; then
        echo -e "$report"
    else
        echo -e "Component $component is $status"
    fi
    
    return $([ "$status" = "running" ] && echo 0 || echo 1)
}

# Dependency analysis function
analyze_dependencies() {
    local component="$1"
    echo -e "\n${BLUE}${ICON_PACKAGE} Analyzing dependencies for: $component${NC}"
    
    # Get direct dependencies
    local deps=$(pacman -Qi "$component" 2>/dev/null | grep "Depends On" | cut -d: -f2-)
    
    # Check each dependency
    echo -e "${CYAN}Dependencies:${NC}"
    for dep in $deps; do
        if pacman -Qi "$dep" &>/dev/null; then
            local version=$(pacman -Q "$dep" | awk '{print $2}')
            echo -e "${GREEN}${ICON_CHECK} $dep: $version${NC}"
        else
            echo -e "${RED}${ICON_ERROR} $dep: Not installed${NC}"
            log_message "ERROR" "Missing dependency: $dep" "$component"
        fi
    done
}

# Component verification function
verify_component() {
    local component="$1"
    echo -e "\n${BLUE}${ICON_CONFIG} Verifying component: $component${NC}"
    
    # Create snapshot
    local snapshot_dir="$BACKUP_DIR/$component"
    mkdir -p "$snapshot_dir"
    
    # Check configuration files
    if [ -d "/etc/$component" ]; then
        cp -r "/etc/$component" "$snapshot_dir/"
        echo -e "${GREEN}${ICON_BACKUP} Configuration snapshot created${NC}"
    fi
    
    # Check for conflicts
    local conflicts=$(pacman -Qc "$component" 2>/dev/null)
    if [ -n "$conflicts" ]; then
        echo -e "${YELLOW}${ICON_WARN} Potential conflicts detected:${NC}"
        echo "$conflicts"
        log_message "WARN" "Package conflicts detected for $component" "$component"
    fi
    
    # Verify integrity
    if pacman -Qk "$component" &>/dev/null; then
        echo -e "${GREEN}${ICON_CHECK} Package integrity verified${NC}"
    else
        echo -e "${RED}${ICON_ERROR} Package integrity check failed${NC}"
        log_message "ERROR" "Integrity check failed for $component" "$component"
    fi
}

# Component error handler
handle_component_error() {
    local component="$1"
    local error_type="$2"
    local error_msg="$3"
    
    echo -e "\n${RED}${ICON_ERROR} Error in component $component: $error_msg${NC}"
    log_message "ERROR" "$error_msg" "$component"
    
    case "$error_type" in
        "crash")
            echo -e "${YELLOW}Attempting to restart $component...${NC}"
            systemctl --user restart "$component" 2>/dev/null || \
            systemctl restart "$component" 2>/dev/null
            ;;
        "config")
            echo -e "${YELLOW}Attempting to restore configuration from backup...${NC}"
            if [ -d "$BACKUP_DIR/$component" ]; then
                sudo cp -r "$BACKUP_DIR/$component"/* "/etc/$component/"
            fi
            ;;
        "dependency")
            echo -e "${YELLOW}Attempting to reinstall dependencies...${NC}"
            analyze_dependencies "$component"
            sudo pacman -S --needed "$component"
            ;;
        *)
            echo -e "${YELLOW}Unknown error type. Manual intervention required.${NC}"
            ;;
    esac
}

# Performance monitoring function
monitor_component() {
    local component="$1"
    local pid=$(pgrep -x "$component")
    mkdir -p "$METRICS_DIR"
    
    while [ -e /proc/$pid ]; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local cpu=$(ps -p $pid -o %cpu --no-headers)
        local mem=$(ps -p $pid -o %mem --no-headers)
        local threads=$(ps -p $pid -o nlwp --no-headers)
        
        # Store metrics
        echo "$timestamp,$cpu,$mem,$threads" >> "$METRICS_DIR/${component}_metrics.csv"
        
        # Real-time display
        printf "\r${CYAN}%s${NC} - CPU: %5s%% MEM: %5s%% Threads: %3s" \
            "$component" "$cpu" "$mem" "$threads"
        
        sleep 1
    done
    printf "\n"
}

# Function to check process status
check_process() {
    local process_name="$1"
    local friendly_name="${2:-$1}"
    if pgrep -x "$process_name" >/dev/null; then
        echo -e "${GREEN}${ICON_CHECK} $friendly_name is running${NC}"
        return 0
    else
        echo -e "${YELLOW}${ICON_WARN} $friendly_name is not running${NC}"
        log_message "WARN" "$friendly_name is not running"
        return 1
    fi
}

# Function to check systemd status
check_systemd_errors() {
    echo -e "\n${BLUE}${ICON_CONFIG} Checking systemd status...${NC}"
    local systemd_errors=$(journalctl -p 3..0 -b | grep -i "failed\|error" | tail -n 5)
    local failed_units=$(systemctl --failed --no-legend)
    local user_failed_units=$(systemctl --user --failed --no-legend)
    
    if [ -n "$systemd_errors" ] || [ -n "$failed_units" ] || [ -n "$user_failed_units" ]; then
        echo -e "${YELLOW}${ICON_WARN} System service issues detected:${NC}"
        [ -n "$systemd_errors" ] && echo -e "\nRecent systemd errors:\n$systemd_errors"
        [ -n "$failed_units" ] && echo -e "\nFailed system units:\n$failed_units"
        [ -n "$user_failed_units" ] && echo -e "\nFailed user units:\n$user_failed_units"
        return 1
    fi
    echo -e "${GREEN}${ICON_CHECK} No systemd errors detected${NC}"
    return 0
}

# Function to check system performance
check_system_stats() {
    echo -e "\n${BLUE}${ICON_SYSTEM} Checking system statistics...${NC}"
    
    # CPU load
    local cpu_load=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1)
    echo -e "CPU Load: $cpu_load"
    
    # Memory usage
    echo -e "\nMemory Usage:"
    free -h | grep -v + | sed 's/^/  /'
    
    # Disk usage
    echo -e "\nDisk Usage:"
    df -h / /home 2>/dev/null | sed 's/^/  /'
    
    # Network stats
    echo -e "\nNetwork Interfaces:"
    ip -br addr | grep -v '^lo' | sed 's/^/  /'
}

# Function to check security status
check_security_status() {
    echo -e "\n${BLUE}${ICON_CONFIG} Checking security status...${NC}"
    
    # Check SSH
    if [ -f "/etc/ssh/sshd_config" ]; then
        echo -e "SSH Configuration:"
        grep -E "^Port|^PermitRootLogin|^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | sed 's/^/  /'
    fi
    
    # Check running services
    echo -e "\nPotentially sensitive services:"
    systemctl list-units --type=service --state=running | grep -E "ftp|telnet|vnc|rdp" | sed 's/^/  /'
    
    # Check last logins
    echo -e "\nRecent logins:"
    last -n 5 | sed 's/^/  /'
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

# Comprehensive System Health Check
echo -e "\n${CYAN}${ICON_SYSTEM} Performing comprehensive system health check...${NC}"
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Network interfaces and connections
echo -e "\n${BLUE}${ICON_NETWORK} Checking network interfaces...${NC}"
if ip link show | grep -v "lo:" >/dev/null; then
    echo -e "${GREEN}${ICON_CHECK} Network interfaces detected${NC}"
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo"); do
        if ip addr show $iface | grep -q "inet "; then
            echo -e "  ${GREEN}• $iface: Connected${NC}"
        else
            echo -e "  ${YELLOW}• $iface: Disconnected${NC}"
            log_message "WARN" "Network interface $iface is disconnected"
        fi
    done
else
    echo -e "${RED}${ICON_ERROR} No network interfaces found${NC}"
    log_message "ERROR" "No network interfaces detected"
fi

# Storage health check (SMART)
echo -e "\n${BLUE}${ICON_DISK} Checking storage health...${NC}"
if command -v smartctl >/dev/null; then
    for drive in $(lsblk -d -n -o NAME | grep -E '^sd|^nvme'); do
        echo -e "Checking /dev/$drive:"
        if sudo smartctl -H /dev/$drive | grep -q "PASSED"; then
            echo -e "  ${GREEN}${ICON_CHECK} SMART status: HEALTHY${NC}"
        else
            echo -e "  ${RED}${ICON_ERROR} SMART status: FAILING${NC}"
            log_message "ERROR" "SMART check failed for /dev/$drive"
        fi
    done
else
    echo -e "${YELLOW}${ICON_WARN} smartctl not installed - skipping SMART checks${NC}"
fi

# Temperature monitoring
echo -e "\n${BLUE}${ICON_CPU} Checking system temperatures...${NC}"
if command -v sensors >/dev/null; then
    temp_data=$(sensors)
    cpu_temp=$(echo "$temp_data" | grep -i "Core 0:" | awk '{print $3}' | tr -d '+°C')
    if [ -n "$cpu_temp" ]; then
        if [ "${cpu_temp%.*}" -gt 80 ]; then
            echo -e "  ${RED}• CPU Temperature: ${cpu_temp}°C (HIGH)${NC}"
            log_message "WARN" "High CPU temperature detected: ${cpu_temp}°C"
        else
            echo -e "  ${GREEN}• CPU Temperature: ${cpu_temp}°C${NC}"
        fi
    fi
    
    # GPU temperature check
    if command -v nvidia-smi >/dev/null; then
        gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader)
        if [ -n "$gpu_temp" ]; then
            if [ "$gpu_temp" -gt 80 ]; then
                echo -e "  ${RED}• GPU Temperature: ${gpu_temp}°C (HIGH)${NC}"
                log_message "WARN" "High GPU temperature detected: ${gpu_temp}°C"
            else
                echo -e "  ${GREEN}• GPU Temperature: ${gpu_temp}°C${NC}"
            fi
        fi
    fi
else
    echo -e "${YELLOW}${ICON_WARN} sensors not installed - skipping temperature checks${NC}"
fi

# Systemd user services status
echo -e "\n${BLUE}${ICON_CONFIG} Checking systemd user services...${NC}"
failed_services=$(systemctl --user list-units --state=failed --no-legend)
if [ -n "$failed_services" ]; then
    echo -e "${RED}${ICON_ERROR} Failed user services detected:${NC}"
    echo "$failed_services" | awk '{print "  • " $1 " - " $2}'
    log_message "ERROR" "Failed user services detected"
else
    echo -e "${GREEN}${ICON_CHECK} All user services are running normally${NC}"
fi

# Audio system check
echo -e "\n${BLUE}${ICON_CONFIG} Checking audio system...${NC}"
if pgrep -x "pipewire" >/dev/null; then
    echo -e "${GREEN}${ICON_CHECK} PipeWire is running${NC}"
    if pactl info >/dev/null 2>&1; then
        echo -e "  ${GREEN}• PulseAudio interface is active${NC}"
    else
        echo -e "  ${YELLOW}• PulseAudio interface is not responding${NC}"
        log_message "WARN" "PulseAudio interface not responding"
    fi
else
    echo -e "${RED}${ICON_ERROR} PipeWire is not running${NC}"
    log_message "ERROR" "Audio system (PipeWire) is not running"
fi

# Flatpak system check
if command -v flatpak >/dev/null; then
    echo -e "\n${BLUE}${ICON_PACKAGE} Checking Flatpak system...${NC}"
    if flatpak list --runtime | grep -q "org.freedesktop.Platform"; then
        echo -e "${GREEN}${ICON_CHECK} Flatpak base runtime is installed${NC}"
    else
        echo -e "${YELLOW}${ICON_WARN} Flatpak base runtime missing${NC}"
        log_message "WARN" "Flatpak base runtime is not installed"
    fi
fi

# Firewall configuration
echo -e "\n${BLUE}${ICON_CONFIG} Checking firewall status...${NC}"
if command -v ufw >/dev/null; then
    if sudo ufw status | grep -q "Status: active"; then
        echo -e "${GREEN}${ICON_CHECK} UFW firewall is active${NC}"
    else
        echo -e "${YELLOW}${ICON_WARN} UFW firewall is inactive${NC}"
        log_message "WARN" "Firewall is inactive"
    fi
elif command -v firewall-cmd >/dev/null; then
    if sudo firewall-cmd --state | grep -q "running"; then
        echo -e "${GREEN}${ICON_CHECK} FirewallD is active${NC}"
    else
        echo -e "${YELLOW}${ICON_WARN} FirewallD is inactive${NC}"
        log_message "WARN" "Firewall is inactive"
    fi
fi

# Bluetooth status
echo -e "\n${BLUE}${ICON_CONFIG} Checking Bluetooth status...${NC}"
if systemctl is-active bluetooth >/dev/null 2>&1; then
    echo -e "${GREEN}${ICON_CHECK} Bluetooth service is active${NC}"
    if bluetoothctl show | grep -q "Powered: yes"; then
        echo -e "  ${GREEN}• Bluetooth adapter is powered on${NC}"
    else
        echo -e "  ${YELLOW}• Bluetooth adapter is powered off${NC}"
    fi
else
    echo -e "${YELLOW}${ICON_WARN} Bluetooth service is not running${NC}"
fi

# Power management
echo -e "\n${BLUE}${ICON_CONFIG} Checking power management...${NC}"
if command -v tlp >/dev/null; then
    if systemctl is-active tlp >/dev/null 2>&1; then
        echo -e "${GREEN}${ICON_CHECK} TLP power management is active${NC}"
    else
        echo -e "${YELLOW}${ICON_WARN} TLP is installed but not active${NC}"
    fi
else
    echo -e "${YELLOW}${ICON_WARN} TLP is not installed${NC}"
fi

# System security checks
echo -e "\n${BLUE}${ICON_CONFIG} Performing security checks...${NC}"
# Check failed login attempts
failed_logins=$(journalctl -u systemd-logind -b | grep "Failed password" | wc -l)
if [ "$failed_logins" -gt 0 ]; then
    echo -e "${YELLOW}${ICON_WARN} Detected $failed_logins failed login attempts${NC}"
    log_message "WARN" "Multiple failed login attempts detected"
else
    echo -e "${GREEN}${ICON_CHECK} No failed login attempts${NC}"
fi

# Check active SSH sessions
ssh_sessions=$(who | grep pts | wc -l)
if [ "$ssh_sessions" -gt 0 ]; then
    echo -e "${YELLOW}${ICON_WARN} $ssh_sessions active SSH session(s)${NC}"
    who | grep pts | awk '{print "  • Connection from: " $5}'
else
    echo -e "${GREEN}${ICON_CHECK} No active SSH sessions${NC}"
fi

echo -e "\n${CYAN}${ICON_SYSTEM} System health check complete${NC}"
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Disk space check
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

# Check Window Manager and Desktop Status
echo -e "${CYAN}${ICON_DESKTOP} Verifying Window Manager status...${NC}"

# Function to check process status
check_system_process() {
    local process_name="$1"
    local friendly_name="${2:-$1}"
    local optional="${3:-false}"
    
    if pgrep -x "$process_name" >/dev/null; then
        echo -e "${GREEN}${ICON_CHECK} $friendly_name is running${NC}"
        return 0
    else
        if [ "$optional" = "true" ]; then
            echo -e "${YELLOW}${ICON_WARN} Optional: $friendly_name is not running${NC}"
            log_message "WARN" "Optional process $friendly_name is not running"
        else
            echo -e "${RED}${ICON_ERROR} Required: $friendly_name is not running${NC}"
            log_message "ERROR" "Required process $friendly_name is not running"
        fi
        return 1
    fi
}

# Optimized function to check desktop environment status
check_desktop_environment_status() {
    local session_type="$XDG_SESSION_TYPE"
    local de_type=""
    
    # Detect session and DE type
    if [ "$session_type" = "wayland" ]; then
        de_type="wayland"
        [ -n "$(pgrep -x Hyprland)" ] && de_type="hyprland"
        [ -n "$(pgrep -x sway)" ] && de_type="sway"
    else
        [ -n "$(pgrep -x plasmashell)" ] && de_type="kde"
        [ -n "$(pgrep -x gnome-shell)" ] && de_type="gnome"
        [ -n "$(pgrep -x xfce4-session)" ] && de_type="xfce"
    fi
    
    echo -e "\n${BLUE}${ICON_DESKTOP} Checking desktop environment ($de_type)...${NC}"
    
    case "$de_type" in
        "hyprland")
            check_system_process "Hyprland" "Hyprland Compositor"
            check_system_process "waybar" "Waybar"
            check_system_process "dunst" "Dunst" "true"
            check_system_process "polkit-gnome-au" "Polkit" "true"
            ;;
        "kde")
            check_system_process "plasmashell" "Plasma Shell"
            check_system_process "kwin_x11" "KWin" "true"
            check_system_process "kwin_wayland" "KWin Wayland" "true"
            ;;
        *)
            echo -e "${YELLOW}${ICON_WARN} Unknown or unsupported desktop environment${NC}"
            ;;
    esac
}
# Check Hyprland and critical components

# Function to check package installation
check_package() {
    local pkg_name="$1"
    if pacman -Qi "$pkg_name" &>/dev/null; then
        echo -e "${GREEN}${ICON_CHECK} $pkg_name is installed${NC}"
        return 0
    else
        echo -e "${YELLOW}${ICON_WARN} $pkg_name is not installed${NC}"
        log_message "WARN" "Missing package: $pkg_name"
        return 1
    fi
}

# Check compositor-related errors in journal
echo -e "\n${BLUE}${ICON_CONFIG} Checking compositor logs...${NC}"
compositor_errors=$(journalctl -b | grep -i "compositor\|wayland\|hyprland" | grep -i "error\|fail" | tail -n 5)
if [ -n "$compositor_errors" ]; then
    echo -e "${YELLOW}${ICON_WARN} Recent compositor-related errors found:${NC}"
    echo "$compositor_errors" | sed 's/^/  /'
    log_message "WARN" "Compositor errors detected in journal"
else
    echo -e "${GREEN}${ICON_CHECK} No recent compositor errors found${NC}"
fi
# Hyprland check
check_hyprland() {
    if [ "$HYPRLAND" = "1" ]; then
        echo -e "${BLUE}${ICON_CONFIG} Checking Hyprland status...${NC}"
        check_process "Hyprland" "Hyprland Compositor"
        
        # Check essential Wayland components
        check_process "waybar" "Waybar Status Bar"
        check_process "dunst" "Dunst Notifications"
        check_process "polkit-gnome-au" "Polkit Authentication Agent"

        # Check critical packages for Hyprland
        echo -e "${BLUE}${ICON_PACKAGE} Checking required packages...${NC}"
        check_package "xdg-desktop-portal-hyprland"
        check_package "qt6-wayland"
        check_package "xdg-utils"
        check_package "polkit-gnome"

        # Check XDG Desktop Portal status
        echo -e "\n${BLUE}${ICON_CONFIG} Checking XDG Desktop Portal...${NC}"
        if systemctl --user status xdg-desktop-portal.service &>/dev/null; then
            echo -e "${GREEN}${ICON_CHECK} XDG Desktop Portal is running${NC}"
            # Check portal implementations
            if systemctl --user status xdg-desktop-portal-hyprland.service &>/dev/null; then
                echo -e "${GREEN}${ICON_CHECK} Hyprland Portal implementation is active${NC}"
            else
                echo -e "${YELLOW}${ICON_WARN} Hyprland Portal implementation not running${NC}"
                log_message "WARN" "xdg-desktop-portal-hyprland service not active"
            fi
        else
            echo -e "${RED}${ICON_ERROR} XDG Desktop Portal is not running${NC}"
            log_message "ERROR" "XDG Desktop Portal service not running"
        fi

        # Check DBus session
        echo -e "\n${BLUE}${ICON_CONFIG} Checking DBus session...${NC}"
        if [ -n "$DBUS_SESSION_BUS_ADDRESS" ]; then
            echo -e "${GREEN}${ICON_CHECK} DBus session is active${NC}"
            # Test DBus functionality
            if dbus-send --session --dest=org.freedesktop.DBus --type=method_call --print-reply /org/freedesktop/DBus org.freedesktop.DBus.ListNames &>/dev/null; then
                echo -e "${GREEN}${ICON_CHECK} DBus communication working${NC}"
            else
                echo -e "${RED}${ICON_ERROR} DBus communication failed${NC}"
                log_message "ERROR" "DBus communication test failed"
            fi
        else
            echo -e "${RED}${ICON_ERROR} No DBus session found${NC}"
            log_message "ERROR" "DBus session not found"
        fi

        # Monitor memory usage of key components
        echo -e "\n${BLUE}${ICON_RAM} Checking component memory usage...${NC}"
        for process in "Hyprland" "waybar" "dunst" "polkit-gnome-au" "xdg-desktop-portal" "pipewire"; do
            mem_usage=$(ps -C "$process" -O rss --no-headers 2>/dev/null | awk '{sum+=$2} END {print sum/1024}')
            if [ -n "$mem_usage" ]; then
                echo -e "${GREEN}${ICON_CHECK} $process: ${mem_usage:.1f} MB${NC}"
            else
                echo -e "${YELLOW}${ICON_WARN} $process: Not running${NC}"
                log_message "WARN" "$process is not running"
            fi
        done

        # Check compositor-related errors in journal
        echo -e "\n${BLUE}${ICON_CONFIG} Checking compositor logs...${NC}"
        compositor_errors=$(journalctl -b | grep -i "compositor\\|wayland\\|hyprland" | grep -i "error\\|fail" | tail -n 5)
        if [ -n "$compositor_errors" ]; then
            echo -e "${YELLOW}${ICON_WARN} Recent compositor-related errors found:${NC}"
            echo "$compositor_errors" | sed 's/^/  /'
            log_message "WARN" "Compositor errors detected in journal"
        else
            echo -e "${GREEN}${ICON_CHECK} No recent compositor errors found${NC}"
        fi
    fi
}

# Call the function where needed
check_hyprland

# Function to check graphics drivers
check_gpu_status() {
    echo -e "\n${BLUE}${ICON_GPU} Checking graphics driver status...${NC}"
    if lspci | grep -i nvidia >/dev/null; then
        if ! nvidia-smi &>/dev/null; then
            echo -e "${YELLOW}${ICON_WARN} NVIDIA driver issues detected${NC}"
            log_message "WARN" "NVIDIA driver not responding properly"
        else
            echo -e "${GREEN}${ICON_CHECK} NVIDIA drivers working properly${NC}"
        fi
    fi
}

    # Display resolution and refresh rate
    echo -e "\n${BLUE}${ICON_DESKTOP} Checking display settings...${NC}"
    if command -v xrandr >/dev/null && [ -n "$DISPLAY" ]; then
        xrandr --current | grep -w connected | while read -r line; do
            echo -e "  ${GREEN}• $line${NC}"
        done
    elif command -v hyprctl >/dev/null; then
        hyprctl monitors | grep -E "Monitor|resolution" | while read -r line; do
            echo -e "  ${GREEN}• $line${NC}"
        done
    fi

    # Bootloader Configuration
    echo -e "\n${BLUE}${ICON_CONFIG} Checking bootloader configuration...${NC}"
    if [ -d "/boot/grub" ]; then
        echo -e "  ${GREEN}• GRUB detected${NC}"
        if [ -f "/boot/grub/grub.cfg" ]; then
            echo -e "  ${GREEN}• GRUB config present${NC}"
            grub_time=$(stat -c %Y /boot/grub/grub.cfg)
            echo -e "  ${BLUE}• Last updated: $(date -d "@$grub_time")${NC}"
        fi
    elif [ -d "/boot/loader" ]; then
        echo -e "  ${GREEN}• systemd-boot detected${NC}"
        bootctl status 2>/dev/null || echo -e "  ${YELLOW}• Unable to get bootloader status${NC}"
    fi

    # Virtualization Status
    echo -e "\n${BLUE}${ICON_SYSTEM} Checking virtualization support...${NC}"
    if grep -q "^flags.*vmx\|^flags.*svm" /proc/cpuinfo; then
        echo -e "  ${GREEN}• CPU virtualization support: Yes${NC}"
        for module in kvm kvm_intel kvm_amd vboxdrv; do
            if lsmod | grep -q "^$module"; then
                echo -e "  ${GREEN}• $module module: Loaded${NC}"
            fi
        done
    else
        echo -e "  ${YELLOW}• CPU virtualization support: No${NC}"
    fi

    # Microcode Updates
    echo -e "\n${BLUE}${ICON_CPU} Checking microcode status...${NC}"
    if [ -f "/sys/devices/system/cpu/microcode/reload" ]; then
        if dmesg | grep -i "microcode updated early to" >/dev/null; then
            echo -e "  ${GREEN}• Microcode is up to date${NC}"
        else
            echo -e "  ${YELLOW}• Microcode update may be needed${NC}"
        fi
    fi

    # System Time Sync
    echo -e "\n${BLUE}${ICON_CONFIG} Checking time synchronization...${NC}"
    for timesync in systemd-timesyncd chronyd ntpd; do
        if systemctl is-active $timesync >/dev/null 2>&1; then
            echo -e "  ${GREEN}• $timesync is active and running${NC}"
            if [ "$timesync" = "systemd-timesyncd" ]; then
                timedatectl status | grep "System clock" | sed 's/^/  /'
            fi
        fi
    done

    # Font Configuration
    echo -e "\n${BLUE}${ICON_CONFIG} Checking font configuration...${NC}"
    if [ -f "$HOME/.config/fontconfig/fonts.conf" ]; then
        echo -e "  ${GREEN}• User font configuration exists${NC}"
    fi
    if command -v fc-cache >/dev/null; then
        echo -e "  ${GREEN}• Font cache is available${NC}"
    fi

    # Package Dependencies
    echo -e "\n${BLUE}${ICON_PACKAGE} Checking package dependencies...${NC}"
    if pacman -Qdt >/dev/null 2>&1; then
        echo -e "  ${GREEN}• No orphaned packages found${NC}"
    else
        echo -e "  ${YELLOW}• Orphaned packages detected${NC}"
        pacman -Qdt | sed 's/^/    /'
    fi

    # Swap/ZRAM Configuration
    echo -e "\n${BLUE}${ICON_RAM} Checking swap/ZRAM configuration...${NC}"
    if grep -q "zram" /proc/swaps; then
        echo -e "  ${GREEN}• ZRAM is active${NC}"
        echo -e "  ${BLUE}• ZRAM usage:${NC}"
        swapon --show | grep zram | sed 's/^/    /'
    fi
    if [ -n "$(swapon --show)" ]; then
        echo -e "  ${BLUE}• Swap status:${NC}"
        free -h | grep "Swap:" | sed 's/^/    /'
    fi

    # Backup Status
    echo -e "\n${BLUE}${ICON_BACKUP} Checking backup system status...${NC}"
    for backup in timeshift snapper; do
        if command -v $backup >/dev/null; then
            echo -e "  ${GREEN}• $backup is installed${NC}"
            case $backup in
                timeshift)
                    if timeshift --list >/dev/null 2>&1; then
                        echo -e "  ${BLUE}• Recent backups:${NC}"
                        timeshift --list | tail -n 3 | sed 's/^/    /'
                    fi
                    ;;
                snapper)
                    if snapper list >/dev/null 2>&1; then
                        echo -e "  ${BLUE}• Recent snapshots:${NC}"
                        snapper list | tail -n 3 | sed 's/^/    /'
                    fi
                    ;;
            esac
        fi
    done

    # Firmware Updates
    echo -e "\n${BLUE}${ICON_UPDATE} Checking firmware updates...${NC}"
    if command -v fwupdmgr >/dev/null; then
        echo -e "  ${GREEN}• fwupd is installed${NC}"
        if fwupdmgr get-devices >/dev/null 2>&1; then
            echo -e "  ${BLUE}• Firmware status:${NC}"
            fwupdmgr get-updates 2>/dev/null || echo -e "    No updates available"
        fi
    fi

    # System File Integrity
    echo -e "\n${BLUE}${ICON_CONFIG} Checking system file integrity...${NC}"
    for integrity in aide tripwire; do
        if command -v $integrity >/dev/null; then
            echo -e "  ${GREEN}• $integrity is installed${NC}"
            case $integrity in
                aide)
                    if [ -f "/var/lib/aide/aide.db.gz" ]; then
                        echo -e "  ${BLUE}• AIDE database exists${NC}"
                    fi
                    ;;
                tripwire)
                    if [ -f "/var/lib/tripwire/$(hostname).twd" ]; then
                        echo -e "  ${BLUE}• Tripwire database exists${NC}"
                    fi
                    ;;
            esac
        fi
    done

    # Update complete
# Update complete
# Check Wayland status
check_wayland_status() {
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
                    log_message "WARN" "$comp not found"
                fi
            done
        fi
    fi
}

# Run checks
check_wayland_status

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
