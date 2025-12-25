# LabChain - Join the Network

Welcome to LabChain! This guide will help you join our network as a node operator or validator.

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Network Information](#network-information)
- [Run a Full Node (EL + CL)](#run-a-full-node-el--cl)
- [Run a Beacon Node (CL Only)](#run-a-beacon-node-cl-only)
- [Run a Validator (VC Only)](#run-a-validator-vc-only)
- [Useful Commands](#useful-commands)
- [Troubleshooting](#troubleshooting)

---

## Overview

LabChain is a Proof-of-Stake Ethereum network. There are three types of nodes you can run:

| Node Type | What It Does | When to Use |
|-----------|--------------|-------------|
| **Full Node** | Runs EL + CL together | You want to run your own complete node |
| **Beacon Node** | Runs CL only | You have access to an external EL |
| **Validator** | Runs VC only | You have access to an external Beacon Node and want to validate |

**Components:**
- **Execution Layer (EL)**: Reth - processes transactions and smart contracts
- **Consensus Layer (CL)**: Lighthouse Beacon Node - handles proof-of-stake consensus
- **Validator Client (VC)**: Lighthouse VC - proposes and attests to blocks

---

## Prerequisites

Before you begin, make sure you have:

**1. Docker & Docker Compose**
```bash
# Verify installation
docker --version
docker compose version
```

**2. Foundry (for validators only)**
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Verify installation
cast --version
```

**3. jq (for validators only)**
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq
```

**4. Minimum Hardware**
- CPU: 4 cores
- RAM: 8 GB
- Storage: 100 GB SSD

**5. Network Ports** (open in your firewall)
- `30303` (TCP/UDP) - EL peer discovery
- `9000` (TCP/UDP) - CL peer discovery

---

## Network Information

| Parameter | Value |
|-----------|-------|
| Network Name | `lab-chain` |
| Chain ID | `5222` |
| Slot Duration | 12 seconds |
| Deposit Contract | `0x5454545454545454545454545454545454545454` |

**Bootnodes:**

```bash
# EL Bootnode (enode)
enode://CONTACT_ADMIN_FOR_ENODE@BOOTNODE_IP:30303

# CL Bootnode (ENR)
enr:-Iq4QJk4WqRkjsX5c2CXtOra6HnxN-BMXnWhmhEQO9Bn9iABTJGdjUOurM7Btj1ouKaFkvTRoju5vz2GPmVON2dffQKGAX53x8JigmlkgnY0gmlwhLKAlv6Jc2VjcDI1NmsxoQK6S-Cii_KmfFdUJL2TANL3ksaKUnNXvTCv1tLwXs0QgIN1ZHCCIyk
```

---

## Run a Full Node (EL + CL)

A Full Node runs both the Execution Layer and Consensus Layer together. Follow these steps:

### Step 1: Clone the Repository

```bash
git clone https://github.com/YOUR_ORG/labchain.git
cd labchain
```

### Step 2: Create Docker Network

```bash
docker network create labchain-net
```

### Step 3: Generate JWT Secret

The JWT secret secures communication between EL and CL.

```bash
mkdir -p config/jwt
openssl rand -hex 32 > config/jwt/jwtsecret
```

### Step 4: Configure EL Environment

```bash
cd EL
cp .env.example .env   # if exists, or create new
```

Edit `EL/.env`:

```bash
# EL/.env
RETH_IMAGE=ghcr.io/paradigmxyz/reth:latest
RETH_LOG_LEVEL=info

# Ports
HTTP_PORT=8545
WS_PORT=8546
AUTHRPC_PORT=8551
P2P_PORT=30303

# Add network bootnodes (get from network admin)
BOOTNODES=enode://CONTACT_ADMIN_FOR_ENODE@BOOTNODE_IP:30303
```

### Step 5: Start the Execution Layer

```bash
cd ..
./node.sh start el
```

Wait for EL to initialize (about 30 seconds).

```bash
# Check EL is running
./node.sh logs el
```

### Step 6: Configure CL Environment

```bash
cd CL
cp .env.example .env   # if exists, or create new
```

Edit `CL/.env`:

```bash
# CL/.env
LIGHTHOUSE_IMAGE=sigp/lighthouse:latest
LIGHTHOUSE_LOG_LEVEL=info

# Connect to your local EL
EXECUTION_ENDPOINT=http://reth:8551

# Ports
HTTP_PORT=5052
P2P_PORT=9000

# Your public IP (important for peer discovery)
BEACON_ENR_ADDRESS=YOUR_PUBLIC_IP

# Add network bootnodes
BOOT_NODES=enr:-Iq4QJk4WqRkjsX5c2CXtOra6HnxN-BMXnWhmhEQO9Bn9iABTJGdjUOurM7Btj1ouKaFkvTRoju5vz2GPmVON2dffQKGAX53x8JigmlkgnY0gmlwhLKAlv6Jc2VjcDI1NmsxoQK6S-Cii_KmfFdUJL2TANL3ksaKUnNXvTCv1tLwXs0QgIN1ZHCCIyk

TARGET_PEERS=64
```

### Step 7: Start the Consensus Layer

```bash
cd ..
./node.sh start cl
```

### Step 8: Verify Everything is Running

```bash
# Check status of all nodes
./node.sh status

# Test EL RPC
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545

# Test CL API
curl http://localhost:5052/eth/v1/node/syncing
```

You should see block numbers increasing. Your Full Node is now running!

---

## Run a Beacon Node (CL Only)

Run only the Consensus Layer if you have access to an external Execution Layer.

### Step 1: Clone the Repository

```bash
git clone https://github.com/YOUR_ORG/labchain.git
cd labchain
```

### Step 2: Create Docker Network

```bash
docker network create labchain-net
```

### Step 3: Get JWT Secret

You must use the **same JWT secret** as the EL you're connecting to.

```bash
mkdir -p config/jwt
# Copy the JWT secret from your EL provider
echo "YOUR_JWT_SECRET_HEX" > config/jwt/jwtsecret
```

### Step 4: Configure CL Environment

```bash
cd CL
cp .env.example .env   # if exists, or create new
```

Edit `CL/.env`:

```bash
# CL/.env
LIGHTHOUSE_IMAGE=sigp/lighthouse:latest
LIGHTHOUSE_LOG_LEVEL=info

# Connect to external EL (replace with actual endpoint)
EXECUTION_ENDPOINT=http://EXTERNAL_EL_IP:8551

# Ports
HTTP_PORT=5052
P2P_PORT=9000

# Your public IP
BEACON_ENR_ADDRESS=YOUR_PUBLIC_IP

# Network bootnodes
BOOT_NODES=enr:-Iq4QJk4WqRkjsX5c2CXtOra6HnxN-BMXnWhmhEQO9Bn9iABTJGdjUOurM7Btj1ouKaFkvTRoju5vz2GPmVON2dffQKGAX53x8JigmlkgnY0gmlwhLKAlv6Jc2VjcDI1NmsxoQK6S-Cii_KmfFdUJL2TANL3ksaKUnNXvTCv1tLwXs0QgIN1ZHCCIyk

TARGET_PEERS=64
```

### Step 5: Start the Beacon Node

```bash
cd ..
./node.sh start cl
```

### Step 6: Verify the Beacon Node is Running

```bash
# Check status
./node.sh status

# Check logs
./node.sh logs cl

# Test beacon API
curl http://localhost:5052/eth/v1/node/health
```

Your Beacon Node is now running!

---

## Run a Validator (VC Only)

Run a Validator Client if you have access to an external Beacon Node and want to participate in consensus.

### Step 1: Clone the Repository

```bash
git clone https://github.com/YOUR_ORG/labchain.git
cd labchain
```

### Step 2: Create Docker Network

```bash
docker network create labchain-net
```

### Step 3: Generate Validator Keystores

Use the provided script to generate validator keys:

```bash
cd VC

# Generate 1 validator with your withdrawal address
./manage-validators.sh \
  --count 1 \
  --withdrawal 0xYOUR_ETH_ADDRESS \
  --output ./output \
  --managed-root ./my-keystores
```

**Script options:**
- `--count <number>` - Number of validators to create (default: 64)
- `--withdrawal <address>` - Your ETH address for withdrawals
- `--output <dir>` - Where to save output files (default: ./output)
- `--managed-root <dir>` - Where to save keystores (default: ./managed-keystores)
- `--first-index <number>` - Starting validator index (default: 0)

This creates:
- `./output/deposits.json` - Deposit data for broadcasting
- `./output/validators.json` - Full validator info
- `./my-keystores/validators/` - Keystore files
- `./my-keystores/secrets/` - Password files

### Step 4: Fund Your Validators (Deposit 32 ETH)

You need 32 ETH per validator. Use the deposit script:

```bash
# First, make sure you have ETH in your wallet
# Then broadcast the deposits

./broadcast-deposits.sh \
  --rpc http://localhost:8545 \
  --deposits ./output/deposits.json \
  --from 0xYOUR_FUNDED_ADDRESS \
  --chain-id 5222 \
  --private-key YOUR_PRIVATE_KEY_HEX \
  --contract 0x5454545454545454545454545454545454545454
```

**Script options:**
- `--rpc <url>` - EL RPC endpoint
- `--deposits <file>` - Path to deposits.json from Step 3
- `--from <address>` - Your funded wallet address
- `--chain-id <id>` - Network chain ID (5222 for LabChain)
- `--private-key <hex>` - Private key of funded wallet (no 0x prefix)
- `--contract <address>` - Deposit contract address
- `--dry-run` - Preview transactions without sending

**Note:** Each deposit costs 32 ETH. Wait for deposits to be processed (about 16 hours).

### Step 5: Configure VC Environment

```bash
cd VC
cp .env.example .env   # if exists, or create new
```

Edit `VC/.env`:

```bash
# VC/.env
LIGHTHOUSE_IMAGE=sigp/lighthouse:latest
LIGHTHOUSE_LOG_LEVEL=info

# Connect to your Beacon Node
BEACON_NODE_ENDPOINTS=http://BEACON_NODE_IP:5052

# Path to your keystores from Step 3
KEYSTORE_DIR=./my-keystores

# Your fee recipient address (for MEV/tips)
FEE_RECIPIENT=0xYOUR_ETH_ADDRESS
```

### Step 6: Start the Validator Client

```bash
cd ..
./node.sh start vc
```

### Step 7: Verify Your Validator is Running

```bash
# Check status
./node.sh status

# Check logs
./node.sh logs vc
```

Look for these messages in the logs:
- `Enabled validator` - Your validator is loaded
- `Successfully published attestation` - Validator is attesting (after activation)
- `Successfully published block` - Validator proposed a block

**Note:** After depositing, validators need to wait in the activation queue (typically 16-24 hours).

---

## Useful Commands

### Node Management

```bash
# Start nodes
./node.sh start el      # Start Execution Layer
./node.sh start cl      # Start Consensus Layer
./node.sh start vc      # Start Validator Client
./node.sh start all     # Start all nodes

# Stop nodes
./node.sh stop el
./node.sh stop cl
./node.sh stop vc
./node.sh stop all

# Restart nodes
./node.sh restart el
./node.sh restart cl
./node.sh restart vc
./node.sh restart all

# View logs
./node.sh logs el
./node.sh logs cl
./node.sh logs vc
./node.sh logs all

# Check status
./node.sh status
```

### Check Sync Status

```bash
# EL sync status
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:8545

# CL sync status
curl http://localhost:5052/eth/v1/node/syncing
```

### Get Current Block/Slot

```bash
# Current EL block
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545

# Current CL slot
curl http://localhost:5052/eth/v1/beacon/headers/head
```

---

## Troubleshooting

### EL won't start

**Check genesis is initialized:**
```bash
ls EL/data/.genesis_applied
```

**Check logs:**
```bash
./node.sh logs el
```

**Verify genesis file exists:**
```bash
ls config/metadata/genesis.json
```

### CL can't connect to EL

**Verify JWT secrets match:**
```bash
# Both should show same content
cat config/jwt/jwtsecret
```

**Check EL is running:**
```bash
./node.sh status
curl http://localhost:8545
```

**Check network:**
```bash
docker network ls | grep labchain
```

### Validator not producing attestations

**Check beacon node is synced:**
```bash
curl http://localhost:5052/eth/v1/node/syncing
# Should return {"data":{"is_syncing":false,...}}
```

**Verify keystores are loaded:**
```bash
./node.sh logs vc | grep "Enabled validator"
```

**Check validator activation status:**
Your validator needs to be activated on-chain. This takes about 16-24 hours after deposit.

### Peer discovery issues

**Check your public IP is correct:**
```bash
curl ifconfig.me
```

**Verify firewall allows P2P ports:**
- EL: 30303 (TCP/UDP)
- CL: 9000 (TCP/UDP)

**Check peer count:**
```bash
# EL peers
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://localhost:8545

# CL peers
curl http://localhost:5052/eth/v1/node/peer_count
```

---

## Support

If you need help:
- Check the [troubleshooting section](#troubleshooting)
- Contact network administrators
- Join our community channels

---

**LabChain** - Made with love by LAOITDEV Team
