#!/bin/bash

# Startup script to initialize and boot a go-ethereum instance.
#
# This script assumes the following files:
#  - `geth` binary is located in the filesystem root
#  - `genesis.json` file is located in the filesystem root (mandatory)
#  - `chain.rlp` file is located in the filesystem root (optional)
#  - `blocks` folder is located in the filesystem root (optional)
#  - `keys` folder is located in the filesystem root (optional)
#
# This script assumes the following environment variables:
#
#  - HIVE_BOOTNODE                enode URL of the remote bootstrap node
#  - HIVE_NETWORK_ID              network ID number to use for the eth protocol
#  - HIVE_TESTNET                 whether testnet nonces (2^20) are needed
#  - HIVE_NODETYPE                sync and pruning selector (archive, full, light)
#
# Forks:
#
#  - HIVE_FORK_HOMESTEAD          block number of the homestead hard-fork transition
#  - HIVE_FORK_DAO_BLOCK          block number of the DAO hard-fork transition
#  - HIVE_FORK_DAO_VOTE           whether the node support (or opposes) the DAO fork
#  - HIVE_FORK_TANGERINE          block number of Tangerine Whistle transition
#  - HIVE_FORK_SPURIOUS           block number of Spurious Dragon transition
#  - HIVE_FORK_BYZANTIUM          block number for Byzantium transition
#  - HIVE_FORK_CONSTANTINOPLE     block number for Constantinople transition
#  - HIVE_FORK_PETERSBURG         block number for ConstantinopleFix/PetersBurg transition
#  - HIVE_FORK_ISTANBUL           block number for Istanbul transition
#  - HIVE_FORK_MUIRGLACIER        block number for Muir Glacier transition
#  - HIVE_FORK_BERLIN             block number for Berlin transition
#  - HIVE_FORK_LONDON             block number for London
#
# Clique PoA:
#
#  - HIVE_CLIQUE_PERIOD           enables clique support. value is block time in seconds.
#  - HIVE_CLIQUE_PRIVATEKEY       private key for clique mining
#
# Other:
#
#  - HIVE_MINER                   enable mining. value is coinbase address.
#  - HIVE_MINER_EXTRA             extra-data field to set for newly minted blocks
#  - HIVE_SKIP_POW                if set, skip PoW verification during block import
#  - HIVE_LOGLEVEL                client loglevel (0-5)
#  - HIVE_GRAPHQL_ENABLED         enables graphql on port 8545
#  - HIVE_LES_SERVER              set to '1' to enable LES server

# Taiko environment variables
#
#  - HIVE_TAIKO_L1_RPC_ENDPOINT                      rpc endpoint of the l1 node
#  - HIVE_TAIKO_L2_RPC_ENDPOINT                      rpc endpoint of the l2 node
#  - HIVE_TAIKO_L2_ENGINE_ENDPOINT                   engine endpoint of the l2 node
#  - HIVE_TAIKO_L1_ROLLUP_ADDRESS                    rollup address of the l1 node
#  - HIVE_TAIKO_L2_ROLLUP_ADDRESS                    rollup address of the l2 node
#  - HIVE_TAIKO_PROPOSER_PRIVATE_KEY                 private key of the proposer
#  - HIVE_TAIKO_SUGGESTED_FEE_RECIPIENT              suggested fee recipient
#  - HIVE_TAIKO_PROPOSE_INTERVAL                     propose interval
#  - HIVE_TAIKO_THROWAWAY_BLOCK_BUILDER_PRIVATE_KEY  private key of the throwaway block builder
#  - HIVE_TAIKO_L1_CHAIN_ID                          l1 chain id
#  - HIVE_TAIKO_PROVER_PRIVATE_KEY                   private key of the prover
#  - HIVE_TAIKO_JWT_SECRET                           jwt secret used by driver and taiko

# Immediately abort the script on any error encountered
set -e

geth=/usr/local/bin/geth
FLAGS="--pcscdpath=\"\""

if [ "$HIVE_LOGLEVEL" != "" ]; then
    FLAGS="$FLAGS --verbosity=$HIVE_LOGLEVEL"
fi

# It doesn't make sense to dial out, use only a pre-set bootnode.
FLAGS="$FLAGS --bootnodes=$HIVE_BOOTNODE"

if [ "$HIVE_SKIP_POW" != "" ]; then
    FLAGS="$FLAGS --fakepow"
fi

# If a specific network ID is requested, use that
if [ "$HIVE_NETWORK_ID" != "" ]; then
    FLAGS="$FLAGS --networkid $HIVE_NETWORK_ID"
else
    # Unless otherwise specified by hive, we try to avoid mainnet networkid. If geth detects mainnet network id,
    # then it tries to bump memory quite a lot
    FLAGS="$FLAGS --networkid 1337"
fi

# If the client is to be run in testnet mode, flag it as such
if [ "$HIVE_TESTNET" == "1" ]; then
    FLAGS="$FLAGS --testnet"
fi

# Handle any client mode or operation requests
if [ "$HIVE_NODETYPE" == "archive" ]; then
    FLAGS="$FLAGS --syncmode full --gcmode archive"
fi
if [ "$HIVE_NODETYPE" == "full" ]; then
    FLAGS="$FLAGS --syncmode full"
fi
if [ "$HIVE_NODETYPE" == "light" ]; then
    FLAGS="$FLAGS --syncmode light"
fi
if [ "$HIVE_NODETYPE" == "snap" ]; then
    FLAGS="$FLAGS --syncmode snap"
fi
if [ -z "$HIVE_NODETYPE" ]; then
    FLAGS="$FLAGS --syncmode snap"
fi

# Import clique signing key.
if [ -n "$HIVE_CLIQUE_PRIVATEKEY" ]; then
    # Create password file.
    echo "Importing clique key..."
    echo "secret" >/geth-password-file.txt
    $geth --nousb account import --password /geth-password-file.txt <(echo "$HIVE_CLIQUE_PRIVATEKEY")

    # Ensure password file is used when running geth in mining mode.
    if [ -n "$HIVE_MINER" ]; then
        FLAGS="$FLAGS --password /geth-password-file.txt --unlock $HIVE_MINER --allow-insecure-unlock"
    fi
fi

# Configure any mining operation
if [ -n "$HIVE_MINER" ] && [ "$HIVE_NODETYPE" != "light" ]; then
    FLAGS="$FLAGS --mine --miner.threads 1 --miner.etherbase $HIVE_MINER"
fi
if [ -n "$HIVE_MINER_EXTRA" ]; then
    FLAGS="$FLAGS --miner.extradata $HIVE_MINER_EXTRA"
fi
FLAGS="$FLAGS --miner.gasprice 16000000000"

# Configure LES.
if [ "$HIVE_LES_SERVER" == "1" ]; then
    FLAGS="$FLAGS --light.serve 50 --light.nosyncserve"
fi

# Configure RPC.
FLAGS="$FLAGS --http --http.addr=0.0.0.0 --http.port=8545 --http.vhosts=* --http.api=admin,debug,eth,miner,net,personal,txpool,web3,taiko"
FLAGS="$FLAGS --ws --ws.addr=0.0.0.0 --ws.origins=* --ws.api=admin,debug,eth,miner,net,personal,txpool,web3,taiko"

# if [ "$HIVE_TERMINAL_TOTAL_DIFFICULTY" != "" ]; then
echo "$HIVE_TAIKO_JWT_SECRET" >/jwtsecret
FLAGS="$FLAGS --authrpc.addr=0.0.0.0 --authrpc.port=8551 --authrpc.vhosts=* --authrpc.jwtsecret=/jwtsecret"
# fi

# Configure GraphQL.
if [ -n "$HIVE_GRAPHQL_ENABLED" ]; then
    FLAGS="$FLAGS --graphql"
fi
# used for the graphql to allow submission of unprotected tx
if [ -n "$HIVE_ALLOW_UNPROTECTED_TX" ]; then
    FLAGS="$FLAGS --rpc.allow-unprotected-txs"
fi

# Run the go-ethereum implementation with the requested flags.
FLAGS="$FLAGS --nat=none"

# taiko part start:
FLAGS="$FLAGS --taiko --allow-insecure-unlock"
# taiko part end

echo "Running taiko-geth with flags $FLAGS"
$geth $FLAGS
