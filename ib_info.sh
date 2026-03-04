#!/bin/bash
set -uo pipefail  # -e intentionally omitted — script collects partial data on command failure

# ============================================================================
# ib_info.sh - Gather InfiniBand configuration info from cluster nodes
#
# Outputs CSV config data to stdout. Errors and warnings are buffered in
# memory and flushed to stderr at exit as a labeled block, suitable for
# capture via clush stderr aggregation. No files are written on the node.
# Designed to continue collecting data even when individual commands fail.
# ============================================================================

HOSTNAME_SHORT=$(hostname -s 2>/dev/null || echo "unknown")

# Help function
show_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo "Options:"
    echo "  -h, --help      Show this help message and exit"
    echo "      --header    Print CSV header line and exit"
    echo ""
    echo "This script gathers and displays detailed information about the InfiniBand setup on the system."
    echo "It collects data such as hostname, serial number, model, OS details, kernel version,"
    echo "Mellanox card models, driver type, driver version, and firmware version."
    echo "One output line is generated per unique Mellanox card model found."
    echo ""
    echo "Output:"
    echo "  CSV data:    stdout (one line per unique card)"
    echo "  Errors/warnings: stderr (flushed as a labeled block at exit)"
    echo ""
    echo "CSV format:"
    echo "  Hostname,Serial Number,Model,OS,Kernel,Mellanox Card Model,Driver Type,Installed OFED,Loaded OFED,Firmware Version"
    echo ""
}

# Parse options and handle help flag
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --header)
            echo '"Hostname","Serial Number","Model","OS","Kernel","Mellanox Card Model","Driver Type","Installed OFED","Loaded OFED","Firmware Version"'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

# ============================================================================
# In-memory error buffer — flushed to stderr at EXIT
# ============================================================================

ERROR_BUFFER=""
error_count=0
warn_count=0

flush_errors() {
    if [[ -n "$ERROR_BUFFER" ]]; then
        printf '=== IB_INFO ERRORS: %s ===\n' "$HOSTNAME_SHORT" >&2
        printf '%s\n' "$ERROR_BUFFER" >&2
        printf '=== END: %s ===\n' "$HOSTNAME_SHORT" >&2
    fi
}
trap flush_errors EXIT

# ============================================================================
# Logging functions
# ============================================================================

log_error() {
    ERROR_BUFFER="${ERROR_BUFFER}${ERROR_BUFFER:+$'\n'}[$(date '+%Y-%m-%d %H:%M:%S')] ${HOSTNAME_SHORT} ERROR: $*"
    (( error_count += 1 )) || true
}

log_warn() {
    ERROR_BUFFER="${ERROR_BUFFER}${ERROR_BUFFER:+$'\n'}[$(date '+%Y-%m-%d %H:%M:%S')] ${HOSTNAME_SHORT} WARN:  $*"
    (( warn_count += 1 )) || true
}

log_info() {
    ERROR_BUFFER="${ERROR_BUFFER}${ERROR_BUFFER:+$'\n'}[$(date '+%Y-%m-%d %H:%M:%S')] ${HOSTNAME_SHORT} INFO:  $*"
}

# ============================================================================
# Helper: run a command, log failures, return UNAVAILABLE on error
# ============================================================================

run_or_log() {
    local description="$1"
    shift
    local output
    if ! output=$("$@" 2>&1); then
        log_error "$description failed: $(printf '%s' "$output" | head -1)"
        echo "UNAVAILABLE"
        return 1
    fi
    if [ -z "$output" ]; then
        log_warn "$description returned empty output"
        echo "UNAVAILABLE"
        return 1
    fi
    echo "$output"
}

# ============================================================================
# Helper: quote a value for safe CSV output
# Wraps the value in double-quotes and escapes any embedded double-quotes.
# ============================================================================

csv_field() {
    printf '"%s"' "${1//\"/\"\"}"
}

# ============================================================================
# Command abstraction layer — IB_ENV=mock reads from MOCK_DIR instead of
# calling real hardware commands. SYS_ROOT redirects /sys reads.
# See CLAUDE.md for the full pattern specification.
# ============================================================================

SYS_ROOT="${SYS_ROOT:-/sys}"

get_ip_link() {
    if [[ "${IB_ENV:-}" == "mock" ]]; then
        cat "${MOCK_DIR}/ip_link.out"
    else
        ip link
    fi
}

get_dmidecode() {
    if [[ "${IB_ENV:-}" == "mock" ]]; then
        cat "${MOCK_DIR}/dmidecode_t1.out"
    else
        dmidecode -t1
    fi
}

get_lsb_release() {
    if [[ "${IB_ENV:-}" == "mock" ]]; then
        cat "${MOCK_DIR}/lsb_release.out"
    else
        lsb_release -d
    fi
}

get_lspci_list() {
    if [[ "${IB_ENV:-}" == "mock" ]]; then
        cat "${MOCK_DIR}/lspci.out"
    else
        lspci
    fi
}

get_lspci_slot() {
    local slot="$1"
    if [[ "${IB_ENV:-}" == "mock" ]]; then
        grep "^${slot} " "${MOCK_DIR}/lspci.out"
    else
        lspci -s "$slot"
    fi
}

get_rpm_qa() {
    if [[ "${IB_ENV:-}" == "mock" ]]; then
        cat "${MOCK_DIR}/rpm_qa.out"
    else
        rpm -qa
    fi
}

get_ofed_info() {
    if [[ "${IB_ENV:-}" == "mock" ]]; then
        cat "${MOCK_DIR}/ofed_info.out"
    else
        ofed_info -s
    fi
}

get_ethtool_fw() {
    local iface="$1"
    if [[ "${IB_ENV:-}" == "mock" ]]; then
        cat "${MOCK_DIR}/ethtool_i_${iface}.out" 2>/dev/null \
            || cat "${MOCK_DIR}/ethtool_i.out"
    else
        ethtool -i "$iface"
    fi
}

log_info "ib_info.sh started on ${HOSTNAME_SHORT}"

# ============================================================================
# Check for required tools upfront (skipped in mock mode)
# ============================================================================

REQUIRED_TOOLS=(lspci ethtool dmidecode)
OPTIONAL_TOOLS=(ofed_info lsb_release)

if [[ "${IB_ENV:-}" != "mock" ]]; then
    for cmd in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required tool '$cmd' not found — some fields will be UNAVAILABLE"
        fi
    done

    for cmd in "${OPTIONAL_TOOLS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_warn "Optional tool '$cmd' not found — some fields will be UNAVAILABLE"
        fi
    done
fi

# ============================================================================
# Gather system information
# ============================================================================

# Get Hostname
host=$(run_or_log "hostname" hostname) || true

# Get InfiniBand link name
linkinfo=$(get_ip_link 2>/dev/null | grep "^[0-9]*: ib" | grep " UP " | awk '{print $2}' | sed 's/://') || true
link=$(echo "$linkinfo" | awk '{print $1}')

if [ -z "$link" ]; then
    log_error "InfiniBand interface not found (no IB link in UP state)"
    link="UNAVAILABLE"
fi

# Get system details using dmidecode (single call; parse with field delimiter)
if [[ "${IB_ENV:-}" == "mock" ]] || command -v dmidecode &>/dev/null; then
    _dmi=$(get_dmidecode 2>/dev/null) || true
    serial=$(echo "$_dmi" | awk -F: '/Serial Number/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}') || true
    model=$(echo "$_dmi"  | awk -F: '/Product Name/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')  || true
    [ -z "$serial" ] && serial="UNAVAILABLE" && log_warn "Could not determine serial number"
    [ -z "$model" ]  && model="UNAVAILABLE"  && log_warn "Could not determine system model"
else
    serial="UNAVAILABLE"
    model="UNAVAILABLE"
    log_warn "Serial number unavailable — dmidecode not found"
    log_warn "System model unavailable — dmidecode not found"
fi

# Get OS details using lsb_release
os=""
if [[ "${IB_ENV:-}" == "mock" ]] || command -v lsb_release &>/dev/null; then
    os=$(get_lsb_release 2>/dev/null | awk -F: '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}') || true
fi

# Fallback to /etc/os-release
if [ -z "$os" ]; then
    os=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | awk -F= '{print $2}' | sed 's/"//g') || true
fi

if [ -z "$os" ]; then
    log_warn "Could not determine OS version"
    os="UNAVAILABLE"
fi

# Get Kernel version
kernel=$(uname -r 2>/dev/null) || kernel="UNAVAILABLE"

# ============================================================================
# Get Mellanox card info
# ============================================================================

cardmodels=""
if [[ "${IB_ENV:-}" == "mock" ]] || command -v lspci &>/dev/null; then
    cardmodels=$(get_lspci_list 2>/dev/null | grep Mellanox | grep -v "Ethernet controller" | awk '{print $1}' | sed 's/^[0-9a-fA-F]\{4\}://g' | sort -u) || true
fi

if [ -z "$cardmodels" ]; then
    log_error "No Mellanox cards found"
    # Output a single row with UNAVAILABLE card info
    echo "$(csv_field "$host"),$(csv_field "$serial"),$(csv_field "$model"),$(csv_field "$os"),$(csv_field "$kernel"),$(csv_field "UNAVAILABLE"),$(csv_field "UNAVAILABLE"),$(csv_field "UNAVAILABLE"),$(csv_field "UNAVAILABLE"),$(csv_field "UNAVAILABLE")"
    log_info "Completed with ${error_count} error(s), ${warn_count} warning(s)"
    exit 1
fi

# ============================================================================
# Determine driver type and OFED versions (installed vs loaded)
# ============================================================================

driver=$(get_rpm_qa 2>/dev/null | grep -i infiniband) || true

if [[ "$driver" =~ mlnx ]]; then
    drivertype="MOFED"
else
    drivertype="Linux OFED"
fi

# Installed OFED version
if [[ "${IB_ENV:-}" == "mock" ]] || command -v ofed_info &>/dev/null; then
    installed_ofed=$(get_ofed_info 2>/dev/null | tr -d '[:space:]') || true
    [ -z "$installed_ofed" ] && installed_ofed="UNAVAILABLE" && log_warn "ofed_info returned empty output"
else
    installed_ofed="UNAVAILABLE"
fi

# Loaded OFED version (what the kernel is actually running)
if [ -f "${SYS_ROOT}/module/mlx5_core/version" ]; then
    loaded_ofed=$(cat "${SYS_ROOT}/module/mlx5_core/version" 2>/dev/null | tr -d '[:space:]') || loaded_ofed="UNAVAILABLE"
else
    loaded_ofed="UNAVAILABLE"
    log_warn "mlx5_core module version not found in ${SYS_ROOT}/module/"
fi

# Check for mismatch — normalize installed_ofed to a bare version string
# before comparing.  ofed_info -s returns e.g. "MLNX_OFED_LINUX-5.8-4.1.5.0:"
# while mlx5_core/version returns e.g. "5.8-4.1.5".
if [ "$installed_ofed" != "UNAVAILABLE" ] && [ "$loaded_ofed" != "UNAVAILABLE" ]; then
    _installed_norm="${installed_ofed#MLNX_OFED_LINUX-}"
    _installed_norm="${_installed_norm%:}"
    if [ "$_installed_norm" != "$loaded_ofed" ]; then
        log_warn "OFED version mismatch: installed=${installed_ofed} loaded=${loaded_ofed} — reboot or 'systemctl restart openibd' may be needed"
    fi
fi

# ============================================================================
# Iterate over unique Mellanox cards and output CSV
# ============================================================================

_seen_cards=""

for cardid in $cardmodels; do
    # Identify the unique PCI ID by stripping off the function suffix (.0, .1, etc.)
    base_cardid="${cardid%.[0-9]}"

    # If this base ID hasn't been seen before, it's a new unique card
    if [[ ":${_seen_cards}:" != *":${base_cardid}:"* ]]; then
        _seen_cards="${_seen_cards:+${_seen_cards}:}${base_cardid}"

        # Get card model for this PCI slot
        if [[ "${IB_ENV:-}" == "mock" ]] || command -v lspci &>/dev/null; then
            cardmodel=$(get_lspci_slot "${cardid}" 2>/dev/null | sed 's/^[^:]*:[^:]*: //') || true
            [ -z "$cardmodel" ] && cardmodel="UNAVAILABLE" && log_warn "Could not get card model for PCI slot ${cardid}"
        else
            cardmodel="UNAVAILABLE"
        fi

        # Find the IB interface associated with this PCI device and get its firmware
        cardfirmware="UNAVAILABLE"
        card_iface=""
        for _devpath in "${SYS_ROOT}"/class/infiniband/*/device; do
            [ -e "$_devpath" ] || continue
            _pci_slot=$(basename "$(readlink -f "$_devpath")" 2>/dev/null) || continue
            # Strip function suffix (.0, .1, etc.) and domain prefix (e.g. 0000:) for comparison
            _pci_base="${_pci_slot%.[0-9]}"
            _pci_base="${_pci_base#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]:}"
            if [[ "$_pci_base" == "$base_cardid" ]]; then
                card_iface="$(basename "$(dirname "$_devpath")")"
                break
            fi
        done

        if [[ -n "$card_iface" ]]; then
            # Get the network interface for this IB device
            net_iface=$(find "${SYS_ROOT}/class/infiniband/${card_iface}/device/net/" -maxdepth 1 -mindepth 1 -printf '%f\n' 2>/dev/null | head -1) || true
            if [[ -n "$net_iface" ]]; then
                cardfirmware=$(get_ethtool_fw "$net_iface" 2>/dev/null | awk -F: '/^firmware-version/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}') || true
            elif [[ "$link" != "UNAVAILABLE" ]]; then
                cardfirmware=$(get_ethtool_fw "$link" 2>/dev/null | awk -F: '/^firmware-version/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}') || true
            fi
        elif [[ "$link" != "UNAVAILABLE" ]]; then
            # Fallback to the first IB link
            cardfirmware=$(get_ethtool_fw "$link" 2>/dev/null | awk -F: '/^firmware-version/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}') || true
        fi

        [ -z "$cardfirmware" ] && cardfirmware="UNAVAILABLE" && log_warn "Could not get firmware version for card ${base_cardid}"

        # Output collected information in CSV format for each unique card
        csv_line="$(csv_field "$host"),$(csv_field "$serial"),$(csv_field "$model"),$(csv_field "$os"),$(csv_field "$kernel"),$(csv_field "$cardmodel"),$(csv_field "$drivertype"),$(csv_field "$installed_ofed"),$(csv_field "$loaded_ofed"),$(csv_field "$cardfirmware")"
        echo "$csv_line"
    fi
done

# ============================================================================
# Summary and exit
# ============================================================================

log_info "Completed with ${error_count} error(s), ${warn_count} warning(s)"

if [ "$error_count" -gt 0 ]; then
    exit 1
fi
