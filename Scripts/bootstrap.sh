#!/usr/bin/env bash
set -euo pipefail

command -v xcodebuild >/dev/null || { echo "需要安装完整 Xcode（当前不能仅使用 Command Line Tools）"; exit 1; }
if ! xcode-select -p | grep -q '/Xcode.app/Contents/Developer'; then
  echo "请执行：sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

SWIFT_VERSION="$(xcrun swift --version 2>/dev/null | awk '/Apple Swift version/ { print $4; exit }')"
SWIFT_MAJOR="${SWIFT_VERSION%%.*}"
if [ -z "$SWIFT_MAJOR" ] || [ "$SWIFT_MAJOR" -lt 6 ]; then
  echo "Swift 6+ is required; detected: ${SWIFT_VERSION:-unknown}. Please use Xcode 16 or newer."
  exit 1
fi

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "Missing required tool: swiftlint"
  exit 1
fi
if ! command -v periphery >/dev/null 2>&1; then
  echo "Warning: periphery is unavailable; install it before final D4 gate (the formula is archived)."
fi

if ! command -v swift-format >/dev/null && ! xcrun --find swift-format >/dev/null 2>&1; then
  echo "Missing required tool: swift-format"
  exit 1
fi

mkdir -p "$HOME/.config/consolepilot"
echo "bootstrap 完成"
