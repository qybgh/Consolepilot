#!/bin/bash
# P1-D：Provider 统一 stream contract fixture 验证（可重复执行）。
# 用法：Scripts/verify-provider-contract.sh
# 作用：重新生成 xcodeproj（漂移防护）→ 仅运行 ProviderContractTests。
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
xcodebuild -project Consolepilot.xcodeproj -scheme Consolepilot \
    -destination 'platform=macOS' \
    test CODE_SIGNING_ALLOWED=NO \
    -only-testing:ConsolepilotTests/ProviderContractTests
echo "✓ provider contract fixtures 全部通过"
