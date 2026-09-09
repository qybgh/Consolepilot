#!/usr/bin/env bash
# Consolepilot 卸载数据清理
#
# 把 Consolepilot.app 与 consolepilot 移入废纸篓后，运行本脚本即可清除
# 应用在系统里留下的全部用户数据。设计原则：
#   - 只删除 Consolepilot 自己的数据，绝不触碰其他应用或用户文档；
#   - 钥匙串里的 API Key 属于用户秘密，默认保留（见 --purge-keychain）；
#   - “辅助功能”授权归系统 TCC 管理，脚本尝试用 tccutil 重置（尽力而为）。
#
# 用法：
#   ./uninstall.sh            # 逐项询问
#   ./uninstall.sh --yes      # 直接执行全部清理
#   ./uninstall.sh --dry-run  # 只打印将要删除的路径，不真正删除
set -u

BUNDLE_ID="com.consolepilot.Consolepilot"
APP_NAME="Consolepilot"

PURGE_KEYCHAIN=0
YES=0
DRY=0
for arg in "$@"; do
  case "$arg" in
    --purge-keychain) PURGE_KEYCHAIN=1 ;;
    --yes) YES=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "未知参数：$arg" >&2; exit 2 ;;
  esac
done

HOME_DIR="${HOME:?}"
PATHS=(
  "$HOME_DIR/.config/consolepilot"                                  # 配置文件目录
  "$HOME_DIR/Library/Application Support/Consolepilot"              # SQLite 数据库与备用配置
  "$HOME_DIR/Library/Caches/$BUNDLE_ID"                             # 缓存（如存在）
  "$HOME_DIR/Library/Logs/Consolepilot"                             # 日志目录（如存在）
  "$HOME_DIR/Library/Preferences/$BUNDLE_ID.plist"                  # 偏好设置（defaults 域）
)
# 若应用为沙盒形态出现过容器目录，一并清理（当前非沙盒，防御性保留）
CONTAINER="$HOME_DIR/Library/Containers/$BUNDLE_ID"
[ -e "$CONTAINER" ] && PATHS+=("$CONTAINER")

echo "即将清理 Consolepilot 的以下用户数据："
for p in "${PATHS[@]}"; do
  echo "  - $p"
done

if [ "$DRY" = 1 ]; then
  echo "（--dry-run：以上为将删除清单，未执行任何删除）"
  exit 0
fi

if [ "$YES" != 1 ]; then
  read -r -p "确认删除以上数据？[y/N] " answer
  case "$answer" in
    y|Y) ;;
    *) echo "已取消"; exit 1 ;;
  esac
fi

# 1) 退出正在运行的应用
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
sleep 1

# 2) 删除数据目录与偏好
for p in "${PATHS[@]}"; do
  if [ -e "$p" ] || [ -L "$p" ]; then
    rm -rf -- "$p" && echo "已删除：$p"
  fi
done
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 && echo "已重置偏好设置域：$BUNDLE_ID" || true

# 3) 重置系统“辅助功能”授权（TCC；若系统提示无权限授权则忽略）
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 \
  && echo "已重置辅助功能授权（TCC）" || echo "提示：辅助功能授权未能自动重置，可在 系统设置→隐私与安全性→辅助功能 中手动移除"

# 4) 钥匙串：默认保留（可能同时被其他工具引用）
if [ "$PURGE_KEYCHAIN" = 1 ]; then
  echo "提示：钥匙串条目需逐条删除。请确认账户名后手动执行："
  echo "  security delete-generic-password -s com.local.consolepilot -a <账户名>"
else
  echo "提示：API Key 等钥匙串条目属于你的秘密，默认保留；需要彻底删除时请加 --purge-keychain 并手动核对账户名。"
fi

echo "✓ Consolepilot 数据清理完成（App/CLI 本体请手动移入废纸篓）"
