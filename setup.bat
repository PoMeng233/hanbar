@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo [1/3] 生成 Windows / macOS / Linux 平台工程（不会覆盖已有源码）...
flutter create --project-name hanbar --platforms=windows,macos,linux .

echo [2/3] 安装依赖...
flutter pub get

echo [3/3] 完成！运行示例：
echo   flutter run -d windows
echo   flutter build windows --release
pause
