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
}
