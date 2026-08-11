import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/progress_card.dart';

/// 初始窗口尺寸
const Size kWindowSize = Size(380, 156);

/// 窗口最小尺寸（与 progress_card.dart 中 kWindowMinSize 保持一致）
const Size kWindowMinSize = Size(150, 138);

Future<void> main() async {
  // 1. 初始化 Widgets 绑定（runApp 之前使用异步 API 的必要步骤）
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 初始化 window_manager（无边框 / 置顶 / 透明 桌面悬浮窗）
  await windowManager.ensureInitialized();

  // 3. 窗口参数说明（window_manager 0.5.x）：
  //    - backgroundColor 透明：实现透明背景（圆角卡片悬浮效果）
  //    - alwaysOnTop：       始终置顶，悬浮于游戏 / 编辑器之上
  //    - skipTaskbar：       不占用任务栏（按需可改为 false）
  //    - titleBarStyle.hidden：隐藏标题栏（macOS 必需）
  //    - windowButtonVisibility：macOS 隐藏红绿灯按钮
  //    - minimumSize：       限制最小尺寸（不限制宽高比，可自由缩放）
  const windowOptions = WindowOptions(
    size: kWindowSize,
    minimumSize: kWindowMinSize,
    center: true,
    title: '汉化进度悬浮窗',
    backgroundColor: Colors.transparent,
    alwaysOnTop: true,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  // 4. 等待窗口创建就绪后：设置为无边框、可缩放并显示
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    // 无边框（Windows 必需；macOS 同时隐藏标题栏）
    await windowManager.setAsFrameless();
    // 允许自由调整大小（无边框窗口的缩放手柄在 progress_card 中自绘）
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(kWindowMinSize);
    // 无边框悬浮窗不适合最大化 / 最小化
    await windowManager.setMaximizable(false);
    await windowManager.setMinimizable(false);
    await windowManager.show();
    await windowManager.focus();
    // 重复设置一次置顶，确保部分平台（Windows）创建后依然保持置顶
    await windowManager.setAlwaysOnTop(true);
  });

  runApp(const HanClockApp());
}

/// 应用根组件（现代极简 Dark Mode）
class HanClockApp extends StatelessWidget {
  const HanClockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '汉化进度悬浮窗',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const ProgressCard(),
    );
  }
}
