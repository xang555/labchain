#!/usr/bin/env bash
#
# exit-validators.sh - Exit validators and withdraw all funds (stake + rewards)
#
# This script performs voluntary exits for validators on the LabChain network.
# After a successful exit and withdrawal delay, all funds (32 LAB stake + rewards)
# will be sent to the validator's withdrawal address.
#
# Simply run: ./exit-validators.sh
# The script will guide you through the process interactively.
#
set -euo pipefail

# =============================================================================
# Constants
# =============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION="1.0.0"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# =============================================================================
# Default Configuration
# =============================================================================
BEACON_URL="http://localhost:5052"
KEYSTORE_DIR="./managed-keystores"
CONSENSUS_DIR="../config/metadata"
LIGHTHOUSE_IMAGE="sigp/lighthouse:latest"

# =============================================================================
# Logging Functions
# =============================================================================
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================================
# Utility Functions
# =============================================================================
print_header() {
    clear
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║         LabChain Validator Exit Tool v${VERSION}                     ║${NC}"
    echo -e "${BOLD}║                                                                  ║${NC}"
    echo -e "${BOLD}║   Exit validators and withdraw all funds (stake + rewards)      ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_separator() {
    echo ""
    echo -e "${BLUE}──────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

# Prompt for input with default value
prompt_input() {
    local prompt="$1"
    local default="$2"
    local value

    if [[ -n "$default" ]]; then
        echo -ne "  ${prompt} ${CYAN}(default: ${default})${NC}: " >&2
        read -r value
        value="${value:-$default}"
    else
        echo -ne "  ${prompt}: " >&2
        read -r value
    fi

    echo "$value"
}

# Prompt for yes/no
prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local value

    if [[ "$default" == "y" ]]; then
        echo -ne "  ${prompt} ${CYAN}[Y/n]${NC}: " >&2
    else
        echo -ne "  ${prompt} ${CYAN}[y/N]${NC}: " >&2
    fi

    read -r value
    value="${value:-$default}"

    # Convert to lowercase (compatible with bash 3.x)
    value=$(echo "$value" | tr '[:upper:]' '[:lower:]')

    [[ "$value" == "y" || "$value" == "yes" ]]
}

# =============================================================================
# Check Functions
# =============================================================================
check_dependencies() {
    local missing=()

    if ! command -v docker &>/dev/null; then
        missing+=("docker")
    fi

    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    if ! command -v curl &>/dev/null; then
        missing+=("curl")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        echo ""
        echo "  Please install them first:"
        [[ " ${missing[*]} " =~ " docker " ]] && echo "    - Docker: curl -fsSL https://get.docker.com | sh"
        [[ " ${missing[*]} " =~ " jq " ]] && echo "    - jq: sudo apt install jq (Ubuntu) or brew install jq (macOS)"
        [[ " ${missing[*]} " =~ " curl " ]] && echo "    - curl: sudo apt install curl (Ubuntu)"
        echo ""
        exit 1
    fi
}

check_beacon_node() {
    local url="$1"

    info "Checking beacon node at ${url}..."

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "${url}/eth/v1/node/health" 2>/dev/null || echo "000")

    if [[ "$http_code" == "000" ]]; then
        return 1
    fi

    # Check sync status
    local response
    response=$(curl -s "${url}/eth/v1/node/syncing" 2>/dev/null || echo "{}")
    local is_syncing
    is_syncing=$(echo "$response" | jq -r '.data.is_syncing // "unknown"' 2>/dev/null || echo "unknown")

    if [[ "$is_syncing" == "true" ]]; then
        warn "Beacon node is still syncing"
        return 2
    fi

    success "Beacon node is connected and synced"
    return 0
}

# =============================================================================
# Validator Functions
# =============================================================================
get_all_validator_pubkeys() {
    local keystore_dir="$1"
    local validators_dir="${keystore_dir}/validators"
    local pubkeys=()

    if [[ ! -d "$validators_dir" ]]; then
        return
    fi

    for dir in "$validators_dir"/0x*; do
        if [[ -d "$dir" && -f "$dir/voting-keystore.json" ]]; then
            pubkeys+=("$(basename "$dir")")
        fi
    done

    printf '%s\n' "${pubkeys[@]}"
}

get_validator_info() {
    local beacon_url="$1"
    local pubkey="$2"

    curl -s "${beacon_url}/eth/v1/beacon/states/head/validators/${pubkey}" 2>/dev/null || echo "{}"
}

get_validator_status() {
    local beacon_url="$1"
    local pubkey="$2"

    local response
    response=$(get_validator_info "$beacon_url" "$pubkey")
    echo "$response" | jq -r '.data.status // "unknown"' 2>/dev/null || echo "unknown"
}

get_validator_activation_epoch() {
    local beacon_url="$1"
    local pubkey="$2"

    local response
    response=$(get_validator_info "$beacon_url" "$pubkey")
    echo "$response" | jq -r '.data.validator.activation_epoch // "0"' 2>/dev/null || echo "0"
}

get_current_epoch() {
    local beacon_url="$1"

    local response
    response=$(curl -s "${beacon_url}/eth/v1/beacon/headers/head" 2>/dev/null || echo "{}")
    local slot
    slot=$(echo "$response" | jq -r '.data.header.message.slot // "0"' 2>/dev/null || echo "0")

    # Epoch = slot / 32 (slots per epoch)
    echo $((slot / 32))
}

check_exit_eligibility() {
    local beacon_url="$1"
    local pubkey="$2"

    # Constants (standard Ethereum PoS)
    local SHARD_COMMITTEE_PERIOD=256  # Minimum epochs before exit is allowed

    local current_epoch
    current_epoch=$(get_current_epoch "$beacon_url")

    local activation_epoch
    activation_epoch=$(get_validator_activation_epoch "$beacon_url" "$pubkey")

    # Check if activation_epoch is valid
    if [[ "$activation_epoch" == "0" || "$activation_epoch" == "null" || -z "$activation_epoch" ]]; then
        echo "unknown"
        return
    fi

    local eligible_epoch=$((activation_epoch + SHARD_COMMITTEE_PERIOD))

    if [[ $current_epoch -ge $eligible_epoch ]]; then
        echo "eligible"
    else
        local epochs_remaining=$((eligible_epoch - current_epoch))
        # Each epoch is ~6.4 minutes (32 slots * 12 seconds)
        local minutes_remaining=$((epochs_remaining * 32 * 12 / 60))
        local hours_remaining=$((minutes_remaining / 60))
        local mins=$((minutes_remaining % 60))

        if [[ $hours_remaining -gt 0 ]]; then
            echo "not_eligible:${eligible_epoch}:~${hours_remaining}h ${mins}m"
        else
            echo "not_eligible:${eligible_epoch}:~${minutes_remaining}m"
        fi
    fi
}

get_validator_index() {
    local beacon_url="$1"
    local pubkey="$2"

    local response
    response=$(get_validator_info "$beacon_url" "$pubkey")
    echo "$response" | jq -r '.data.index // "N/A"' 2>/dev/null || echo "N/A"
}

get_validator_balance() {
    local beacon_url="$1"
    local pubkey="$2"

    local response
    response=$(get_validator_info "$beacon_url" "$pubkey")
    local balance_gwei
    balance_gwei=$(echo "$response" | jq -r '.data.balance // "0"' 2>/dev/null || echo "0")

    if [[ "$balance_gwei" != "0" && "$balance_gwei" != "" && "$balance_gwei" != "null" ]]; then
        echo "scale=4; $balance_gwei / 1000000000" | bc 2>/dev/null || echo "${balance_gwei} Gwei"
    else
        echo "0"
    fi
}

get_withdrawal_address() {
    local beacon_url="$1"
    local pubkey="$2"

    local response
    response=$(get_validator_info "$beacon_url" "$pubkey")
    local withdrawal_creds
    withdrawal_creds=$(echo "$response" | jq -r '.data.validator.withdrawal_credentials // empty' 2>/dev/null || echo "")

    if [[ "$withdrawal_creds" == 0x01* ]]; then
        echo "0x${withdrawal_creds: -40}"
    else
        echo "${withdrawal_creds:-Not set}"
    fi
}

# =============================================================================
# Display Functions
# =============================================================================
display_validators() {
    local beacon_url="$1"
    shift
    local pubkeys=("$@")

    echo ""
    echo -e "${BOLD}Found ${#pubkeys[@]} validator(s):${NC}"
    echo ""

    local idx=1
    for pubkey in "${pubkeys[@]}"; do
        local status balance index withdrawal_addr eligibility
        status=$(get_validator_status "$beacon_url" "$pubkey")
        balance=$(get_validator_balance "$beacon_url" "$pubkey")
        index=$(get_validator_index "$beacon_url" "$pubkey")
        withdrawal_addr=$(get_withdrawal_address "$beacon_url" "$pubkey")
        eligibility=$(check_exit_eligibility "$beacon_url" "$pubkey")

        # Status color
        local status_color="${NC}"
        case "$status" in
            active_ongoing) status_color="${GREEN}" ;;
            active_exiting|exited*) status_color="${YELLOW}" ;;
            withdrawal*) status_color="${CYAN}" ;;
            *) status_color="${RED}" ;;
        esac

        # Eligibility display
        local eligibility_display=""
        if [[ "$eligibility" == "eligible" ]]; then
            eligibility_display="${GREEN}Eligible for exit${NC}"
        elif [[ "$eligibility" == "unknown" ]]; then
            eligibility_display="${YELLOW}Unknown${NC}"
        else
            # Parse not_eligible:epoch:time_remaining
            local eligible_epoch time_remaining
            eligible_epoch=$(echo "$eligibility" | cut -d':' -f2)
            time_remaining=$(echo "$eligibility" | cut -d':' -f3)
            eligibility_display="${RED}Not eligible until epoch ${eligible_epoch} (${time_remaining})${NC}"
        fi

        echo -e "  ${BOLD}[$idx]${NC} ${pubkey:0:20}...${pubkey: -8}"
        echo -e "      Index: ${index} | Status: ${status_color}${status}${NC} | Balance: ${balance} LAB"
        echo -e "      Withdrawal: ${withdrawal_addr}"
        echo -e "      Exit eligibility: ${eligibility_display}"
        echo ""

        idx=$((idx + 1))
    done
}

# =============================================================================
# Exit Function
# =============================================================================
perform_exit() {
    local beacon_url="$1"
    local keystore_dir="$2"
    local consensus_dir="$3"
    local pubkey="$4"

    local keystore_path="${keystore_dir}/validators/${pubkey}/voting-keystore.json"
    local password_file="${keystore_dir}/secrets/${pubkey}"

    if [[ ! -f "$keystore_path" ]]; then
        error "Keystore not found: ${keystore_path}"
        return 1
    fi

    if [[ ! -f "$password_file" ]]; then
        error "Password file not found: ${password_file}"
        return 1
    fi

    # Get absolute paths
    local keystore_abs consensus_abs
    keystore_abs="$(cd "$(dirname "$keystore_path")" && pwd)"
    consensus_abs="$(cd "$consensus_dir" && pwd)"

    # Create temp directory
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" RETURN

    # Copy files to temp location
    mkdir -p "$temp_dir/validators/${pubkey}"
    mkdir -p "$temp_dir/secrets"
    cp "${keystore_abs}/voting-keystore.json" "$temp_dir/validators/${pubkey}/"
    cp "$password_file" "$temp_dir/secrets/${pubkey}"

    info "Broadcasting voluntary exit for ${pubkey:0:20}..."

    # Execute voluntary exit
    docker run --rm \
        -v "$temp_dir/validators:/validators:ro" \
        -v "$temp_dir/secrets:/secrets:ro" \
        -v "$consensus_abs:/consensus:ro" \
        --network host \
        "$LIGHTHOUSE_IMAGE" \
        lighthouse \
        account validator exit \
        --testnet-dir /consensus \
        --keystore "/validators/${pubkey}/voting-keystore.json" \
        --password-file "/secrets/${pubkey}" \
        --beacon-node "$beacon_url" \
        --no-confirmation

    return $?
}

# =============================================================================
# Main Interactive Flow
# =============================================================================
main() {
    print_header

    # Check dependencies
    info "Checking required tools..."
    check_dependencies
    success "All required tools are installed"

    print_separator

    # Step 1: Configure beacon node
    echo -e "${BOLD}Step 1: Beacon Node Configuration${NC}"
    echo ""

    local beacon_connected=false
    while [[ "$beacon_connected" == "false" ]]; do
        BEACON_URL=$(prompt_input "Beacon node URL" "$BEACON_URL")

        if check_beacon_node "$BEACON_URL"; then
            beacon_connected=true
        else
            echo ""
            warn "Cannot connect to beacon node at ${BEACON_URL}"
            if ! prompt_yes_no "Try a different URL?" "y"; then
                error "Beacon node is required to exit validators"
                exit 1
            fi
            echo ""
        fi
    done

    print_separator

    # Step 2: Configure keystore directory
    echo -e "${BOLD}Step 2: Keystore Configuration${NC}"
    echo ""

    local keystore_valid=false
    while [[ "$keystore_valid" == "false" ]]; do
        KEYSTORE_DIR=$(prompt_input "Keystore directory" "$KEYSTORE_DIR")

        # Convert to absolute path if relative
        if [[ ! "$KEYSTORE_DIR" = /* ]]; then
            KEYSTORE_DIR="${SCRIPT_DIR}/${KEYSTORE_DIR}"
        fi

        if [[ -d "${KEYSTORE_DIR}/validators" && -d "${KEYSTORE_DIR}/secrets" ]]; then
            keystore_valid=true
            success "Keystore directory found: ${KEYSTORE_DIR}"
        else
            echo ""
            warn "Invalid keystore directory (missing validators/ or secrets/ folder)"
            if ! prompt_yes_no "Try a different directory?" "y"; then
                exit 1
            fi
            KEYSTORE_DIR="./managed-keystores"
            echo ""
        fi
    done

    # Check consensus directory
    if [[ ! "$CONSENSUS_DIR" = /* ]]; then
        CONSENSUS_DIR="${SCRIPT_DIR}/${CONSENSUS_DIR}"
    fi

    if [[ ! -d "$CONSENSUS_DIR" ]]; then
        error "Consensus directory not found: ${CONSENSUS_DIR}"
        exit 1
    fi

    print_separator

    # Step 3: Discover validators
    echo -e "${BOLD}Step 3: Select Validators to Exit${NC}"
    echo ""

    info "Scanning keystore directory..."

    mapfile -t ALL_PUBKEYS < <(get_all_validator_pubkeys "$KEYSTORE_DIR")

    if [[ ${#ALL_PUBKEYS[@]} -eq 0 ]]; then
        error "No validators found in ${KEYSTORE_DIR}"
        exit 1
    fi

    display_validators "$BEACON_URL" "${ALL_PUBKEYS[@]}"

    # Ask which validators to exit
    echo -e "${BOLD}Which validators do you want to exit?${NC}"
    echo ""
    echo "  1) Exit ALL validators (${#ALL_PUBKEYS[@]} total)"
    echo "  2) Select specific validators by number"
    echo "  3) Enter validator public key manually"
    echo "  4) Cancel and exit"
    echo ""

    local choice
    choice=$(prompt_input "Your choice" "1")

    local SELECTED_PUBKEYS=()

    case "$choice" in
        1)
            SELECTED_PUBKEYS=("${ALL_PUBKEYS[@]}")
            ;;
        2)
            echo ""
            echo "  Enter validator numbers separated by comma (e.g., 1,3,5)"
            local numbers
            numbers=$(prompt_input "Validator numbers" "")

            if [[ -z "$numbers" ]]; then
                error "No validators selected"
                exit 1
            fi

            IFS=',' read -ra NUM_ARRAY <<< "$numbers"
            for num in "${NUM_ARRAY[@]}"; do
                num=$(echo "$num" | tr -d ' ')
                local idx=$((num - 1))
                if [[ $idx -ge 0 && $idx -lt ${#ALL_PUBKEYS[@]} ]]; then
                    SELECTED_PUBKEYS+=("${ALL_PUBKEYS[$idx]}")
                else
                    warn "Invalid number: ${num} (skipping)"
                fi
            done
            ;;
        3)
            echo ""
            local manual_pubkey
            manual_pubkey=$(prompt_input "Enter validator public key (0x...)" "")

            if [[ -z "$manual_pubkey" ]]; then
                error "No public key entered"
                exit 1
            fi

            # Normalize pubkey
            manual_pubkey="${manual_pubkey#0x}"
            manual_pubkey="0x${manual_pubkey}"
            SELECTED_PUBKEYS+=("$manual_pubkey")
            ;;
        4|*)
            info "Exit cancelled"
            exit 0
            ;;
    esac

    if [[ ${#SELECTED_PUBKEYS[@]} -eq 0 ]]; then
        error "No validators selected"
        exit 1
    fi

    print_separator

    # Step 4: Confirmation
    echo -e "${BOLD}Step 4: Confirm Exit${NC}"
    echo ""

    echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║                        ⚠️  WARNING ⚠️                              ║${NC}"
    echo -e "${RED}${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}${BOLD}║${NC}                                                                  ${RED}${BOLD}║${NC}"
    echo -e "${RED}${BOLD}║${NC}  You are about to exit ${BOLD}${#SELECTED_PUBKEYS[@]}${NC} validator(s)                            ${RED}${BOLD}║${NC}"
    echo -e "${RED}${BOLD}║${NC}                                                                  ${RED}${BOLD}║${NC}"
    echo -e "${RED}${BOLD}║${NC}  ${BOLD}THIS ACTION IS IRREVERSIBLE!${NC}                                   ${RED}${BOLD}║${NC}"
    echo -e "${RED}${BOLD}║${NC}                                                                  ${RED}${BOLD}║${NC}"
    echo -e "${RED}${BOLD}║${NC}  After exiting:                                                  ${RED}${BOLD}║${NC}"
    echo -e "${RED}${BOLD}║${NC}  • Validator cannot be reactivated with same keys                ${RED}${BOLD}║${NC}"
    echo -e "${RED}${BOLD}║${NC}  • Must wait for withdrawal delay (~27+ hours)                   ${RED}${BOLD}║${NC}"
    echo -e "${RED}${BOLD}║${NC}  • Funds (32 LAB + rewards) sent to withdrawal address           ${RED}${BOLD}║${NC}"
    echo -e "${RED}${BOLD}║${NC}                                                                  ${RED}${BOLD}║${NC}"
    echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "  Selected validators:"
    local eligible_count=0
    local not_eligible_count=0
    for pk in "${SELECTED_PUBKEYS[@]}"; do
        local elig
        elig=$(check_exit_eligibility "$BEACON_URL" "$pk")
        if [[ "$elig" == "eligible" ]]; then
            echo -e "    ${GREEN}✓${NC} ${pk:0:20}...${pk: -8} - Eligible"
            eligible_count=$((eligible_count + 1))
        elif [[ "$elig" == "unknown" ]]; then
            echo -e "    ${YELLOW}?${NC} ${pk:0:20}...${pk: -8} - Unknown"
        else
            local time_remaining
            time_remaining=$(echo "$elig" | cut -d':' -f3)
            echo -e "    ${RED}✗${NC} ${pk:0:20}...${pk: -8} - Not eligible (${time_remaining})"
            not_eligible_count=$((not_eligible_count + 1))
        fi
    done
    echo ""

    if [[ $not_eligible_count -gt 0 ]]; then
        echo -e "  ${YELLOW}Note: ${not_eligible_count} validator(s) are not yet eligible and will be skipped.${NC}"
        echo ""
    fi

    if [[ $eligible_count -eq 0 ]]; then
        echo -e "  ${RED}No validators are currently eligible for exit.${NC}"
        echo -e "  ${YELLOW}Validators must be active for ~27 hours before they can exit.${NC}"
        echo ""
        info "Exiting..."
        exit 0
    fi

    echo -e "  ${YELLOW}To confirm, type '${BOLD}yes${NC}${YELLOW}':${NC}"
    local confirm
    read -r -p "  > " confirm

    # Convert to lowercase (compatible with bash 3.x)
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')

    if [[ "$confirm" != "yes" ]]; then
        info "Exit cancelled by user"
        exit 0
    fi

    print_separator

    # Step 5: Execute exits
    echo -e "${BOLD}Step 5: Executing Voluntary Exits${NC}"
    echo ""

    local success_count=0
    local fail_count=0
    local skip_count=0
    local total=${#SELECTED_PUBKEYS[@]}

    for i in "${!SELECTED_PUBKEYS[@]}"; do
        local pubkey="${SELECTED_PUBKEYS[$i]}"
        local num=$((i + 1))

        echo ""
        echo -e "${CYAN}[${num}/${total}]${NC} Processing ${pubkey:0:20}...${pubkey: -8}"

        # Check status first
        local status
        status=$(get_validator_status "$BEACON_URL" "$pubkey")

        if [[ "$status" == "exited"* || "$status" == "withdrawal"* ]]; then
            warn "Already exited (status: ${status}). Skipping."
            skip_count=$((skip_count + 1))
            continue
        fi

        if [[ "$status" != "active_ongoing" && "$status" != "active_slashed" ]]; then
            warn "Not in active state (status: ${status}). Skipping."
            skip_count=$((skip_count + 1))
            continue
        fi

        # Check exit eligibility
        local eligibility
        eligibility=$(check_exit_eligibility "$BEACON_URL" "$pubkey")

        if [[ "$eligibility" != "eligible" && "$eligibility" != "unknown" ]]; then
            local eligible_epoch time_remaining
            eligible_epoch=$(echo "$eligibility" | cut -d':' -f2)
            time_remaining=$(echo "$eligibility" | cut -d':' -f3)
            warn "Not eligible for exit yet!"
            echo -e "      ${YELLOW}Validator must wait until epoch ${eligible_epoch}${NC}"
            echo -e "      ${YELLOW}Estimated time remaining: ${time_remaining}${NC}"
            echo ""
            skip_count=$((skip_count + 1))
            continue
        fi

        if perform_exit "$BEACON_URL" "$KEYSTORE_DIR" "$CONSENSUS_DIR" "$pubkey"; then
            success "Exit broadcast successful!"
            success_count=$((success_count + 1))
        else
            error "Exit failed!"
            fail_count=$((fail_count + 1))
        fi

        # Delay between exits
        if [[ $num -lt $total ]]; then
            sleep 2
        fi
    done

    print_separator

    # Summary
    echo -e "${BOLD}Exit Summary${NC}"
    echo ""
    echo -e "  ${GREEN}✓ Successful:${NC} ${success_count}"
    echo -e "  ${RED}✗ Failed:${NC}     ${fail_count}"
    echo -e "  ${YELLOW}⊘ Skipped:${NC}    ${skip_count}"
    echo ""

    if [[ $success_count -gt 0 ]]; then
        echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}${BOLD}║                   EXIT PROCESS STARTED                           ║${NC}"
        echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}${BOLD}║${NC}  Your validator(s) will now go through:                          ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}                                                                  ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}  1. Exit queue (varies by network congestion)                    ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}  2. Exit processing (~27 hours minimum)                          ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}  3. Withdrawal delay (~27 hours after exit)                      ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}  4. Funds sent to your withdrawal address                        ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}                                                                  ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}  Check status: curl ${BEACON_URL}/eth/v1/beacon/states/head/validators/<pubkey>"
        echo -e "${GREEN}${BOLD}║${NC}  Or view on explorer: https://explorer.labchain.la               ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    fi

    echo ""
}

# Run main
main
