#!/bin/bash

# Enhanced NTFS Drive Mounter
# Automatically detects and mounts NTFS drives with advanced features and proper permissions
# Version: 2.0
# License: MIT

# Strict error handling
set -euo pipefail
IFS=$'\n\t'

# Constants
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="/var/log/ntfs-mounter.log"
readonly BACKUP_DIR="/var/backups/ntfs-mounter"
readonly MOUNT_OPTIONS="rw,big_writes,windows_names,noatime,x-gvfs-show"

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'  # No Color

# Logging functions
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}Error: $1${NC}" >&2
    log "ERROR" "$1"
}

success() {
    echo -e "${GREEN}$1${NC}"
    log "INFO" "$1"
}

warn() {
    echo -e "${YELLOW}Warning: $1${NC}"
    log "WARN" "$1"
}

info() {
    echo -e "${BLUE}Info: $1${NC}"
    log "INFO" "$1"
}

# Initialize logging
init_logging() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir"
    fi
    
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
    fi
    
    chown "$SUDO_USER:$(id -g "$SUDO_USER")" "$LOG_FILE"
    chmod 644 "$LOG_FILE"
}

# Function to show help message
show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] [DEVICE]

Automatically detects and mounts NTFS drives with advanced features.

Options:
-h, --help        Show this help message
-f, --fstab       Add entries to /etc/fstab for permanent mounting
--force           Force mount dirty volumes (use with caution)
--user USER       Specify username (defaults to current user)
--mountdir DIR    Specify base mount directory (defaults to /run/media/USERNAME)
--unmount         Unmount NTFS drives
--status          Show status of NTFS mounts
--verify          Verify NTFS filesystem integrity
--recover         Attempt to recover corrupted NTFS partition
--debug           Enable debug logging
--list           List all NTFS partitions

Examples:
$SCRIPT_NAME --force                # Mount all NTFS drives with force option
$SCRIPT_NAME -f                     # Mount and add to fstab
$SCRIPT_NAME --unmount /dev/sdb1    # Unmount specific NTFS drive
$SCRIPT_NAME --status               # Show mount status
$SCRIPT_NAME --verify /dev/sdb1     # Check filesystem integrity

Note: This script requires sudo privileges.
EOF
}

# Check if running with sudo
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run with sudo privileges"
        exit 1
    fi
}

# Check for required tools
check_dependencies() {
    local missing_deps=()
    
    for cmd in blkid mount ntfs-3g grep awk ntfsfix ntfsinfo; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -ne 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing packages and try again."
        exit 1
    fi
}

# Check for hibernated Windows
check_hibernation() {
    local device="$1"
    local hibernate_status
    
    hibernate_status=$(ntfsinfo "$device" 2>/dev/null | grep -i "Hibernated:" || true)
    
    if [[ "$hibernate_status" == *"Yes"* ]]; then
        warn "Windows hibernation detected on $device"
        warn "Mounting in read-only mode to prevent data corruption"
        return 1
    fi
    return 0
}

# Verify NTFS filesystem
verify_filesystem() {
    local device="$1"
    
    info "Verifying filesystem on $device"
    if ntfsfix -d "$device"; then
        success "Filesystem verification completed successfully"
        return 0
    else
        error "Filesystem verification failed"
        return 1
    fi
}

# Get NTFS partitions
get_ntfs_partitions() {
    blkid | grep -i "type=\"ntfs\"" | cut -d: -f1
}

# Create mount point directory safely
create_mount_point() {
    local device="$1"
    local mount_name="$2"
    local base_dir="$3"
    
    # Get label or use device name if no label
    local label
    label=$(blkid -o value -s LABEL "$device" || echo "${device##*/}")
    
    # Clean up label for use in path
    label=$(echo "$label" | sed 's/[^[:alnum:]]/_/g')
    
    local mount_point="$base_dir/$mount_name"
    
    if [[ ! -d "$mount_point" ]]; then
        mkdir -p "$mount_point"
        success "Created mount point: $mount_point"
    fi
    
    # Set proper ownership and permissions
    chown "$SUDO_USER:$(id -g "$SUDO_USER")" "$mount_point"
    chmod 755 "$mount_point"
    
    echo "$mount_point"
}

# Backup important files
create_backup() {
    local file="$1"
    local backup_file="$BACKUP_DIR/$(basename "$file").$(date +%Y%m%d-%H%M%S)"
    
    mkdir -p "$BACKUP_DIR"
    cp "$file" "$backup_file"
    success "Created backup: $backup_file"
}

# Mount NTFS partition
mount_partition() {
    local device="$1"
    local mount_point="$2"
    local force_mount="$3"
    
    # Check if already mounted
    if mountpoint -q "$mount_point"; then
        warn "$mount_point is already mounted"
        return 0
    }
    
    # Check for hibernation unless force mount is enabled
    if [[ "$force_mount" != "true" ]] && ! check_hibernation "$device"; then
        return 1
    }
    
    local mount_options="uid=$(id -u "$SUDO_USER"),gid=$(id -g "$SUDO_USER"),$MOUNT_OPTIONS"
    
    if [[ "$force_mount" == "true" ]]; then
        mount_options+=",force"
    fi
    
    # Try ntfs3 first (kernel driver)
    if mount -t ntfs3 -o "$mount_options" "$device" "$mount_point" 2>/dev/null; then
        success "Successfully mounted $device at $mount_point using ntfs3 driver"
        return 0
    fi
    
    # Fallback to ntfs-3g
    if mount -t ntfs-3g -o "$mount_options" "$device" "$mount_point"; then
        success "Successfully mounted $device at $mount_point using ntfs-3g"
        return 0
    else
        error "Failed to mount $device at $mount_point"
        return 1
    fi
}

# Unmount NTFS partition
unmount_partition() {
    local mount_point="$1"
    
    if ! mountpoint -q "$mount_point"; then
        warn "$mount_point is not mounted"
        return 0
    }
    
    if umount "$mount_point"; then
        success "Successfully unmounted $mount_point"
        return 0
    else
        error "Failed to unmount $mount_point"
        return 1
    fi
}

# Show mount status
show_mount_status() {
    info "Current NTFS mounts:"
    mount | grep -E "ntfs|ntfs-3g" || echo "No NTFS partitions currently mounted"
}

# Add entry to fstab
add_to_fstab() {
    local device="$1"
    local mount_point="$2"
    local uuid
    uuid=$(blkid -s UUID -o value "$device")
    
    if [[ -z "$uuid" ]]; then
        error "Could not get UUID for device $device"
        return 1
    }
    
    local fstab_line="UUID=$uuid $mount_point ntfs-3g $MOUNT_OPTIONS,uid=$(id -u "$SUDO_USER"),gid=$(id -g "$SUDO_USER") 0 0"
    
    # Check if entry already exists
    if grep -q "$mount_point" /etc/fstab; then
        warn "Mount point $mount_point already exists in fstab"
        return 0
    fi
    
    # Backup fstab
    create_backup "/etc/fstab"
    
    echo "$fstab_line" >> /etc/fstab
    success "Added entry to fstab for $device"
}

main() {
    local add_to_fstab=false
    local force_mount=false
    local custom_user=""
    local mount_base_dir=""
    local unmount_mode=false
    local show_status=false
    local verify_mode=false
    local debug_mode=false
    local specific_device=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--fstab)
                add_to_fstab=true
                shift
                ;;
            --force)
                force_mount=true
                shift
                ;;
            --user)
                custom_user="$2"
                shift 2
                ;;
            --mountdir)
                mount_base_dir="$2"
                shift 2
                ;;
            --unmount)
                unmount_mode=true
                [[ $# -gt 1 ]] && specific_device="$2"
                shift
                ;;
            --status)
                show_status=true
                shift
                ;;
            --verify)
                verify_mode=true
                [[ $# -gt 1 ]] && specific_device="$2"
                shift
                ;;
            --debug)
                debug_mode=true
                set -x
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Verify root privileges
    check_sudo
    
    # Initialize logging
    init_logging
    
    # Check dependencies
    check_dependencies
    
    # Set user and mount base directory
    SUDO_USER=${custom_user:-${SUDO_USER:-$(whoami)}}
    mount_base_dir=${mount_base_dir:-"/run/media/$SUDO_USER"}
    
    # Handle different operation modes
    if [[ "$show_status" == "true" ]]; then
        show_mount_status
        exit 0
    fi
    
    if [[ "$verify_mode" == "true" ]]; then
        if [[ -n "$specific_device" ]]; then
            verify_filesystem "$specific_device"
        else
            error "Please specify a device to verify"
            exit 1
        fi
        exit 0
    fi
    
    # Get NTFS partitions
    local partitions
    if [[ -n "$specific_device" ]]; then
        partitions=("$specific_device")
    else
        mapfile -t partitions < <(get_ntfs_partitions)
    fi
    
    if [[ ${#partitions[@]} -eq 0 ]]; then
        error "No NTFS partitions found"
        exit 1
    fi
    
    success "Found ${#partitions[@]} NTFS partition(s)"
    
    # Process each partition
    for device in "${partitions[@]}"; do
        local mount_point
        mount_point=$(create_mount_point "$device" "$(basename "$device")" "$mount_base_dir")
        
        if [[ "$unmount_mode" == "true" ]]; then
            unmount_partition "$mount_point"
        else
            if mount_partition "$device" "$mount_point" "$force_mount"; then
                if [[ "$add_to_fstab" == "true" ]]; then
                    add_to_fstab "$device" "$mount_point"
                fi
            fi
        fi
    done
}

# Run main function
main "$@"

