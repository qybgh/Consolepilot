#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f dist/consolepilot ] || { echo "先运行 build-local.sh"; exit 1; }
sudo mkdir -p /usr/local/bin
sudo install -m 0755 dist/consolepilot /usr/local/bin/consolepilot
mkdir -p "$HOME/.config/consolepilot"
[ -f "$HOME/.config/consolepilot/config.toml" ] || cp dist/config.example.toml "$HOME/.config/consolepilot/config.toml"
