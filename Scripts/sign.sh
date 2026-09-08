#!/usr/bin/env bash
set -euo pipefail
APP="${1:?usage: sign.sh path/to/App.app}"
IDENTITY="${CONSOLEPILOT_SIGN_IDENTITY:--}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT_DIR/Resources/Consolepilot.entitlements"
if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "缺少 entitlements：$ENTITLEMENTS" >&2
  exit 1
fi
codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" -s "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "com.apple.security.app-sandbox" && {
  echo "错误：Consolepilot 不应启用 App Sandbox" >&2
  exit 1
} || true
echo "signed with: $IDENTITY"
