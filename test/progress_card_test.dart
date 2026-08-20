import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hanbar/ui/progress_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归测试：设置菜单在窗口较小时必须能正常打开（不得崩溃）。
/// 曾因菜单高度超过窗口高度导致 clamp 上下界倒置抛 ArgumentError。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('默认窗口尺寸下打开设置菜单不崩溃', (tester) async {
    await tester.binding.setSurfaceSize(const Size(380, 200));
    await tester.pumpWidget(const MaterialApp(home: ProgressCard()));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('配色方案'), findsOneWidget);
    expect(find.text('进度条样式'), findsOneWidget);
  });

  testWidgets('最小竖向窗口（280×180）打开设置菜单不崩溃', (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 180));
    await tester.pumpWidget(const MaterialApp(home: ProgressCard()));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('配色方案'), findsOneWidget);
  });

  testWidgets('150px 窄竖排能够正常布局并打开设置菜单', (tester) async {
    await tester.binding.setSurfaceSize(const Size(150, 260));
    await tester.pumpWidget(const MaterialApp(home: ProgressCard()));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('配色方案'), findsOneWidget);
  });

  testWidgets('切换到各进度条样式与主题不崩溃', (tester) async {
    await tester.binding.setSurfaceSize(const Size(380, 200));
    await tester.pumpWidget(const MaterialApp(home: ProgressCard()));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();

    // 逐个点击样式标签
    for (final label in ['经典', '滴水', '马赛克', '条纹', '发光', '波纹']) {
      await tester.tap(find.text(label).first, warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('横竖布局边界快速来回切换不崩溃（迟滞死区回归）', (tester) async {
    // 在 高≈宽 边界附近反复抖动尺寸：布局模式不得逐帧抖动重建，
    // 也不得出现布局断言 / 溢出异常。
    const sizes = [
      Size(380, 200), // 横向
      Size(200, 210), // 跨过边界 → 竖向
      Size(202, 208), // 死区内抖动 → 应保持竖向
      Size(210, 200), // 明显越过死区 → 回到横向
      Size(150, 300), // 窄窗强制竖向
      Size(300, 150), // 宽窗横向
    ];
    for (final s in sizes) {
      await tester.binding.setSurfaceSize(s);
      await tester.pumpWidget(const MaterialApp(home: ProgressCard()));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '尺寸 $s 下出现布局异常');
    }
  });

  testWidgets('极端小尺寸（缩放中间帧模拟）不崩溃', (tester) async {
    // 无边框窗口快速缩放的中间帧可能短暂小于最小尺寸：
    // 负 / 零尺寸不得传给布局导致断言。
    const sizes = [
      Size(1, 1),
      Size(10, 60),
      Size(60, 10),
      Size(150, 138), // 回到最小尺寸恢复正常
    ];
    for (final s in sizes) {
      await tester.binding.setSurfaceSize(s);
      await tester.pumpWidget(const MaterialApp(home: ProgressCard()));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '尺寸 $s 下出现布局异常');
    }
    // 恢复正常尺寸后 UI 仍然可用（菜单能打开）
    await tester.binding.setSurfaceSize(const Size(380, 200));
    await tester.pumpWidget(const MaterialApp(home: ProgressCard()));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('配色方案'), findsOneWidget);
  });
}
