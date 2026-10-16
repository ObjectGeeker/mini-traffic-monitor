#!/bin/bash
# 安装到 /Applications 并启动（菜单栏 App 的常规位置，SMAppService 也更稳定）
set -euo pipefail
cd "$(dirname "$0")/.."

APP=MiniTrafficMonitor.app

pkill -f "$APP/Contents/MacOS" 2>/dev/null || true
sleep 0.5

rm -rf "/Applications/$APP"
cp -R "$APP" "/Applications/$APP"
codesign --force --sign - "/Applications/$APP"

open "/Applications/$APP"
echo "已安装并启动: /Applications/$APP"
