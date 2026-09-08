#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Spike S1–S9 需要 Xcode 16+、完整 Swift 6 toolchain 和实机权限。"
echo "当前仅提供目录与 S4 mock server；请安装 Xcode 后按各 Spike README 执行。"
