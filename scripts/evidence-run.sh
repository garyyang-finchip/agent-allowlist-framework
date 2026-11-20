#!/usr/bin/env bash
# Runs the three worked cases of the specification on a network and records the result.
#
#   bash scripts/evidence-run.sh <anvil|sepolia>
#
#   DEPLOYER_PK   key of the funded deployer; every other account of the run is derived from it
#   RPC_URL       JSON-RPC endpoint of the network (SEPOLIA_RPC_URL is accepted as well)
#   TIP_WEI       priority fee per gas, default 200000000 (0.2 gwei)
#
# deployments/<network>/plan.json must exist. It is written by `node tools/awf.mjs plan <network>`
# and fixes the accounts, the documents and the committed set of the run. The run writes
# state.json and evidence.json next to it. Gas limits come from the node, never from a local
# simulation. Nothing is sent unless the deployer balance covers the whole run. If a run stops
# half way, run the same command again: it starts over with fresh contracts.
set -euo pipefail

NETWORK="${1:-anvil}"
RPC_URL="${RPC_URL:-${SEPOLIA_RPC_URL:-}}"
: "${DEPLOYER_PK:?set DEPLOYER_PK}"
: "${RPC_URL:?set RPC_URL}"
export NETWORK RPC_URL
cd "$(dirname "$0")/.."

PLAN="deployments/$NETWORK/plan.json"
[ -f "$PLAN" ] || { echo "missing $PLAN"; exit 1; }
[ -d lib/forge-std ] || bash scripts/setup.sh

DEPLOYER="$(cast wallet address --private-key "$DEPLOYER_PK")"
BASE="$(cast base-fee --rpc-url "$RPC_URL")"
TIP="${TIP_WEI:-200000000}"
if [ "${#BASE}" -gt 10 ]; then
  echo "the base fee of $BASE wei is far above normal for a test network; try again later"
  exit 1
fi
# Every transaction of the run is sent with this fee cap: twice the base fee plus the tip.
MAXFEE=$(( BASE * 2 + TIP ))
export GAS_PRICE_WEI="$MAXFEE"

# Gas each account of the run is funded for. The figures are sized for networks that price
# state creation at 1,530 gas per byte (EIP-8037); see docs/sepolia-runbook.md for how they
# were derived. Networks without that pricing use about a fifth of them.
export GAS_MANAGER=12000000 GAS_ISSUER=2500000 GAS_ALICE=8000000 GAS_BOB=8000000
export GAS_CAROL=3000000 GAS_OPERATOR=6000000 GAS_MALLORY=2000000
ACTOR_GAS=$(( GAS_MANAGER + GAS_ISSUER + GAS_ALICE + GAS_BOB + GAS_CAROL + GAS_OPERATOR + GAS_MALLORY ))
OWN_GAS=125000000
NEED=$(( (ACTOR_GAS + OWN_GAS) * MAXFEE ))
HAVE="$(cast balance "$DEPLOYER" --rpc-url "$RPC_URL")"
echo "network   $NETWORK"
echo "deployer  $DEPLOYER"
echo "base fee  $BASE wei, tip $TIP wei, fee cap $MAXFEE wei per gas"
echo "balance   $HAVE wei"
echo "budget    $NEED wei"
if [ "${#HAVE}" -lt "${#NEED}" ] || { [ "${#HAVE}" -eq "${#NEED}" ] && [ "$HAVE" \< "$NEED" ]; }; then
  echo "the deployer balance is below the budget of this run; nothing was sent"
  echo "fund $DEPLOYER up to the budget and run again"
  exit 1
fi

# The test files are left out of the build: the run does not need them, and building them takes
# more memory than a small server has.
phase() {
  echo "== $1"
  forge script script/AWFEvidence.s.sol --sig "$1()" --rpc-url "$RPC_URL" --skip test --broadcast --slow \
    --skip-simulation --with-gas-price "$MAXFEE" --priority-gas-price "$TIP" --timeout 600
}

phase deploy
phase caseA1
phase caseB1
phase caseA2

# Two things have to pass: the notice period of the entry made in Case B (120 seconds) and the
# lifetime of the credential issued in Case A (240 seconds).
WAIT="$(sed -n 's/.*"wait": *\([0-9]*\).*/\1/p' "$PLAN")"
if [ "$NETWORK" = "anvil" ]; then
  cast rpc evm_increaseTime "$WAIT" --rpc-url "$RPC_URL" > /dev/null
  cast rpc evm_mine --rpc-url "$RPC_URL" > /dev/null
else
  echo "waiting $WAIT seconds for the notice period and the credential lifetime"
  sleep "$WAIT"
fi

phase caseA3
phase caseB2
phase caseC

echo "== report"
forge script script/AWFEvidence.s.sol --sig "report()" --rpc-url "$RPC_URL" --skip test
LEFT="$(cast balance "$DEPLOYER" --rpc-url "$RPC_URL")"
echo "deployer balance after the run: $LEFT wei"
echo "===== BEGIN deployments/$NETWORK/evidence.json ====="
cat "deployments/$NETWORK/evidence.json"
echo
echo "===== END deployments/$NETWORK/evidence.json ====="
