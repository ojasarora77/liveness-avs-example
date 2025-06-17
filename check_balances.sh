#!/bin/bash

source .env

echo "💰 CHECKING MNT BALANCES ON MANTLE SEPOLIA"
echo "=========================================="
echo ""

RPC_URL="https://rpc.sepolia.mantle.xyz"

# Function to check balance and convert from wei to MNT
check_balance() {
    local name="$1"
    local private_key="$2"
    local address=$(cast wallet address $private_key)
    local balance_wei=$(cast balance $address --rpc-url $RPC_URL)
    local balance_mnt=$(cast --to-unit $balance_wei ether)
    
    echo "$name:"
    echo "  Address: $address"
    echo "  Balance: $balance_mnt MNT"
    echo ""
}

check_balance "DEPLOYER" $PRIVATE_KEY_DEPLOYER
check_balance "AGGREGATOR" $PRIVATE_KEY_AGGREGATOR  
check_balance "ATTESTER 1" $PRIVATE_KEY_ATTESTER1
check_balance "ATTESTER 2" $PRIVATE_KEY_ATTESTER2
check_balance "ATTESTER 3" $PRIVATE_KEY_ATTESTER3
check_balance "PERFORMER" $PRIVATE_KEY_PERFORMER

echo "✅ All addresses checked!"
echo ""
echo "💡 Each address needs at least 0.1 MNT for gas fees"
echo "🔗 If any balance is 0, visit: https://faucet.sepolia.mantle.xyz/"