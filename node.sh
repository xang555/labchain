#!/usr/bin/env bash
# LabChain Node Management Script
# Easy control for Execution Layer (EL), Consensus Layer (CL), and Validator Client (VC)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored messages
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Usage information
usage() {
  cat <<'EOF'
LabChain Node Manager

USAGE:
  ./node.sh <command> [node]

COMMANDS:
  start <node>      Start a node
  stop <node>       Stop a node
  restart <node>    Restart a node
  logs <node>       View node logs (follow mode)
  status            Show status of all nodes
  health            Check network health

NODES:
  el      Execution Layer (Reth)
  cl      Consensus Layer (Lighthouse Beacon)
  vc      Validator Client (Lighthouse VC)
  all     All nodes

EXAMPLES:
  ./node.sh start all         # Start all nodes (EL, CL, VC)
  ./node.sh start el          # Start only EL
  ./node.sh stop vc           # Stop validator client
  ./node.sh logs cl           # View CL logs
  ./node.sh status            # Check status of all nodes

ENVIRONMENT VARIABLES:
  EL:
    BOOTNODES           - Comma-separated list of EL bootnodes (enode://...)
    EL_DATA_DIR         - Path to EL data directory
    GENESIS_DIR         - Path to genesis files
    JWT_SECRET          - Path to JWT secret file

  CL:
    BOOT_NODES          - Comma-separated list of CL bootnodes (enr:...)
    EXECUTION_ENDPOINT  - URL of execution layer RPC
    CL_DATA_DIR         - Path to CL data directory
    CONSENSUS_DIR       - Path to consensus config files

  VC:
    KEYSTORE_DIR        - Path to validator keystores (required)
    BEACON_NODE_ENDPOINTS - URL of beacon node API
    FEE_RECIPIENT       - Fee recipient address

EOF
}

# Get docker compose command for a node
get_compose_cmd() {
  local node=$1

  case $node in
    el)
      echo "docker compose -f EL/docker-compose.yml"
      ;;
    cl)
      echo "docker compose -f CL/docker-compose.yml"
      ;;
    vc)
      echo "docker compose -f VC/docker-compose.yml"
      ;;
    *)
      error "Unknown node: $node"
      return 1
      ;;
  esac
}

# Start a node
start_node() {
  local node=$1

  if [ "$node" = "all" ]; then
    info "Starting all nodes..."
    start_node el
    sleep 5
    start_node cl
    sleep 5
    start_node vc
    success "All nodes started"
    return 0
  fi

  info "Starting $node..."
  local cmd=$(get_compose_cmd "$node")
  eval "$cmd up -d"
  success "$node started"
}

# Stop a node
stop_node() {
  local node=$1

  if [ "$node" = "all" ]; then
    info "Stopping all nodes..."
    stop_node vc 2>/dev/null || true
    stop_node cl 2>/dev/null || true
    stop_node el 2>/dev/null || true
    success "All nodes stopped"
    return 0
  fi

  info "Stopping $node..."
  local cmd=$(get_compose_cmd "$node")
  eval "$cmd down" 2>/dev/null || warn "$node was not running"
  success "$node stopped"
}

# Restart a node
restart_node() {
  local node=$1

  if [ "$node" = "all" ]; then
    info "Restarting all nodes..."
    stop_node all
    sleep 3
    start_node all
    success "All nodes restarted"
    return 0
  fi

  info "Restarting $node..."
  stop_node "$node"
  sleep 2
  start_node "$node"
  success "$node restarted"
}

# View logs
view_logs() {
  local node=$1

  if [ "$node" = "all" ]; then
    info "Showing logs for all running nodes..."
    info "Press Ctrl+C to exit"
    sleep 2

    # Show logs from all running containers
    docker compose -f EL/docker-compose.yml -f CL/docker-compose.yml -f VC/docker-compose.yml logs -f --tail=50
    return 0
  fi

  info "Showing logs for $node - Press Ctrl+C to exit"
  local cmd=$(get_compose_cmd "$node")
  eval "$cmd logs -f --tail=100"
}

# Show status of all nodes
show_status() {
  info "Checking node status..."
  echo ""

  # Check EL
  echo -e "${BLUE}=== Execution Layer (EL) ===${NC}"
  if docker ps --filter "name=reth" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q reth; then
    docker ps --filter "name=reth" --format "table {{.Names}}\t{{.Status}}"

    # Get block number
    BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
      http://localhost:8545 2>/dev/null | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$BLOCK" ]; then
      BLOCK_NUM=$((16#${BLOCK#0x}))
      echo -e "  ${GREEN}✓${NC} Block number: $BLOCK_NUM"
    fi
  else
    echo -e "  ${RED}✗${NC} Not running"
  fi
  echo ""

  # Check CL
  echo -e "${BLUE}=== Consensus Layer (CL) ===${NC}"
  if docker ps --filter "name=lighthouse" --format "table {{.Names}}\t{{.Status}}" | grep -q lighthouse; then
    docker ps --filter "name=lighthouse" --format "table {{.Names}}\t{{.Status}}" | grep -v "\-vc"

    # Get head slot
    if curl -s http://localhost:5052/eth/v1/node/health > /dev/null 2>&1; then
      HEAD_SLOT=$(curl -s http://localhost:5052/eth/v1/beacon/headers/head 2>/dev/null | grep -o '"slot":"[^"]*"' | head -1 | cut -d'"' -f4)
      echo -e "  ${GREEN}✓${NC} Head slot: ${HEAD_SLOT:-0}"
    fi
  else
    echo -e "  ${RED}✗${NC} Not running"
  fi
  echo ""

  # Check VC
  echo -e "${BLUE}=== Validator Client (VC) ===${NC}"
  if docker ps --filter "name=lighthouse-vc" --format "table {{.Names}}\t{{.Status}}" | grep -q lighthouse-vc; then
    docker ps --filter "name=lighthouse-vc" --format "table {{.Names}}\t{{.Status}}"
    echo -e "  ${GREEN}✓${NC} Validator client running"
  else
    echo -e "  ${RED}✗${NC} Not running"
  fi
  echo ""
}

# Check network health
check_health() {
  info "Running health checks..."

  if [ ! -f "./check-engine-api.sh" ]; then
    error "check-engine-api.sh not found"
    return 1
  fi

  ./check-engine-api.sh
}

# Main command handler
main() {
  if [ $# -eq 0 ]; then
    usage
    exit 0
  fi

  local command=$1
  shift

  case $command in
    start)
      if [ $# -eq 0 ]; then
        error "Please specify a node (el/cl/vc/all)"
        exit 1
      fi
      start_node "$@"
      ;;
    stop)
      if [ $# -eq 0 ]; then
        error "Please specify a node (el/cl/vc/all)"
        exit 1
      fi
      stop_node "$@"
      ;;
    restart)
      if [ $# -eq 0 ]; then
        error "Please specify a node (el/cl/vc/all)"
        exit 1
      fi
      restart_node "$@"
      ;;
    logs)
      if [ $# -eq 0 ]; then
        error "Please specify a node (el/cl/vc/all)"
        exit 1
      fi
      view_logs "$@"
      ;;
    status)
      show_status
      ;;
    health)
      check_health
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      error "Unknown command: $command"
      echo ""
      usage
      exit 1
      ;;
  esac
}

main "$@"
