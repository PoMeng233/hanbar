#!/usr/bin/env sh
# 生成 Linux / macOS 平台工程并安装依赖（不会覆盖已有源码）
cd "$(dirname "$0")"

echo "[1/3] 生成 Linux / macOS 平台工程..."
flutter create --project-name hanbar --platforms=linux,macos .

echo "[2/3] 安装依赖..."
flutter pub get

echo "[3/3] 完成！运行示例："
echo "  flutter run -d linux"
echo "  flutter build linux --release"
