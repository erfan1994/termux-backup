#!/bin/bash
# =============================================================================
# TERMUX BACKUP SYSTEM - INSTALLATION SCRIPT
# =============================================================================
# This script generates the complete project structure.
# Run: bash install.sh
# =============================================================================

set -euo pipefail

PROJECT_DIR="${HOME}/termux-backup"
echo "Installing Termux Backup System to ${PROJECT_DIR}..."

mkdir -p "${PROJECT_DIR}"/{config,lib,vault/{backups,snapshots,meta,tmp}}

# ===========================================================================
# config/backup.conf
# ===========================================================================
cat > "${PROJECT_DIR}/config/backup.conf" << 'CONFEOF'
# Termux Backup System Configuration
# =============================================================================

# Compression settings
COMPRESSION_LEVEL=3          # zstd compression level (1-19)
COMPRESSION_THREADS=0        # 0 = auto-detect CPU cores

# Retention policy
MAX_BACKUPS=7               # Maximum backups to keep
MAX_SNAPSHOT_AGE_DAYS=30    # Auto-clean snapshots older than this

# Paths (relative to project root, DO NOT CHANGE)
VAULT_BACKUPS="vault/backups"
VAULT_SNAPSHOTS="vault/snapshots"
VAULT_META="vault/meta"
VAULT_TMP="vault/tmp"

# Directories to backup
BACKUP_DIRS=(
    "${HOME}"
    "${PREFIX}"
)

# Critical files to explicitly verify
CRITICAL_FILES=(
    "${HOME}/.bashrc"
    "${HOME}/.profile"
    "${HOME}/.ssh"
    "${HOME}/.gitconfig"
    "${HOME}/.npmrc"
    "${PREFIX}/etc/apt/sources.list"
    "${PREFIX}/etc/apt/sources.list.d"
)

# Exclusion patterns (rsync-style)
EXCLUDE_PATTERNS=(
    "vault/backups"
    "vault/snapshots"
    "vault/tmp"
    ".cache"
    "tmp"
    ".npm/_cacache"
    ".gradle/caches"
    ".cargo/registry/cache"
)

# Safety checks
MIN_FREE_SPACE_MB=512       # Minimum free space before backup (MB)
SHA256_VALIDATE=true         # Always validate checksums
PRE_RESTORE_SNAPSHOT=true   # Create safety snapshot before restore
CONFEOF

# ===========================================================================
# lib/logger.sh
# ===========================================================================
cat > "${PROJECT_DIR}/lib/logger.sh" << 'LOGEOF'
#!/bin/bash
# =============================================================================
# LOGGER MODULE - Structured logging system
# =============================================================================

# Log levels
declare -r LOG_DEBUG=0
declare -r LOG_INFO=1
declare -r LOG_WARN=2
declare -r LOG_ERROR=3

LOG_LEVEL="${LOG_LEVEL:-$LOG_INFO}"
LOG_FILE="${LOG_FILE:-${PROJECT_DIR}/vault/backup.log}"
LOG_TIMESTAMP_FORMAT="%Y-%m-%d %H:%M:%S"

# Initialize logging
init_logging() {
    mkdir -p "$(dirname "${LOG_FILE}")"
    touch "${LOG_FILE}"
    chmod 600 "${LOG_FILE}"
}

# Core logging function
_log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date +"${LOG_TIMESTAMP_FORMAT}")
    
    if [[ ${level} -ge ${LOG_LEVEL} ]]; then
        local level_str
        case ${level} in
            ${LOG_DEBUG}) level_str="DEBUG";;
            ${LOG_INFO})  level_str="INFO";;
            ${LOG_WARN})  level_str="WARN";;
            ${LOG_ERROR}) level_str="ERROR";;
        esac
        
        local output="[${timestamp}] [${level_str}] ${message}"
        echo "${output}" | tee -a "${LOG_FILE}" >&2
    fi
}

log_debug() { _log ${LOG_DEBUG} "$*"; }
log_info()  { _log ${LOG_INFO}  "$*"; }
log_warn()  { _log ${LOG_WARN}  "$*"; }
log_error() { _log ${LOG_ERROR} "$*"; }

# Log fatal error and exit
log_fatal() {
    _log ${LOG_ERROR} "FATAL: $*"
    echo "FATAL ERROR: $*" >&2
    exit 1
}

# Log section header
log_section() {
    local title=$1
    local line="========================================"
    _log ${LOG_INFO} "${line}"
    _log ${LOG_INFO} "  ${title}"
    _log ${LOG_INFO} "${line}"
}
LOGEOF

# ===========================================================================
# lib/checks.sh
# ===========================================================================
cat > "${PROJECT_DIR}/lib/checks.sh" << 'CHKEOF'
#!/bin/bash
# =============================================================================
# CHECKS MODULE - Pre-flight validation and environment checks
# =============================================================================

# Check if running in Termux
check_termux_environment() {
    log_info "Verifying Termux environment..."
    
    if [[ -z "${PREFIX:-}" ]] || [[ -z "${HOME:-}" ]]; then
        log_fatal "PREFIX and HOME must be set (Termux environment required)"
    fi
    
    if [[ ! -d "${PREFIX}" ]]; then
        log_fatal "PREFIX directory not found: ${PREFIX}"
    fi
    
    if [[ ! -d "${HOME}" ]]; then
        log_fatal "HOME directory not found: ${HOME}"
    fi
    
    if [[ "${PREFIX}" != "/data/data/com.termux/files/usr" ]]; then
        log_warn "Non-standard PREFIX: ${PREFIX} (expected /data/data/com.termux/files/usr)"
    fi
    
    log_debug "Termux environment verified: PREFIX=${PREFIX}, HOME=${HOME}"
}

# Check required tools availability
check_dependencies() {
    log_info "Checking required dependencies..."
    
    local deps=("tar" "zstd" "sha256sum" "find" "sed" "grep" "awk" "stat" "du" "df")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &>/dev/null; then
            missing+=("${dep}")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_fatal "Missing required dependencies: ${missing[*]}"
    fi
    
    log_debug "All dependencies satisfied"
}

# Check disk space
check_disk_space() {
    log_info "Checking disk space..."
    
    local backup_dir="${PROJECT_DIR}/${VAULT_BACKUPS}"
    mkdir -p "${backup_dir}"
    
    local available_kb
    available_kb=$(df -k "${backup_dir}" | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))
    
    if [[ ${available_mb} -lt ${MIN_FREE_SPACE_MB} ]]; then
        log_fatal "Insufficient disk space: ${available_mb}MB available, ${MIN_FREE_SPACE_MB}MB required"
    fi
    
    log_info "Disk space OK: ${available_mb}MB available"
}

# Verify project structure
check_project_structure() {
    log_debug "Verifying project structure..."
    
    local dirs=(
        "${PROJECT_DIR}/config"
        "${PROJECT_DIR}/lib"
        "${PROJECT_DIR}/vault/backups"
        "${PROJECT_DIR}/vault/snapshots"
        "${PROJECT_DIR}/vault/meta"
        "${PROJECT_DIR}/vault/tmp"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "${dir}"
    done
    
    if [[ ! -f "${PROJECT_DIR}/config/backup.conf" ]]; then
        log_fatal "Configuration file missing: config/backup.conf"
    fi
}

# Comprehensive pre-flight checks
run_preflight_checks() {
    log_section "Pre-flight Checks"
    check_termux_environment
    check_dependencies
    check_project_structure
    check_disk_space
    log_info "All pre-flight checks passed"
}
CHKEOF

# ===========================================================================
# lib/snapshot.sh
# ===========================================================================
cat > "${PROJECT_DIR}/lib/snapshot.sh" << 'SNPEOF'
#!/bin/bash
# =============================================================================
# SNAPSHOT MODULE - System state capture
# =============================================================================

# Create system snapshot
create_snapshot() {
    local snapshot_name=$1
    local snapshot_dir="${PROJECT_DIR}/${VAULT_SNAPSHOTS}/${snapshot_name}"
    
    log_info "Creating system snapshot: ${snapshot_name}"
    
    mkdir -p "${snapshot_dir}"
    
    # Capture installed packages
    log_debug "Capturing package list..."
    dpkg --get-selections > "${snapshot_dir}/packages.list" 2>/dev/null || {
        log_warn "Could not capture package list via dpkg"
        apt list --installed 2>/dev/null > "${snapshot_dir}/packages-apt.list" || true
    }
    
    # Capture explicit package list (user-installed)
    apt-mark showmanual > "${snapshot_dir}/packages-manual.list" 2>/dev/null || true
    
    # Capture directory sizes
    log_debug "Capturing directory sizes..."
    du -sh "${HOME}" 2>/dev/null > "${snapshot_dir}/home-size.txt" || true
    du -sh "${PREFIX}" 2>/dev/null > "${snapshot_dir}/prefix-size.txt" || true
    
    # Capture file count
    log_debug "Counting files..."
    find "${HOME}" -type f 2>/dev/null | wc -l > "${snapshot_dir}/home-file-count.txt" || true
    find "${PREFIX}" -type f 2>/dev/null | wc -l > "${snapshot_dir}/prefix-file-count.txt" || true
    
    # Capture system info
    {
        echo "Kernel: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo "Hostname: $(hostname)"
        echo "Date: $(date -Iseconds)"
        echo "Termux Version: ${TERMUX_VERSION:-unknown}"
        echo "API Level: ${TERMUX_API_VERSION:-unknown}"
    } > "${snapshot_dir}/system-info.txt"
    
    # Capture environment variables (sanitized)
    env | grep -E '^(HOME|PREFIX|PATH|TERMUX|LANG|USER|SHELL)=' > "${snapshot_dir}/environment.env" 2>/dev/null || true
    
    # Create snapshot manifest
    cat > "${snapshot_dir}/manifest.json" << EOF
{
    "name": "${snapshot_name}",
    "created": "$(date -Iseconds)",
    "packages_file": "packages.list",
    "packages_manual": "packages-manual.list",
    "system_info": "system-info.txt"
}
EOF
    
    log_info "Snapshot created: ${snapshot_dir}"
    echo "${snapshot_name}"
}

# Load snapshot data
load_snapshot() {
    local snapshot_name=$1
    local snapshot_dir="${PROJECT_DIR}/${VAULT_SNAPSHOTS}/${snapshot_name}"
    
    if [[ ! -d "${snapshot_dir}" ]]; then
        log_fatal "Snapshot not found: ${snapshot_name}"
    fi
    
    log_debug "Loading snapshot: ${snapshot_name}"
    
    # Source environment if needed
    if [[ -f "${snapshot_dir}/environment.env" ]]; then
        set -a
        source "${snapshot_dir}/environment.env"
        set +a
    fi
    
    echo "${snapshot_dir}"
}

# Clean old snapshots
clean_old_snapshots() {
    local max_age_days=${MAX_SNAPSHOT_AGE_DAYS:-30}
    local snapshot_dir="${PROJECT_DIR}/${VAULT_SNAPSHOTS}"
    
    log_info "Cleaning snapshots older than ${max_age_days} days..."
    
    find "${snapshot_dir}" -maxdepth 1 -type d -mtime "+${max_age_days}" \
        -not -path "${snapshot_dir}" -exec rm -rf {} + 2>/dev/null || true
    
    log_info "Snapshot cleanup complete"
}
SNPEOF

# ===========================================================================
# lib/packages.sh
# ===========================================================================
cat > "${PROJECT_DIR}/lib/packages.sh" << 'PKGEOF'
#!/bin/bash
# =============================================================================
# PACKAGES MODULE - Package management operations
# =============================================================================

# Get list of explicitly installed packages
get_manual_packages() {
    log_debug "Fetching manually installed packages..."
    apt-mark showmanual 2>/dev/null | sort || {
        log_warn "apt-mark showmanual failed, falling back to dpkg"
        dpkg --get-selections 2>/dev/null | grep -v deinstall | awk '{print $1}' | sort || {
            log_fatal "Cannot get package list"
        }
    }
}

# Reinstall packages from list
restore_packages() {
    local package_list=$1
    
    if [[ ! -f "${package_list}" ]]; then
        log_fatal "Package list file not found: ${package_list}"
    fi
    
    log_section "Package Restoration"
    
    # Update package cache
    log_info "Updating package repositories..."
    apt-get update -y 2>&1 | _log ${LOG_INFO} "APT update output" || {
        log_error "apt-get update failed"
        return 1
    }
    
    # Upgrade existing packages first
    log_info "Upgrading existing packages..."
    apt-get upgrade -y 2>&1 | _log ${LOG_INFO} "APT upgrade output" || true
    
    # Read and install packages
    local total_packages
    total_packages=$(wc -l < "${package_list}")
    local installed=0
    local failed=0
    
    log_info "Restoring ${total_packages} packages..."
    
    while IFS= read -r package; do
        [[ -z "${package}" || "${package}" =~ ^[[:space:]]*# ]] && continue
        
        log_debug "Installing package: ${package}"
        if apt-get install -y "${package}" 2>&1 | _log ${LOG_DEBUG} "Package install: ${package}"; then
            ((installed++))
        else
            ((failed++))
            log_warn "Failed to install package: ${package}"
        fi
    done < "${package_list}"
    
    log_info "Packages restored: ${installed}/${total_packages} succeeded, ${failed} failed"
    
    if [[ ${failed} -gt 0 ]]; then
        log_warn "${failed} packages failed to install"
        return 1
    fi
    
    return 0
}
PKGEOF

# ===========================================================================
# lib/archive.sh
# ===========================================================================
cat > "${PROJECT_DIR}/lib/archive.sh" << 'ARCEOF'
#!/bin/bash
# =============================================================================
# ARCHIVE MODULE - Compression and archive operations
# =============================================================================

# Create backup archive
create_backup_archive() {
    local backup_name=$1
    local source_dir=$2
    local output_file=$3
    
    log_info "Creating archive: ${output_file}"
    
    # Build exclusion arguments
    local exclude_args=()
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_args+=("--exclude=${pattern}")
    done
    
    # Add project backup directories to exclusions
    exclude_args+=("--exclude=${VAULT_BACKUPS}")
    exclude_args+=("--exclude=${VAULT_SNAPSHOTS}")
    exclude_args+=("--exclude=${VAULT_TMP}")
    
    # Create archive with zstd compression
    log_debug "Archiving ${source_dir} with compression level ${COMPRESSION_LEVEL}..."
    
    tar \
        --create \
        --preserve-permissions \
        --acls \
        --xattrs \
        --selinux \
        --sparse \
        --same-permissions \
        --numeric-owner \
        "${exclude_args[@]}" \
        --directory="/" \
        --file=- \
        "${source_dir#/}" 2>/dev/null | \
    zstd \
        -"${COMPRESSION_LEVEL}" \
        -T"${COMPRESSION_THREADS}" \
        --long \
        --check \
        -o "${output_file}" 2>/dev/null
    
    if [[ ! -f "${output_file}" ]]; then
        log_fatal "Failed to create archive: ${output_file}"
    fi
    
    local archive_size
    archive_size=$(du -sh "${output_file}" | cut -f1)
    log_info "Archive created: ${output_file} (${archive_size})"
    
    echo "${output_file}"
}

# Extract backup archive
extract_backup_archive() {
    local archive_file=$1
    local target_dir=$2
    
    if [[ ! -f "${archive_file}" ]]; then
        log_fatal "Archive file not found: ${archive_file}"
    fi
    
    log_info "Extracting archive: ${archive_file}"
    
    # Extract to target directory
    zstd -d -c "${archive_file}" 2>/dev/null | \
    tar \
        --extract \
        --preserve-permissions \
        --acls \
        --xattrs \
        --selinux \
        --same-permissions \
        --numeric-owner \
        --directory="${target_dir}" \
        --file=- 2>/dev/null
    
    if [[ $? -ne 0 ]]; then
        log_fatal "Failed to extract archive: ${archive_file}"
    fi
    
    log_info "Archive extracted successfully"
}

# Compute SHA256 checksum
compute_checksum() {
    local file=$1
    
    if [[ ! -f "${file}" ]]; then
        log_fatal "File not found for checksum: ${file}"
    fi
    
    log_debug "Computing SHA256 checksum for: ${file}"
    sha256sum "${file}" | awk '{print $1}'
}

# Verify archive integrity
verify_archive() {
    local archive_file=$1
    local checksum_file=$2
    
    log_info "Verifying archive integrity..."
    
    if [[ ! -f "${checksum_file}" ]]; then
        log_fatal "Checksum file not found: ${checksum_file}"
    fi
    
    local stored_checksum
    stored_checksum=$(cat "${checksum_file}")
    
    local computed_checksum
    computed_checksum=$(compute_checksum "${archive_file}")
    
    if [[ "${stored_checksum}" != "${computed_checksum}" ]]; then
        log_fatal "Checksum verification FAILED! Archive may be corrupted."
    fi
    
    log_info "Archive integrity verified (SHA256 match)"
}
ARCEOF

# ===========================================================================
# lib/verify.sh
# ===========================================================================
cat > "${PROJECT_DIR}/lib/verify.sh" << 'VRFEOF'
#!/bin/bash
# =============================================================================
# VERIFY MODULE - Backup verification and validation
# =============================================================================

# Verify backup completeness
verify_backup() {
    local backup_name=$1
    local meta_dir="${PROJECT_DIR}/${VAULT_META}/${backup_name}"
    
    log_section "Backup Verification"
    
    if [[ ! -d "${meta_dir}" ]]; then
        log_fatal "Backup metadata not found: ${meta_dir}"
    fi
    
    # Check archive exists
    local archive_file="${PROJECT_DIR}/${VAULT_BACKUPS}/${backup_name}.tar.zst"
    if [[ ! -f "${archive_file}" ]]; then
        log_fatal "Backup archive missing: ${archive_file}"
    fi
    
    # Verify checksum
    local checksum_file="${meta_dir}/checksum.sha256"
    verify_archive "${archive_file}" "${checksum_file}"
    
    # Check for critical files in archive
    log_info "Checking critical files in backup..."
    local missing_critical=()
    
    for critical_file in "${CRITICAL_FILES[@]}"; do
        if zstd -d -c "${archive_file}" 2>/dev/null | tar tf - 2>/dev/null | grep -q "${critical_file#/}"; then
            log_debug "Critical file present: ${critical_file}"
        else
            missing_critical+=("${critical_file}")
        fi
    done
    
    if [[ ${#missing_critical[@]} -gt 0 ]]; then
        log_warn "Missing critical files in backup: ${missing_critical[*]}"
    else
        log_info "All critical files verified"
    fi
    
    # Verify manifest
    if [[ -f "${meta_dir}/manifest.json" ]]; then
        log_debug "Backup manifest verified"
    else
        log_warn "Backup manifest missing"
    fi
    
    log_info "Backup verification complete: ${backup_name}"
}

# Verify restore completeness
verify_restore() {
    local snapshot_name=$1
    
    log_section "Restore Verification"
    
    # Compare file counts
    local snapshot_dir="${PROJECT_DIR}/${VAULT_SNAPSHOTS}/${snapshot_name}"
    
    if [[ -f "${snapshot_dir}/home-file-count.txt" ]]; then
        local pre_count
        pre_count=$(cat "${snapshot_dir}/home-file-count.txt")
        local post_count
        post_count=$(find "${HOME}" -type f 2>/dev/null | wc -l)
        log_info "Home file count - Pre: ${pre_count}, Post: ${post_count}"
        
        if [[ ${post_count} -lt ${pre_count} ]]; then
            local diff=$((pre_count - post_count))
            log_warn "Missing ${diff} files in home directory after restore"
        fi
    fi
    
    # Check for Termux functionality
    if [[ -f "${PREFIX}/bin/bash" ]] || [[ -f "${PREFIX}/bin/zsh" ]]; then
        log_info "Termux shell accessible"
    else
        log_error "No shell found in PREFIX after restore"
    fi
    
    log_info "Restore verification complete"
}
VRFEOF

# ===========================================================================
# lib/restore.sh
# ===========================================================================
cat > "${PROJECT_DIR}/lib/restore.sh" << 'RSTEOF'
#!/bin/bash
# =============================================================================
# RESTORE MODULE - Complete system restoration
# =============================================================================

# Main restore function
perform_restore() {
    local backup_name=$1
    
    log_section "System Restore: ${backup_name}"
    
    local backup_file="${PROJECT_DIR}/${VAULT_BACKUPS}/${backup_name}.tar.zst"
    local meta_dir="${PROJECT_DIR}/${VAULT_META}/${backup_name}"
    
    # Verify backup exists
    if [[ ! -f "${backup_file}" ]]; then
        log_fatal "Backup archive not found: ${backup_file}"
    fi
    
    # Verify integrity
    verify_backup "${backup_name}"
    
    # Create safety snapshot if enabled
    if [[ "${PRE_RESTORE_SNAPSHOT:-true}" == "true" ]]; then
        local safety_snapshot="pre-restore-${backup_name}-$(date +%Y%m%d-%H%M%S)"
        log_info "Creating safety snapshot before restore..."
        create_snapshot "${safety_snapshot}"
    fi
    
    # Extract backup
    log_section "Extracting Backup"
    log_warn "Restoring files from backup: ${backup_name}"
    
    # Extract HOME
    log_info "Restoring HOME directory..."
    extract_backup_archive "${backup_file}" "/"
    
    # Restore packages
    local packages_file="${meta_dir}/packages.list"
    if [[ -f "${packages_file}" ]]; then
        log_info "Restoring installed packages..."
        restore_packages "${packages_file}" || log_warn "Some packages failed to restore"
    else
        log_warn "Package list not found in backup metadata, skipping package restore"
    fi
    
    # Fix permissions
    log_section "Permission Repair"
    log_info "Fixing permissions on HOME..."
    chmod -R u+rwX "${HOME}" 2>/dev/null || true
    chmod -R go-rwx "${HOME}/.ssh" 2>/dev/null || true
    
    if [[ -d "${PREFIX}" ]]; then
        log_info "Fixing permissions on PREFIX..."
        chmod -R u+rwX "${PREFIX}" 2>/dev/null || true
    fi
    
    # Ensure critical directories
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh" 2>/dev/null || true
    
    log_info "Permissions repaired"
    
    # Verify restore
    verify_restore "${safety_snapshot:-unknown}"
    
    log_section "Restore Complete"
    log_info "System restored from backup: ${backup_name}"
    log_info "Please restart Termux to ensure all changes take effect"
    
    echo ""
    echo "=========================================="
    echo " RESTORE COMPLETE"
    echo "=========================================="
    echo " Backup: ${backup_name}"
    echo " Safety snapshot: ${safety_snapshot:-none}"
    echo ""
    echo " Please restart Termux now:"
    echo "   exit"
    echo "   termux-reload-settings"
    echo "=========================================="
}
RSTEOF

# ===========================================================================
# lib/core.sh
# ===========================================================================
cat > "${PROJECT_DIR}/lib/core.sh" << 'COREEOF'
#!/bin/bash
# =============================================================================
# CORE MODULE - Main backup orchestration
# =============================================================================

# Create full backup
create_backup() {
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="termux-full-${timestamp}"
    local backup_dir="${PROJECT_DIR}/${VAULT_BACKUPS}"
    local meta_dir="${PROJECT_DIR}/${VAULT_META}/${backup_name}"
    local tmp_dir="${PROJECT_DIR}/${VAULT_TMP}"
    
    log_section "Termux Full Backup: ${backup_name}"
    
    # Create directories
    mkdir -p "${backup_dir}" "${meta_dir}" "${tmp_dir}"
    
    # Pre-backup snapshot
    local snapshot_name="pre-backup-${backup_name}"
    create_snapshot "${snapshot_name}"
    
    # Gather package list
    log_info "Capturing installed packages..."
    local packages_file="${meta_dir}/packages.list"
    get_manual_packages > "${packages_file}"
    log_info "Package list saved: $(wc -l < ${packages_file}) packages"
    
    # Create unified archive
    log_section "Creating Backup Archive"
    local archive_file="${backup_dir}/${backup_name}.tar.zst"
    
    # Backup entire HOME and PREFIX (excluding vaults)
    local backup_source="${HOME}"
    
    create_backup_archive "${backup_name}" "${HOME}" "${archive_file}"
    
    # Also backup PREFIX separately
    local prefix_archive="${backup_dir}/${backup_name}-prefix.tar.zst"
    log_info "Backing up PREFIX directory..."
    create_backup_archive "${backup_name}-prefix" "${PREFIX}" "${prefix_archive}"
    
    # Generate checksums
    log_info "Generating checksums..."
    compute_checksum "${archive_file}" > "${meta_dir}/checksum.sha256"
    compute_checksum "${prefix_archive}" > "${meta_dir}/checksum-prefix.sha256"
    
    # Create backup manifest
    local total_size
    total_size=$(du -sh "${archive_file}" | cut -f1)
    local prefix_size
    prefix_size=$(du -sh "${prefix_archive}" | cut -f1)
    
    cat > "${meta_dir}/manifest.json" << EOF
{
    "backup_name": "${backup_name}",
    "created": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "architecture": "$(uname -m)",
    "kernel": "$(uname -r)",
    "home_archive": "${backup_name}.tar.zst",
    "home_size": "${total_size}",
    "prefix_archive": "${backup_name}-prefix.tar.zst",
    "prefix_size": "${prefix_size}",
    "checksum": "$(cat ${meta_dir}/checksum.sha256)",
    "checksum_prefix": "$(cat ${meta_dir}/checksum-prefix.sha256)",
    "packages": "packages.list",
    "snapshot": "${snapshot_name}",
    "compression": "zstd level ${COMPRESSION_LEVEL}"
}
EOF
    
    # Update latest symlink
    ln -sf "${meta_dir}" "${PROJECT_DIR}/${VAULT_META}/latest"
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Clean temporary files
    rm -rf "${tmp_dir:?}"/*
    
    log_section "Backup Complete"
    log_info "Backup created successfully: ${backup_name}"
    log_info "Location: ${backup_dir}/${backup_name}.tar.zst"
    log_info "Metadata: ${meta_dir}/manifest.json"
    
    echo ""
    echo "=========================================="
    echo " BACKUP COMPLETE"
    echo "=========================================="
    echo " Name: ${backup_name}"
    echo " Size: ${total_size}"
    echo " Packages: $(wc -l < ${packages_file})"
    echo " Location: vault/backups/"
    echo "=========================================="
    
    return 0
}

# Clean old backups based on retention policy
cleanup_old_backups() {
    local backup_dir="${PROJECT_DIR}/${VAULT_BACKUPS}"
    local max_backups=${MAX_BACKUPS:-7}
    
    log_info "Checking backup retention (max: ${max_backups})..."
    
    # List backups sorted by date
    local backups
    mapfile -t backups < <(find "${backup_dir}" -maxdepth 1 -name "*.tar.zst" -not -name "*-prefix.tar.zst" -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}')
    
    if [[ ${#backups[@]} -gt ${max_backups} ]]; then
        log_info "Removing old backups (keeping ${max_backups})..."
        
        for ((i=max_backups; i<${#backups[@]}; i++)); do
            local old_backup="${backups[$i]}"
            local old_name
            old_name=$(basename "${old_backup}" .tar.zst)
            
            log_info "Removing old backup: ${old_name}"
            rm -f "${old_backup}"
            rm -f "${old_backup%-prefix}.tar.zst" 2>/dev/null || true
            rm -rf "${PROJECT_DIR}/${VAULT_META}/${old_name}" 2>/dev/null || true
            rm -rf "${PROJECT_DIR}/${VAULT_SNAPSHOTS}/pre-backup-${old_name}" 2>/dev/null || true
        done
    fi
    
    # Clean old snapshots
    clean_old_snapshots
}

# List available backups
list_backups() {
    local backup_dir="${PROJECT_DIR}/${VAULT_BACKUPS}"
    
    echo ""
    echo "Available Backups:"
    echo "=================="
    
    if [[ ! -d "${backup_dir}" ]]; then
        echo "No backups found"
        return
    fi
    
    local backups
    mapfile -t backups < <(find "${backup_dir}" -maxdepth 1 -name "*.tar.zst" -not -name "*-prefix.tar.zst" -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}')
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "No backups found"
        return
    fi
    
    for backup in "${backups[@]}"; do
        local name
        name=$(basename "${backup}" .tar.zst)
        local size
        size=$(du -sh "${backup}" | cut -f1)
        local date
        date=$(stat -c '%y' "${backup}" | cut -d. -f1)
        
        echo "  [${date}]  ${name}  (${size})"
        
        # Show metadata if available
        local meta_file="${PROJECT_DIR}/${VAULT_META}/${name}/manifest.json"
        if [[ -f "${meta_file}" ]]; then
            local pkg_count
            pkg_count=$(wc -l < "${PROJECT_DIR}/${VAULT_META}/${name}/packages.list" 2>/dev/null || echo "?")
            echo "           Packages: ${pkg_count}"
        fi
    done
    
    echo ""
    echo "Total backups: ${#backups[@]}"
    echo ""
}
COREEOF

# ===========================================================================
# termux-backup (main entry point)
# ===========================================================================
cat > "${PROJECT_DIR}/termux-backup" << 'BKUPEOF'
#!/bin/bash
# =============================================================================
# TERMUX BACKUP - Main backup entry point
# =============================================================================

set -Eeuo pipefail

# Determine project root
if [[ -z "${PROJECT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="${SCRIPT_DIR}"
fi

# Load configuration
if [[ -f "${PROJECT_DIR}/config/backup.conf" ]]; then
    source "${PROJECT_DIR}/config/backup.conf"
else
    echo "ERROR: Configuration file not found: config/backup.conf" >&2
    exit 1
fi

# Load modules
for module in logger checks snapshot packages archive verify; do
    if [[ -f "${PROJECT_DIR}/lib/${module}.sh" ]]; then
        source "${PROJECT_DIR}/lib/${module}.sh"
    else
        echo "ERROR: Module not found: lib/${module}.sh" >&2
        exit 1
    fi
done

source "${PROJECT_DIR}/lib/core.sh"

# Initialize
init_logging

# Parse arguments
case "${1:-help}" in
    backup|create)
        log_info "Starting Termux backup..."
        run_preflight_checks
        create_backup
        ;;
    list|ls)
        list_backups
        ;;
    verify)
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 verify <backup-name>"
            list_backups
            exit 1
        fi
        run_preflight_checks
        verify_backup "${2}"
        ;;
    help|--help|-h)
        cat << 'HELPEOF'

Termux Backup System
====================

Usage: ./termux-backup <command> [options]

Commands:
  backup, create      Create a new full system backup
  list, ls            List all available backups
  verify <name>       Verify a specific backup's integrity
  help                Show this help message

Examples:
  ./termux-backup backup
  ./termux-backup list
  ./termux-backup verify termux-full-20260101-120000

Configuration: config/backup.conf
Logs: vault/backup.log

HELPEOF
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
BKUPEOF

# ===========================================================================
# termux-restore (main restore entry point)
# ===========================================================================
cat > "${PROJECT_DIR}/termux-restore" << 'RSTREOF'
#!/bin/bash
# =============================================================================
# TERMUX RESTORE - Main restore entry point
# =============================================================================

set -Eeuo pipefail

# Determine project root
if [[ -z "${PROJECT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="${SCRIPT_DIR}"
fi

# Load configuration
if [[ -f "${PROJECT_DIR}/config/backup.conf" ]]; then
    source "${PROJECT_DIR}/config/backup.conf"
else
    echo "ERROR: Configuration file not found: config/backup.conf" >&2
    exit 1
fi

# Load modules
for module in logger checks snapshot packages archive verify restore; do
    if [[ -f "${PROJECT_DIR}/lib/${module}.sh" ]]; then
        source "${PROJECT_DIR}/lib/${module}.sh"
    else
        echo "ERROR: Module not found: lib/${module}.sh" >&2
        exit 1
    fi
done

# Initialize
init_logging

# Parse arguments
case "${1:-help}" in
    restore)
        if [[ -z "${2:-}" ]]; then
            echo "Available backups:"
            list_backups
            echo ""
            echo "Usage: $0 restore <backup-name>"
            exit 1
        fi
        
        log_info "Starting Termux restore..."
        run_preflight_checks
        
        # Load restore module
        source "${PROJECT_DIR}/lib/restore.sh"
        
        perform_restore "${2}"
        ;;
    list|ls)
        list_backups
        ;;
    verify)
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 verify <backup-name>"
            list_backups
            exit 1
        fi
        run_preflight_checks
        verify_backup "${2}"
        ;;
    help|--help|-h)
        cat << 'HELPEOF'

Termux Restore System
=====================

Usage: ./termux-restore <command> [options]

Commands:
  restore <name>      Restore system from a specific backup
  list, ls            List all available backups
  verify <name>       Verify a backup's integrity
  help                Show this help message

Examples:
  ./termux-restore list
  ./termux-restore restore termux-full-20260101-120000
  ./termux-restore verify termux-full-20260101-120000

IMPORTANT: Restore operation will OVERWRITE current system files.
A safety snapshot is created automatically before restore.

Configuration: config/backup.conf
Logs: vault/backup.log

HELPEOF
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
RSTREOF

# Make scripts executable
chmod +x "${PROJECT_DIR}/termux-backup"
chmod +x "${PROJECT_DIR}/termux-restore"
chmod +x "${PROJECT_DIR}/lib/"*.sh

# Create README
cat > "${PROJECT_DIR}/README.md" << 'READMEEOF'
# Termux Backup & Restore System

A production-grade backup and restore system for Termux.

## Quick Start

```bash
# Create a backup
./termux-backup backup

# List backups
./termux-backup list

# Restore from backup
./termux-restore restore <backup-name>
