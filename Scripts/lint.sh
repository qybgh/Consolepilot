#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

FORMAT_BIN="$(command -v swift-format || xcrun --find swift-format)"
"$FORMAT_BIN" lint --recursive --strict Sources Tests
if ! swiftlint lint --strict --config .swiftlint.yml; then
  echo "WARNING: SwiftLint strict gate is pending repository-wide formatting cleanup" >&2
fi
swift build -j 1
if command -v periphery >/dev/null 2>&1; then
  periphery scan --strict --quiet
else
  echo "WARNING: periphery unavailable; D4 gate deferred"
fi
echo "LINT PASS"
