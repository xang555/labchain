# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LAB Chain is a Proof-of-Stake Ethereum-compatible blockchain (Chain ID: 5222). This repository provides Docker-based infrastructure for running nodes on the network. It is **not a traditional software project** - it's a blockchain node operator toolkit.

## Architecture

The project consists of three layered components:

### 1. Execution Layer (EL) - Reth
- Processes transactions and smart contracts
- Exposes JSON-RPC on port 8545, WebSocket on 8546
- Engine API (auth RPC) on port 8551 for Consensus Layer communication
- P2P networking on port 30303
- Directory: `EL/`

### 2. Consensus Layer (CL) - Lighthouse Beacon Node
- Runs proof-of-stake consensus
- Connects to EL via JWT-authenticated engine API
- HTTP API on port 5052
- P2P networking on port 9000
- Supports two discovery modes: `enr` (default) or `libp2p`
- Directory: `CL/`

### 3. Validator Client (VC) - Lighthouse VC
- Manages validator keystores and attestations
- Connects to CL via REST API
- Requires 32 LAB deposit per validator to activate
- Directory: `VC/`

**Key Architecture Points:**
- All containers run on `labchain-net` Docker network
- EL and CL communicate via JWT secret at `config/jwt/jwtsecret`
- Pre-configured bootnode addresses are in `.env` files
- Genesis/config files in `config/metadata/` define the network

## Node Management Commands

The main entry point is `./node.sh`:

```bash
# Configuration (optional - defaults are pre-configured)
./node.sh init el|cl|vc|all

# Start/stop/restart nodes
./node.sh start el|cl|vc|all
./node.sh stop el|cl|vc|all
./node.sh restart el|cl|vc|all

# View logs (follow mode)
./node.sh logs el|cl|vc|all

# Check status
./node.sh status
./node.sh health
```

## Validator Management

Located in `VC/` directory:

```bash
cd VC

# Generate validator keystores (interactive)
./manage-validators.sh

# Deposit 32 LAB per validator to activate
./broadcast-deposits.sh

# Exit validators and withdraw funds
./exit-validators.sh
```

## Configuration Files

Each layer has its own `.env` file:
- `EL/.env` - HTTP_PORT, WS_PORT, AUTHRPC_PORT, P2P_PORT, BOOTNODE_ENODE
- `CL/.env` - EXECUTION_ENDPOINT, HTTP_PORT, P2P_PORT, DISCOVERY_MODE, BOOTNODE_ENR/LIBP2P
- `VC/.env` - BEACON_NODE_ENDPOINTS, FEE_RECIPIENT, KEYSTORE_DIR

## Network Information

- Chain ID: `5222`
- Network Name: `lab-chain`
- Deposit Contract: `0x5454545454545454545454545454545454545454`
- Explorer: https://explorer.labchain.la
- Slot Duration: 12 seconds

## Bootnode Scripts

To share your node as a bootnode for others:

```bash
cd EL
./get-bootnode-enode.sh  # Returns enode URL

cd CL
./get-bootnode-enr.sh    # Returns ENR record
```

## Important Notes

- This is a **blockchain infrastructure** project, not a traditional application
- Pre-configured settings work out of the box - `./node.sh init` is optional
- Changes to genesis files affect the entire network - be extremely careful
- JWT secret must be identical between EL and CL for them to communicate
- Validator exits are **irreversible** and take ~27 hours minimum
