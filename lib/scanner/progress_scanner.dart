import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:path/path.dart' as p;

/// ==================================================================
///  汉化进度扫描器（运行于后台 Isolate，绝不阻塞 UI 线程）
///
///  支持三种脚本格式（自动检测）：
///   1. triline（如 True Colors 的 .tra.txt）
///       块结构： [编号] / ORI=原文 / TR1=初翻 / TR2=定稿
///       翻译判定：TR1 / TR2 内容 ≠ ORI 原文（预填的日文原文不算翻译）
///       统计两个进度条：TR1 初翻进度、TR2 定稿进度
///   2. siglus（○/● 配对脚本）
///       ○ 行为原文，● 行为翻译槽位
///       忽略：● 空行（动画控制块）、纯人名行、占位「」
///   3. generic（无上述标记的普通文本）：含汉字行为已翻译
/// ==================================================================

/// 参与统计的脚本文件扩展名（可按需增删，例如 's'、'ks'、'ybn' 等）
const Set<String> kScriptExtensions = {'yst', 'txt'};

/// 遍历时忽略的目录名（构建产物 / 隐藏目录 / 平台工程目录等）
const Set<String> kIgnoredDirNames = {
  '.git',
  '.dart_tool',
  '.idea',
  '.vscode',
  '.metadata',
  '.plugin_symlinks',
  'build',
  'dist',
  'node_modules',
  '__pycache__',
  'windows',
  'macos',
  'android',
  'ios',
  'linux',
  'web',
};

/// 忽略的非脚本文本文件（即使扩展名匹配）
const Set<String> kIgnoredFileNames = {'CMakeLists.txt'};

/// 单次扫描结果（纯数据对象，可安全跨 Isolate 传输）
class ScanResult {
  const ScanResult({
    required this.totalLines,
    required this.translatedLines,
    required this.draftTotal,
    required this.draftTranslated,
    required this.format,
    required this.fileCount,
    required this.errorFiles,
    required this.targetLabel,
    required this.elapsedMillis,
  });

  final int totalLines; // 主进度分母（triline=总块数；siglus=可翻译●槽位；generic=有效行）
  final int translatedLines; // 主进度已翻译（triline=TR2 定稿；siglus=●已翻译；generic=含汉字行）
  final int draftTotal; // 副进度分母（仅 triline 有意义=总块数；其他为 0）
  final int draftTranslated; // 副进度已翻译（triline=TR1 初翻）
  final String format; // 'triline' | 'siglus' | 'generic'
  final int fileCount; // 参与统计的脚本文件数
  final int errorFiles; // 读取失败被跳过的文件数（被其他程序独占等）
  final String targetLabel; // 用于界面显示的目录 / 文件名
  final int elapsedMillis; // 本次扫描耗时（毫秒）

  double get percent => totalLines == 0 ? 0.0 : translatedLines / totalLines;

  double get draftPercent =>
      draftTotal == 0 ? 0.0 : draftTranslated / draftTotal;

  /// 形如：1234 / 5678 (21.7%)
  String get summary =>
      '$translatedLines / $totalLines (${(percent * 100).toStringAsFixed(1)}%)';
}

/// 启动一次后台扫描（核心入口）。
/// 实际工作在独立 Isolate 中完成，UI 主线程完全不会卡顿。
Future<ScanResult> scanProgress({
  required String targetPath,
  required bool isSingleFile,
}) {
  return Isolate.run(() => _scanSync(targetPath, isSingleFile));
}

/// 同步扫描逻辑（只在本文件内部使用，运行于后台 Isolate）
ScanResult _scanSync(String targetPath, bool isSingleFile) {
  final stopwatch = Stopwatch()..start();

  // 1. 收集待扫描文件
  final files = <File>[];
  var errorFiles = 0;

  void collect(File file) => files.add(file);

  void walk(Directory dir) {
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      errorFiles++;
      return;
    }
    for (final entity in entries) {
      if (entity is File) {
        if (isScriptFile(entity.path) &&
            !kIgnoredFileNames.contains(p.basename(entity.path))) {
          collect(entity);
        }
      } else if (entity is Directory) {
        if (kIgnoredDirNames.contains(p.basename(entity.path))) continue;
        walk(entity);
      }
    }
  }

  if (isSingleFile) {
    collect(File(targetPath));
  } else {
    final root = Directory(targetPath);
    if (!root.existsSync()) {
      throw FileSystemException('目标目录不存在', targetPath);
    }
    walk(root);
  }

  // 2. 检测格式：读第一个“有内容”的脚本文件，按其中的标记判定
  var format = 'generic';
  for (final file in files) {
    final sample = _readLinesUnlockedSafe(file);
    if (sample == null || sample.isEmpty) continue; // 跳过读取失败/空文件
    format = _detectFormat(sample);
    break;
  }

  // 3. 按格式统计（读取失败的文件在此计数跳过）
  final c = _Counter();
  var fileCount = 0;

  for (final file in files) {
    final lines = _readLinesUnlockedSafe(file);
    if (lines == null) {
      errorFiles++;
      continue;
    }
    fileCount++;
    switch (format) {
      case 'triline':
        _countTriline(lines, c);
      case 'siglus':
        _countSiglus(lines, c);
      default:
        _countGeneric(lines, c);
    }
  }

  return ScanResult(
    totalLines: c.total,
    translatedLines: c.translated,
    draftTotal: c.draftTotal,
    draftTranslated: c.draftTranslated,
    format: format,
    fileCount: fileCount,
    errorFiles: errorFiles,
    targetLabel: isSingleFile ? p.basename(targetPath) : p.basename(targetPath),
    elapsedMillis: stopwatch.elapsedMilliseconds,
  );
}

class _Counter {
  int total = 0;
  int translated = 0;
  int draftTotal = 0;
  int draftTranslated = 0;
}

/// 根据行内容检测脚本格式：
///  - 出现 ORI=/TR1=/TR2= → triline
///  - 出现 ○ / ● 标记 → siglus
///  - 否则 generic
String _detectFormat(List<String> lines) {
  for (final raw in lines.take(200)) {
    final line = raw.trim();
    if (line.startsWith('ORI=') ||
        line.startsWith('TR1=') ||
        line.startsWith('TR2=')) {
      return 'triline';
    }
    if (line.startsWith('○') || line.startsWith('●')) {
      return 'siglus';
    }
  }
  return 'generic';
}

/// ==================================================================
///  格式一：triline（.tra.txt）——块级统计
///  每块：ORI=原文、TR1=初翻、TR2=定稿。
///  翻译判定：去掉角色名标签与引号后，TR2 仍非空，且满足其一：
///   1) TR2 与 ORI 不同（真正的翻译）；或
///   2) TR1 被用户编辑成纯占位模板（如 【角色名】「」）——表示该块已被
///      用户处理过，此时 TR2 即使与 ORI 相同（如 【名】「…………」）
///      也算已翻译（预填的原版文件 TR1 == ORI，不会误判）。
///  注意：TR1 是真实草稿（剥离后非空）时不算"已处理占位"，TR2 相同
///  仍视为未定稿。
/// ==================================================================
void _countTriline(List<String> lines, _Counter c) {
  String? ori, tr1, tr2;

  void flushBlock() {
    final o = ori;
    if (o == null || o.isEmpty) {
      ori = tr1 = tr2 = null;
      return;
    }
    c.total++;
    c.draftTotal++;
    // 对照前先剥离【角色名】与引号噪声：`【瑠璃色】「」` 这类
    // 只填了角色名的占位模板不能算已翻译 / 已初翻。
    final oStripped = _stripNamesAndPlaceholders(o);
    final t1 = (tr1 ?? '').trim();
    final t2 = (tr2 ?? '').trim();
    final s1 = _stripNamesAndPlaceholders(t1);
    final s2 = _stripNamesAndPlaceholders(t2);
    // “用户已处理”信号：TR1 非空、与 ORI 不同、且剥离后为空（纯占位模板）
    final touchedPlaceholder = t1.isNotEmpty && t1 != o && s1.isEmpty;
    if (s1.isNotEmpty && s1 != oStripped) c.draftTranslated++; // TR1 初翻完成
    if (s2.isNotEmpty && (s2 != oStripped || touchedPlaceholder)) {
      c.translated++; // TR2 定稿完成
    }
    ori = tr1 = tr2 = null;
  }

  // 块头形如 `[372]`，也可能带后缀如 `[600]opt`（菜单选项块）
  final blockHeader = RegExp(r'^\[\d+\]');

  for (final raw in lines) {
    final line = raw.trim();
    if (blockHeader.hasMatch(line)) {
      flushBlock(); // 上一块结束
      continue;
    }
    if (line.startsWith('ORI=')) {
      ori = line.substring(4).trim();
    } else if (line.startsWith('TR1=')) {
      tr1 = line.substring(4).trim();
    } else if (line.startsWith('TR2=')) {
      tr2 = line.substring(4).trim();
    }
  }
  flushBlock();
}

/// ==================================================================
///  格式二：siglus（○/● 配对）
///  ○ 行为原文，● 行为翻译槽位。
///  忽略：纯人名行（優子/雪月）、控制标记（％Ｂ）整对。
///  未翻译槽位：● 为空，或仅含引号片段（如「」、」）——引擎用这些
///   片段表示尚未填写的翻译，必须计入分母。
///  翻译判定：● 内容 ≠ ○ 原文（预填的日文原文不算翻译）。
/// ==================================================================
void _countSiglus(List<String> lines, _Counter c) {
  String? pendingOri; // 最近一条 ○ 行的内容（去标记后）

  for (final raw in lines) {
    final line = raw.trim();
    if (line.startsWith('○')) {
      pendingOri = _afterMarker(line)?.trim();
      continue;
    }
    if (!line.startsWith('●')) continue;

    // 人名 / 标记行（○ 无假名、无引号，如 優子 / 雪月 / ％Ｂ）：
    // ● 槽位只是人名替换（如 优子），不是翻译，整对忽略。
    if (_isNameLine(pendingOri)) continue;

    final content = _afterMarker(line)?.trim() ?? '';

    // 空 ●：○ 为纯控制标记（如 ％Ｂ）→ 整对跳过；否则是未翻译槽位
    if (content.isEmpty) {
      if (_isControlOriginal(pendingOri)) continue;
      c.total++;
      continue;
    }

    // 去掉角色名标签与占位引号后，若没有实际内容
    // （如「」、」等引号片段）→ 未翻译槽位（引擎中的空白翻译位）
    final stripped = _stripNamesAndPlaceholders(content);
    if (stripped.isEmpty) {
      if (_isControlOriginal(pendingOri)) continue;
      c.total++;
      continue;
    }

    // 与原文完全相同且不含假名 → 人名类（无需翻译），忽略
    if (pendingOri != null && content == pendingOri && !containsKana(content)) {
      continue;
    }

    c.total++;
    if (pendingOri != null) {
      // 翻译判定：与原文不同
      if (content != pendingOri) c.translated++;
    } else {
      // 无原文可对照（异常情况）：按含汉字兜底
      if (containsHanzi(stripped)) c.translated++;
    }
  }
}

/// ==================================================================
///  格式三：generic（普通文本）
///  有效行 = 非空、不以 \ 或 ; 开头；已翻译 = 行内含汉字。
/// ==================================================================
void _countGeneric(List<String> lines, _Counter c) {
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('\\') || line.startsWith(';')) continue;
    c.total++;
    if (containsHanzi(line)) c.translated++;
  }
}

/// ==================================================================
///  行内容提取与噪声剥离（siglus 专用）
/// ==================================================================

/// 提取 ○/● 标记后的内容：●000006●百百花 → 百百花
String? _afterMarker(String line) {
  final first = line.indexOf(line[0]); // 0
  final second = line.indexOf(line[0], first + 1);
  if (second == -1) return null;
  return line.substring(second + 1);
}

/// 去掉角色名标签【xxx】与占位引号，返回实际内容（可能为空）
String _stripNamesAndPlaceholders(String content) {
  var s = content.replaceAll(RegExp(r'【[^】]*】'), '');
  // 去除各类引号、括号与空白（避免正则转义问题，逐字符替换）
  for (final ch in const [
    '「',
    '」',
    '『',
    '』',
    '“',
    '”',
    '（',
    '）',
    '(',
    ')',
    '"',
    "'",
    ' ',
    '　',
  ]) {
    s = s.replaceAll(ch, '');
  }
  return s.trim();
}

/// ○ 行是否纯人名 / 标记行（无需翻译的整对）：
///  - null / 剥离后为空（如 ％Ｂ）→ 是
///  - 含引号（「『 等）→ 否（是对话行）
///  - 剥离后不含假名 → 是（如 優子 / 雪月 / 純中文人名）
///  - 否则（含假名）→ 否
bool _isNameLine(String? ori) {
  if (ori == null) return true;
  // 含对话引号 → 一定是对话内容，不是人名
  if (ori.contains('「') ||
      ori.contains('『') ||
      ori.contains('“') ||
      ori.contains('"')) {
    return false;
  }
  final s = _stripNamesAndPlaceholders(ori);
  if (s.isEmpty) return true;
  if (containsKana(s)) return false; // 有假名 → 对话 / 叙述行
  return true; // 无假名无引号 → 人名 / 标记行
}

/// ○ 行是否纯控制标记（如 ％Ｂ），对应 ● 行无需翻译
bool _isControlOriginal(String? ori) {
  if (ori == null) return true;
  final s = _stripNamesAndPlaceholders(ori);
  if (s.isEmpty) return true;
  // 无假名、无汉字、无引号内容 → 纯控制符
  if (!containsKana(s) && !containsHanzi(s)) return true;
  return false;
}

/// ==================================================================
///  字符判定工具
/// ==================================================================

/// 是否包含汉字（U+4E00–U+9FA5）。
/// 注意：日文汉字也在此区间，因此判断“是否已翻译”必须结合
/// 与原文比对（见 _countTriline / _countSiglus），不能只看汉字。
bool containsHanzi(String s) {
  for (final rune in s.runes) {
    if (rune >= 0x4E00 && rune <= 0x9FA5) return true;
  }
  return false;
}

/// 是否包含日文假名（平假名 / 片假名）
bool containsKana(String s) {
  for (final rune in s.runes) {
    if (rune >= 0x3040 && rune <= 0x30FF) return true;
    if (rune >= 0x31F0 && rune <= 0x31FF) return true;
  }
  return false;
}

/// 判断路径是否为脚本文件（按扩展名过滤，忽略大小写）
bool isScriptFile(String path) {
  final ext = p.extension(path).toLowerCase();
  return ext.length > 1 && kScriptExtensions.contains(ext.substring(1));
}

/// ==================================================================
///  编码识别与无锁读取（文件安全核心）
/// ==================================================================

/// 只读 + 一次性读入的方式快速加载文件内容，读取后立即释放句柄。
///  - 不使用写模式、不创建锁文件，完全不影响外部编辑器 / 封包工具读写；
///  - 文件被其他程序以独占方式打开时返回 null（由调用方计数跳过）。
List<String>? _readLinesUnlockedSafe(File file) {
  try {
    return _readLinesUnlocked(file);
  } on FileSystemException {
    return null; // 文件正被其他程序独占：跳过，绝不阻塞
  }
}

List<String> _readLinesUnlocked(File file) {
  final bytes = file.readAsBytesSync(); // 一次性读入内存后立即释放句柄
  String text;
  try {
    text = utf8.decode(bytes); // 绝大多数中文脚本为 UTF-8
  } on FormatException {
    try {
      // 非 UTF-8（GBK / Shift-JIS 等）时回退到 GBK 解码
      // （fast_gbk 为纯 Dart 实现，可在后台 Isolate 中安全使用）
      text = gbk.decode(bytes);
    } catch (_) {
      // 兜底：宽松 UTF-8 解码，保证不会因个别字节导致整个文件失败
      text = utf8.decode(bytes, allowMalformed: true);
    }
  }
  text = text.replaceAll('\uFEFF', ''); // 去除 BOM
  return const LineSplitter().convert(text); // 兼容 CRLF / LF / CR 换行
}
