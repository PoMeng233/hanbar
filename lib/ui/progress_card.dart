import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watcher/watcher.dart';
import 'package:window_manager/window_manager.dart';

import '../scanner/progress_scanner.dart';
import 'progress_bar.dart';
import 'theme_defs.dart';

/// 窗口最小尺寸（与 main.dart 保持一致）
const Size kWindowMinSize = Size(150, 138);

/// 窗口宽度低于此值时强制竖向布局（横向双进度条放不下）
const double kNarrowWindowWidth = 230;

/// 横竖布局切换的迟滞死区（像素）：高≈宽附近拖拽缩放时，
/// 避免两个模式逐帧抖动导致整棵子树反复重建
const double kPortraitDeadZone = 8;

/// 清洗尺寸分量：无边框窗口快速缩放的中间帧里，平台侧可能短暂传来
/// 负值 / NaN / 无穷，负尺寸进入布局（SizedBox / Positioned / 紧约束）
/// 会触发断言或产生 NaN 传播到 Skia 导致闪退，统一钳为非负有限值。
double _sanitizeExtent(double v) => (v.isFinite && v > 0) ? v : 0.0;

/// 偏好设置 key
const String _kPrefTarget = 'han_clock.target';
const String _kPrefSingleFile = 'han_clock.single_file';
const String _kPrefLastDir = 'han_clock.last_dir';
const String _kPrefTheme = 'han_clock.theme';
const String _kPrefBarStyle = 'han_clock.bar_style';
const String _kPrefAnimations = 'han_clock.animations';
const String _kPrefBackgroundOpacity = 'han_clock.background_opacity';

/// 可拖拽的窗口边缘
enum _ResizeEdge { left, right, top, bottom, tl, tr, bl, br }

/// 悬浮卡片：显示汉化进度 + 右键菜单 + 拖拽移动 + 边缘缩放 + 样式设置
class ProgressCard extends StatefulWidget {
  const ProgressCard({super.key});

  @override
  State<ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends State<ProgressCard> {
  // ---------- 扫描状态 ----------
  String? _targetPath; // 当前目标（目录或单个文件路径）
  bool _isSingleFile = false; // 是否单文件模式
  ScanResult? _result; // 最近一次扫描结果
  String? _error; // 扫描错误信息
  bool _scanning = false; // 是否正在后台扫描
  bool _dirty = false; // 扫描期间又收到文件变化，稍后需重扫

  // ---------- 外观设置 ----------
  int _themeIndex = 0;
  BarStyle _barStyle = BarStyle.classic;
  bool _animations = true;
  double _backgroundOpacity = 0.90;
  bool _opacityHover = false;

  // ---------- 休息提醒 ----------
  Timer? _reminderTimer;
  Timer? _reminderHideTimer;
  bool _reminderVisible = false;
  int _reminderIndex = 0;
  static const List<String> _reminderMessages = [
    '保存一下进度吧，窗外的风也在等你。',
    '补充一点水分，回来再推进剧情吧。',
    '眼睛也需要读档，休息一分钟再继续。',
    '辛苦啦，伸个懒腰再和文字重逢吧。',
    '暂停一下，下一幕会等你的。',
  ];

  // ---------- 文件监听 ----------
  DirectoryWatcher? _watcher;
  StreamSubscription<WatchEvent>? _watcherSub;
  Timer? _debounce; // 事件防抖定时器

  // ---------- 右键菜单 ----------
  bool _menuOpen = false;
  Offset _menuAnchor = Offset.zero;
  final GlobalKey _gearKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _restoreTarget();
    _reminderTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _showReminder(),
    );
  }

  @override
  void dispose() {
    _watcherSub?.cancel();
    _debounce?.cancel();
    _reminderTimer?.cancel();
    _reminderHideTimer?.cancel();
    super.dispose();
  }

  void _showReminder() {
    if (!mounted) return;
    _reminderHideTimer?.cancel();
    setState(() {
      _reminderIndex = (_reminderIndex + 1) % _reminderMessages.length;
      _reminderVisible = true;
    });
    _reminderHideTimer = Timer(
      const Duration(minutes: 1),
      _hideReminder,
    );
  }

  void _hideReminder() {
    if (!mounted || !_reminderVisible) return;
    _reminderHideTimer?.cancel();
    setState(() => _reminderVisible = false);
  }

  // ================================================================
  // 设置持久化
  // ================================================================
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _themeIndex =
          (prefs.getInt(_kPrefTheme) ?? 0).clamp(0, kThemes.length - 1);
      _barStyle =
          BarStyle.values.elementAtOrNull(prefs.getInt(_kPrefBarStyle) ?? 0) ??
              BarStyle.classic;
      _animations = prefs.getBool(_kPrefAnimations) ?? true;
      _backgroundOpacity =
          (prefs.getDouble(_kPrefBackgroundOpacity) ?? 0.90).clamp(0.55, 1.0);
    });
  }

  void _setTheme(int index) {
    setState(() => _themeIndex = index);
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_kPrefTheme, index));
  }

  void _setBarStyle(BarStyle style) {
    setState(() => _barStyle = style);
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_kPrefBarStyle, style.index));
  }

  void _setAnimations(bool on) {
    setState(() => _animations = on);
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_kPrefAnimations, on));
  }

  void _setBackgroundOpacity(double value) {
    setState(() => _backgroundOpacity = value);
    SharedPreferences.getInstance().then(
      (p) => p.setDouble(_kPrefBackgroundOpacity, value),
    );
  }

  // ================================================================
  // 初始化：恢复上次选择的目标并开始监听
  // ================================================================
  Future<void> _restoreTarget() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kPrefTarget);
    if (saved == null || saved.isEmpty || !mounted) return;
    setState(() {
      _targetPath = saved;
      _isSingleFile = prefs.getBool(_kPrefSingleFile) ?? false;
    });
    _startWatcher();
    await _refresh();
  }

  // ================================================================
  // 目标选择（文件夹 / 单个文件）
  // ================================================================
  Future<void> _chooseFolder() async {
    final prefs = await SharedPreferences.getInstance();
    // lockParentWindow：让系统对话框保持在悬浮窗之上（Windows 模态）
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: '选择汉化脚本根目录',
      initialDirectory: prefs.getString(_kPrefLastDir),
      lockParentWindow: true,
    );
    if (dir == null || dir.isEmpty) return;
    await _applyTarget(dir, isSingleFile: false);
  }

  Future<void> _chooseFile() async {
    final prefs = await SharedPreferences.getInstance();
    final res = await FilePicker.pickFiles(
      dialogTitle: '选择汉化脚本文件',
      type: FileType.any,
      initialDirectory: prefs.getString(_kPrefLastDir),
      lockParentWindow: true,
    );
    final file = res?.files.single.path;
    if (file == null || file.isEmpty) return;
    await _applyTarget(file, isSingleFile: true);
  }

  Future<void> _applyTarget(String path, {required bool isSingleFile}) async {
    setState(() {
      _targetPath = path;
      _isSingleFile = isSingleFile;
      _result = null;
      _error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefTarget, path);
    await prefs.setBool(_kPrefSingleFile, isSingleFile);
    await prefs.setString(_kPrefLastDir, isSingleFile ? p.dirname(path) : path);
    _startWatcher();
    await _refresh();
  }

  // ================================================================
  // 轻量文件监听（watcher 包）：目录 / 文件变化 → 防抖 → 后台重扫
  // ================================================================
  void _startWatcher() {
    _watcherSub?.cancel();
    _watcher = null;

    final target = _targetPath;
    if (target == null) return;

    // 单文件模式监听其父目录；目录模式监听整个目录
    final watchDir = _isSingleFile ? p.dirname(target) : target;
    try {
      // runInIsolateOnWindows:false —— 避免 watcher 常驻后台 Isolate
      // 占用额外内存。扫描本身已跑在独立 Isolate 中，主 Isolate 空闲，
      // 不会出现文档所述的事件缓冲耗尽问题。
      _watcher = DirectoryWatcher(watchDir, runInIsolateOnWindows: false);
      _watcherSub = _watcher!.events.listen(
        _onWatchEvent,
        onError: (Object e) {
          // 监听出错（如目录被删除）：忽略，手动刷新可恢复
        },
      );
    } catch (_) {
      // 目录不存在等异常：忽略，由 _refresh 报错提示
    }
  }

  void _onWatchEvent(WatchEvent event) {
    // 单文件模式：只关心目标文件本身的变化
    if (_isSingleFile) {
      if (!_samePath(event.path, _targetPath!)) return;
    } else if (!isScriptFile(event.path)) {
      // 目录模式：只关心脚本文件（忽略临时文件 / 备份文件等噪音）
      return;
    }
    // 防抖：编辑器一次保存往往触发多个事件，合并为一次重扫
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _refresh);
  }

  bool _samePath(String a, String b) => p.equals(a, b);

  // ================================================================
  // 后台扫描（Isolate 计算，不阻塞 UI）
  // ================================================================
  Future<void> _refresh() async {
    final target = _targetPath;
    if (target == null) return;
    if (_scanning) {
      _dirty = true; // 扫描进行中收到新变化：标记稍后重扫
      return;
    }
    setState(() => _scanning = true);
    try {
      final result = await scanProgress(
        targetPath: target,
        isSingleFile: _isSingleFile,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _error = null;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '扫描失败：$e';
        _scanning = false;
      });
    } finally {
      if (_dirty) {
        _dirty = false;
        _refresh();
      }
    }
  }

  // ================================================================
  // 退出应用（先清理监听与定时器，再立即结束进程，保证关闭不卡顿）
  // ================================================================
  Future<void> _exitApp() async {
    _watcherSub?.cancel();
    _watcherSub = null;
    _debounce?.cancel();
    _debounce = null;
    setState(() => _menuOpen = false);
    // 触发窗口销毁后直接结束进程。
    // 不 await destroy()：Windows 上若帧管线/目录监听尚未释放，
    // destroy 可能挂起导致退出卡顿，exit(0) 可确保立即退出。
    windowManager.destroy();
    exit(0);
  }

  // ================================================================
  // 右键菜单
  // ================================================================
  void _openMenuAt(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    setState(() {
      _menuAnchor = box.globalToLocal(globalPosition);
      _menuOpen = true;
    });
  }

  void _openMenuAtGear() {
    final ctx = _gearKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    // 以齿轮按钮右侧中部为菜单锚点
    _openMenuAt(box.localToGlobal(Offset(box.size.width, box.size.height / 2)));
  }

  void _closeMenu() => setState(() => _menuOpen = false);

  /// 关闭菜单后执行动作
  void _runMenuAction(VoidCallback action) {
    _closeMenu();
    action();
  }

  // ================================================================
  // UI
  // ================================================================
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(
            _sanitizeExtent(constraints.maxWidth),
            _sanitizeExtent(constraints.maxHeight),
          );
          // 任意位置按住左键拖动窗口；右键打开菜单
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: (d) => _openMenuAt(d.globalPosition),
            onPanStart: (_) => windowManager.startDragging(),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                children: [
                  _buildCard(size),
                  _buildResizeHandles(size),
                  _buildRestReminder(size),
                  if (_menuOpen) ...[
                    // 菜单遮罩：点击菜单外任意位置关闭
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _closeMenu,
                      ),
                    ),
                    _buildMenu(size),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------------
  // 卡片主体
  // ----------------------------------------------------------------
  Widget _buildCard(Size size) {
    final theme = kThemes[_themeIndex];
    final percent = _result?.percent ?? 0.0;
    // RepaintBoundary：把卡片（含昂贵的大模糊阴影）隔离成独立图层，
    // 休息提醒 / 扫描转圈等兄弟动画不再触发卡片整体重绘
    return RepaintBoundary(
      child: Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(
          alpha: theme.cardColor.a * _backgroundOpacity,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.cardBorder, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        size.width < 220 ? 8 : 16,
        10,
        size.width < 220 ? 8 : 16,
        10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTitleRow(theme, size.width),
          const SizedBox(height: 10),
          // 进度区域整体用 TweenAnimationBuilder 驱动平滑数值动画
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: percent),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) =>
                  _buildProgressArea(value, theme, size),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTitleRow(AppTheme theme, double availableWidth) {
    final narrow = availableWidth < 190;
    if (narrow) {
      return MouseRegion(
        onEnter: (_) => setState(() => _opacityHover = true),
        onExit: (_) => setState(() => _opacityHover = false),
        child: SizedBox(
          height: 28,
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: theme.mainGradient),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _opacityHover
                      ? ClipRect(
                          key: const ValueKey('opacity-slider'),
                          child: _buildOpacitySlider(theme),
                        )
                      : const SizedBox(
                          key: ValueKey('opacity-hidden'),
                        ),
                ),
              ),
              IconButton(
                key: _gearKey,
                onPressed: _openMenuAtGear,
                tooltip: '菜单',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                icon: Icon(
                  Icons.settings_outlined,
                  size: 15,
                  color: theme.dimTextColor,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _opacityHover = true),
      onExit: (_) => setState(() => _opacityHover = false),
      child: Row(
        children: [
        // 顶部小圆点 Logo
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: theme.mainGradient),
          ),
        ),
        SizedBox(width: availableWidth < 190 ? 3 : 8),
        if (availableWidth >= 190)
          Text(
            '汉化进度',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.titleColor,
            ),
          ),
        const SizedBox(width: 8),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: SizedBox(
              width: _opacityHover
                  ? (availableWidth < 260 ? 58 : 112)
                  : 12,
              height: 28,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _opacityHover ? 1 : 0,
                child: ClipRect(
                  child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(9),
                        ),
                    ),
                    _buildOpacitySlider(theme),
                  ],
                ),
                ),
              ),
          ),
        ),
        const Spacer(),
        if (_scanning && availableWidth >= 190)
          RepaintBoundary(
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: theme.accentColor,
              ),
            ),
          ),
        SizedBox(width: availableWidth < 190 ? 1 : 3),
        // 极简设置按钮（与右键菜单等价）
        IconButton(
          key: _gearKey,
          onPressed: _openMenuAtGear,
          tooltip: '菜单',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          icon: Icon(
            Icons.settings_outlined,
            size: 15,
            color: theme.dimTextColor,
          ),
        ),
        ],
      ),
    );
  }

  Widget _buildOpacitySlider(AppTheme theme) {
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
        activeTrackColor: theme.accentColor,
        inactiveTrackColor: theme.subTextColor.withValues(alpha: 0.35),
        thumbColor: theme.titleColor,
      ),
      child: Slider(
        value: _backgroundOpacity,
        min: 0.55,
        max: 1.0,
        onChanged: _setBackgroundOpacity,
      ),
    );
    return slider;
  }

  /// 进度区域：根据窗口宽高比自适应横向 / 竖向布局
  /// [windowSize] 为清洗后的窗口尺寸（用于窄窗强制竖排与文本宽度计算）。
  Widget _buildProgressArea(
      double animatedPercent, AppTheme theme, Size windowSize) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(
          _sanitizeExtent(constraints.maxWidth),
          _sanitizeExtent(constraints.maxHeight),
        );
        if (_decidePortrait(area, windowSize)) {
          return _buildVerticalLayout(animatedPercent, theme, windowSize);
        }
        return _buildHorizontalLayout(animatedPercent, theme);
      },
    );
  }

  /// 上一次生效的布局模式（横竖切换迟滞锁存）
  bool _portraitLatched = false;

  /// 横竖布局判定（带迟滞死区）。
  /// 严格按「高>宽」切换时，在边界附近拖拽缩放会让整棵布局子树
  /// 逐帧在两个模式间抖动重建（表现为卡顿，极端时反复触发布局异常）。
  /// 这里保持上一次的模式，只有明显越过死区（8px）才真正切换。
  bool _decidePortrait(Size area, Size window) {
    bool portrait;
    if (_targetPath == null) {
      portrait = false;
    } else if (window.width < kNarrowWindowWidth) {
      portrait = true; // 窄窗口横向布局放不下，强制竖排
    } else if (_portraitLatched) {
      portrait = area.height > area.width - kPortraitDeadZone;
    } else {
      portrait = area.height > area.width + kPortraitDeadZone;
    }
    _portraitLatched = portrait;
    return portrait;
  }

  // ---------------- 横向布局（默认） ----------------
  Widget _buildHorizontalLayout(double animatedPercent, AppTheme theme) {
    final result = _result;
    final showNumbers = _targetPath != null && result != null;
    final isTriline = result?.format == 'triline';
    final total = result?.totalLines ?? 0;
    final translated = (animatedPercent * total).round();
    final String mainText = showNumbers
        ? '$translated / $total '
            '(${(animatedPercent * 100).toStringAsFixed(1)}%)'
        : '-- / -- (0.0%)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 主进度条（triline=TR2 定稿；siglus/generic=翻译）
        SizedBox(
          height: _barThickness(),
          width: double.infinity,
          child: ProgressBarView(
            value: animatedPercent,
            orientation: Axis.horizontal,
            theme: theme,
            style: _barStyle,
            isMain: true,
            animations: _animations,
          ),
        ),
        const SizedBox(height: 6),
        _progressText(
          isTriline ? '定稿  $mainText' : mainText,
          theme,
          main: true,
        ),
        if (isTriline) ...[
          const SizedBox(height: 10),
          // 副进度条（TR1 初翻）
          SizedBox(
            height: _barThickness(),
            width: double.infinity,
            child: ProgressBarView(
              value: result?.draftPercent ?? 0.0,
              orientation: Axis.horizontal,
              theme: theme,
              style: _barStyle,
              isMain: false,
              animations: _animations,
            ),
          ),
          const SizedBox(height: 6),
          _progressText(
            showNumbers
                ? '初翻  ${result.draftTranslated} / '
                    '${result.draftTotal} '
                    '(${(result.draftPercent * 100).toStringAsFixed(1)}%)'
                : '初翻  -- / -- (0.0%)',
            theme,
            main: false,
          ),
        ],
        const SizedBox(height: 8),
        _buildStatusLine(theme),
      ],
    );
  }

  // ---------------- 竖向布局（窗口高 > 宽） ----------------
  Widget _buildVerticalLayout(
      double animatedPercent, AppTheme theme, Size windowSize) {
    final result = _result;
    final showNumbers = _targetPath != null && result != null;
    final isTriline = result?.format == 'triline';
    final total = result?.totalLines ?? 0;
    final translated = (animatedPercent * total).round();

    final winW = _sanitizeExtent(windowSize.width);
    final availableWidth = math.max(92.0, winW - 20);
    final barWidth = (availableWidth * (isTriline ? 0.43 : 0.68))
        .clamp(42.0, 86.0);

    Widget verticalBarGroup(double value, {required String label, required bool main}) {
      return Column(
        children: [
          Expanded(
            child: SizedBox(
              width: barWidth,
              child: ProgressBarView(
                value: value,
                orientation: Axis.vertical,
                theme: theme,
                style: _barStyle,
                isMain: main,
                animations: _animations,
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: barWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$label ${(value * 100).toStringAsFixed(1)}%',
                maxLines: 1,
                style: TextStyle(fontSize: 10, color: theme.subTextColor),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isTriline) ...[
                verticalBarGroup(result?.draftPercent ?? 0.0,
                    label: '初翻', main: false),
                const SizedBox(width: 4),
              ],
              verticalBarGroup(animatedPercent,
                  label: isTriline ? '定稿' : '翻译', main: true),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: math.max(0.0, math.min(120, winW - 20)),
          child: Text(
            showNumbers ? '$translated/$total' : '--/--',
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: theme.dimTextColor),
          ),
        ),
      ],
    );
  }

  double _barThickness() => 11;

  Widget _progressText(String text, AppTheme theme,
      {required bool main}) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontSize: main ? 19 : 14,
          fontWeight: main ? FontWeight.w700 : FontWeight.w500,
          color: main ? theme.textColor : theme.subTextColor,
          letterSpacing: 0.3,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _buildStatusLine(AppTheme theme) {
    final result = _result;
    Color color = theme.dimTextColor;
    String text;

    if (_error != null) {
      text = _error!;
      color = theme.dangerColor;
    } else if (_targetPath == null) {
      text = '右键点击 → 选择目标文件夹';
      color = theme.dimTextColor;
    } else if (result == null) {
      text = _scanning ? '正在扫描…' : '等待刷新…';
    } else if (result.fileCount == 0 && result.errorFiles > 0) {
      text = '脚本文件读取失败（可能正被其他程序占用）';
      color = theme.warnColor;
    } else if (result.totalLines == 0) {
      text = '未找到有效脚本行（${result.fileCount} 个文件）';
    } else {
      text = '监控中 · ${result.targetLabel} · ${result.fileCount} 个文件';
      if (result.errorFiles > 0) text += ' · ${result.errorFiles} 个跳过';
      if (_scanning) text = '扫描中… $text';
    }

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: color, letterSpacing: 0.3),
    );
  }

  // ---------------- 边缘缩放手柄 ----------------
  Widget _buildResizeHandles(Size size) {
    const edge = 7.0;
    const corner = 16.0;
    // 快速缩放的中间帧里窗口可能短暂小于最小尺寸：
    // 负宽高的 Rect 传给 Positioned（紧约束）会触发布局断言，钳到非负。
    final midW = math.max(0.0, size.width - corner * 2);
    final midH = math.max(0.0, size.height - corner * 2);

    Widget zone(_ResizeEdge e, Rect r) {
      return Positioned.fromRect(
        rect: r,
        child: _buildResizeZone(e),
      );
    }

    return Stack(
      children: [
        zone(_ResizeEdge.left, Rect.fromLTWH(0, corner, edge, midH)),
        zone(_ResizeEdge.right,
            Rect.fromLTWH(math.max(0.0, size.width - edge), corner, edge, midH)),
        zone(_ResizeEdge.top,
            Rect.fromLTWH(corner, 0, midW, edge)),
        zone(_ResizeEdge.bottom,
            Rect.fromLTWH(corner, math.max(0.0, size.height - edge), midW, edge)),
        zone(_ResizeEdge.tl, const Rect.fromLTWH(0, 0, corner, corner)),
        zone(_ResizeEdge.tr,
            Rect.fromLTWH(math.max(0.0, size.width - corner), 0, corner, corner)),
        zone(_ResizeEdge.bl,
            Rect.fromLTWH(0, math.max(0.0, size.height - corner), corner, corner)),
        zone(_ResizeEdge.br,
            Rect.fromLTWH(math.max(0.0, size.width - corner),
                math.max(0.0, size.height - corner), corner, corner)),
      ],
    );
  }

  Widget _buildResizeZone(_ResizeEdge edge) {
    final MouseCursor cursor;
    switch (edge) {
      case _ResizeEdge.left:
      case _ResizeEdge.right:
        cursor = SystemMouseCursors.resizeLeftRight;
      case _ResizeEdge.top:
      case _ResizeEdge.bottom:
        cursor = SystemMouseCursors.resizeUpDown;
      case _ResizeEdge.tl:
      case _ResizeEdge.br:
        cursor = SystemMouseCursors.resizeUpLeftDownRight;
      case _ResizeEdge.tr:
      case _ResizeEdge.bl:
        cursor = SystemMouseCursors.resizeUpRightDownLeft;
    }
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => windowManager.startResizing(switch (edge) {
          _ResizeEdge.left => ResizeEdge.left,
          _ResizeEdge.right => ResizeEdge.right,
          _ResizeEdge.top => ResizeEdge.top,
          _ResizeEdge.bottom => ResizeEdge.bottom,
          _ResizeEdge.tl => ResizeEdge.topLeft,
          _ResizeEdge.tr => ResizeEdge.topRight,
          _ResizeEdge.bl => ResizeEdge.bottomLeft,
          _ResizeEdge.br => ResizeEdge.bottomRight,
        }),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildRestReminder(Size size) {
    final portrait = size.height > size.width || size.width < 230;
    if (portrait) return const SizedBox.shrink();
    final theme = kThemes[_themeIndex];
    final maxWidth = math.max(100.0, math.min(280.0, size.width - 24));
    return Positioned(
      right: 12,
      bottom: 12,
      child: IgnorePointer(
        ignoring: !_reminderVisible,
        // RepaintBoundary：滑入/淡入动画只重绘提醒气泡本身，不牵连卡片
        child: RepaintBoundary(
          child: AnimatedSlide(
          offset: _reminderVisible ? Offset.zero : const Offset(0, 0.38),
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _reminderVisible ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: GestureDetector(
              onTap: _hideReminder,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.menuColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.accentColor.withValues(alpha: 0.34),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x55000000),
                        blurRadius: 12,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Text(
                      _reminderMessages[_reminderIndex],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: theme.titleColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  // ---------------- 菜单 ----------------
  Widget _buildMenu(Size size) {
    final theme = kThemes[_themeIndex];
    final double menuWidth = math.min(248, size.width);
    final menuHeight = _menuContentHeight();
    // 钳非负：缩放中间帧窗口可能极小，负的 maxHeight 约束会触发断言
    final double maxH = math.max(0.0, size.height - 8);
    final bool narrow = size.width < 190;

    // 锚点自适应：超出卡片右 / 下边界时翻转方向，保证菜单完整可见。
    // 窗口比菜单还小时（竖向拉高窗口），菜单顶部对齐并内部滚动，
    // 绝不能因 clamp 上下界倒置而抛异常。
    final maxX = math.max(0.0, size.width - menuWidth);
    final maxY = math.max(0.0, size.height - menuHeight);
    var x = _menuAnchor.dx;
    var y = _menuAnchor.dy;
    if (x + menuWidth > size.width) x -= menuWidth;
    if (y + menuHeight > size.height) y -= menuHeight;
    x = x.clamp(0.0, maxX).toDouble();
    y = y.clamp(0.0, maxY).toDouble();

    return Positioned(
      left: x,
      top: y,
      width: menuWidth,
      child: Material(
        color: theme.menuColor,
        elevation: 14,
        shadowColor: const Color(0xAA000000),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _menuItem(
                  Icons.create_new_folder_outlined,
                  '选择目标文件夹…',
                  () => _runMenuAction(_chooseFolder),
                  narrow: narrow,
                ),
                _menuItem(
                  Icons.description_outlined,
                  '选择目标文件…',
                  () => _runMenuAction(_chooseFile),
                  narrow: narrow,
                ),
                _menuItem(Icons.refresh, '立即刷新',
                    () => _runMenuAction(_refresh), narrow: narrow),
                _menuDivider(theme),
                _menuSectionTitle('配色方案', theme),
                Padding(
                  padding: EdgeInsets.fromLTRB(narrow ? 6 : 14, 4, narrow ? 6 : 14, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < kThemes.length; i++)
                        _themeDot(i, theme),
                    ],
                  ),
                ),
                _menuSectionTitle('进度条样式', theme),
                Padding(
                  padding: EdgeInsets.fromLTRB(narrow ? 6 : 14, 4, narrow ? 6 : 14, 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in BarStyle.values) _styleChip(s, theme),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(narrow ? 6 : 14, 0, narrow ? 6 : 14, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '动画效果',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: theme.titleColor,
                          ),
                        ),
                      ),
                      Transform.scale(
                        scale: narrow ? 0.72 : 1,
                        child: Switch(
                          value: _animations,
                          onChanged: _setAnimations,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          activeThumbColor: theme.accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
                _menuDivider(theme),
                _menuItem(Icons.logout, '退出应用', _exitApp,
                    danger: true, narrow: narrow),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _menuContentHeight() {
    // 内容高度估算（用于菜单方向翻转判断）
    const items = 4 * 40.0; // 4 个动作项
    const divider = 2 * 10.0;
    const sections = 2 * 26.0;
    const dots = 2 * 30.0;
    const chips = 2 * 30.0;
    const toggle = 36.0;
    return items + divider + sections + dots + chips + toggle + 16;
  }

  Widget _menuDivider(AppTheme theme) => Divider(
        height: 10,
        thickness: 1,
        indent: 14,
        endIndent: 14,
        color: Colors.white.withValues(alpha: 0.08),
      );

  Widget _menuSectionTitle(String title, AppTheme theme) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: theme.dimTextColor,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _themeDot(int index, AppTheme theme) {
    final t = kThemes[index];
    final selected = index == _themeIndex;
    return Tooltip(
      message: t.name,
      child: GestureDetector(
        onTap: () => _setTheme(index),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: t.mainGradient),
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 12, color: Colors.white)
              : null,
        ),
      ),
    );
  }

  Widget _styleChip(BarStyle style, AppTheme theme) {
    final selected = style == _barStyle;
    return GestureDetector(
      onTap: () => _setBarStyle(style),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? theme.accentColor.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? theme.accentColor : Colors.white12,
            width: 1,
          ),
        ),
        child: Text(
          style.label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? theme.textColor : theme.subTextColor,
          ),
        ),
      ),
    );
  }

  Widget _menuItem(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
    bool narrow = false,
  }) {
    final theme = kThemes[_themeIndex];
    final Color fg = danger ? theme.dangerColor : theme.titleColor;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: EdgeInsets.symmetric(horizontal: narrow ? 7 : 14),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
