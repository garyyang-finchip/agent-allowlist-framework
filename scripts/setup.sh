#!/usr/bin/env bash
# Fetches the library the tests and the evidence run are built against.
# It is pinned by tag and is not part of this repository.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p lib
[ -d lib/forge-std ] || git clone --depth 1 --branch v1.9.7 https://github.com/foundry-rs/forge-std lib/forge-std
echo "libraries ready"
