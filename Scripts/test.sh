#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift package clean
swift test -j 1
echo "TEST PASS"
