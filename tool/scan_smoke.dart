import 'dart:io';

import 'package:hanbar/scanner/progress_scanner.dart';

/// 扫描冒烟测试（不依赖 Flutter，直接跑核心扫描逻辑）：
///   dart run tool/scan_smoke.dart <目标目录或文件>
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tool/scan_smoke.dart <目标目录或文件>');
    exitCode = 1;
    return;
  }
  final target = args.first;
  final isFile = FileSystemEntity.isFileSync(target);
  final result = await scanProgress(targetPath: target, isSingleFile: isFile);

  stdout.writeln('目标   : $target');
  stdout.writeln('模式   : ${isFile ? '单文件' : '目录'}');
  stdout.writeln('格式   : ${result.format}');
  stdout.writeln('文件数 : ${result.fileCount}（跳过 ${result.errorFiles}）');
  stdout.writeln('主进度 : ${result.translatedLines} / ${result.totalLines} '
      '(${(result.percent * 100).toStringAsFixed(1)}%)');
  if (result.draftTotal > 0) {
    stdout.writeln('初翻   : ${result.draftTranslated} / ${result.draftTotal} '
        '(${(result.draftPercent * 100).toStringAsFixed(1)}%)');
  }
  stdout.writeln('耗时   : ${result.elapsedMillis} ms');
}
