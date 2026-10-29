#!/bin/bash
# 一键构建并运行 Kimo（开发用）
set -e
cd "$(dirname "$0")/.."

if [ ! -d CoreRuntime/node_modules ]; then
  echo "→ 安装核心依赖（MoeKoeMusic 的 kugoumusicapi）"
  (cd CoreRuntime && npm install --no-audit --no-fund)
fi

echo "→ 生成 Xcode 工程"
xcodegen generate >/dev/null

echo "→ 编译"
xcodebuild -project Kimo.xcodeproj -scheme Kimo -configuration Debug \
  -derivedDataPath .build build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" || true

echo "→ 启动"
exec .build/Build/Products/Debug/Kimo.app/Contents/MacOS/Kimo
