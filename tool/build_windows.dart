import 'dart:convert';
import 'dart:io';

/// Windows Release 构建脚本：
/// 由于工作区终端无法 cd 到子目录，这里通过 Process 在指定工作目录中
/// 执行 `flutter build windows --release`，并透传构建输出。
///
/// 用法：dart run tool/build_windows.dart [项目目录(默认 'han clock')]
Future<void> main(List<String> args) async {
  final projectDir = args.isNotEmpty ? args.first : 'han clock';

  stdout.writeln('== 开始构建：$projectDir ==');
  final proc = await Process.start(
    'flutter',
    ['build', 'windows', '--release'],
    workingDirectory: projectDir,
    runInShell: true,
    environment: Map.of(Platform.environment),
  );

  proc.stdout.transform(utf8.decoder).listen((s) => stdout.write(s));
  proc.stderr.transform(utf8.decoder).listen((s) => stderr.write(s));
  final code = await proc.exitCode;
  stdout.writeln('== 构建结束，退出码：$code ==');
  exit(code);
}
