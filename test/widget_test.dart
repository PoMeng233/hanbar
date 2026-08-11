import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanbar/scanner/progress_scanner.dart';

void main() {
  group('字符判定', () {
    test('containsHanzi：日文汉字也在区间内', () {
      expect(containsHanzi('今年は、例年を凌ぐほどの早さで夏が来た。'), isTrue);
      expect(containsHanzi('你好世界'), isTrue);
      expect(containsHanzi('こんにちは'), isFalse);
      expect(containsHanzi('konnichiha'), isFalse);
    });

    test('containsKana：平假名/片假名', () {
      expect(containsKana('今年は、例年を凌ぐほどの早さで夏が来た。'), isTrue);
      expect(containsKana('你好世界'), isFalse);
      expect(containsKana('カタカナ'), isTrue);
    });
  });

  group('triline 格式（.tra.txt）扫描', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hanbar_test_');
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('TR1 初翻 / TR2 定稿 双进度', () async {
      final f = File('${dir.path}/test.txt');
      f.writeAsStringSync('''
[1]
ORI=これは原文です。
TR1=这是初翻。
TR2=这是最终定稿。

[2]
ORI=これは二番目の原文です。
TR1=这是初翻二。
TR2=これは二番目の原文です。

[3]
ORI=これは三番目の原文です。
TR1=これは三番目の原文です。
TR2=これは三番目の原文です。
''');
      final r = await scanProgress(targetPath: f.path, isSingleFile: true);
      expect(r.format, 'triline');
      expect(r.totalLines, 3); // 总块数
      expect(r.translatedLines, 1); // 定稿：仅块 1 的 TR2 与原文不同
      expect(r.draftTotal, 3);
      expect(r.draftTranslated, 2); // 初翻：块1、块2 的 TR1 与原文不同
    });

    test('TR1 空行不算初翻', () async {
      final f = File('${dir.path}/test.txt');
      f.writeAsStringSync('''
[1]
ORI=これは原文です。
TR1=
TR2=这是定稿。
''');
      final r = await scanProgress(targetPath: f.path, isSingleFile: true);
      expect(r.draftTranslated, 0); // TR1 为空，不算初翻
      expect(r.translatedLines, 1); // TR2 有翻译
    });

    test('TR2 只填角色名占位（【名】「」）不算翻译', () async {
      final f = File('${dir.path}/test.txt');
      f.writeAsStringSync('''
[1]
ORI=【瑠璃色】「…………」
TR1=【瑠璃色】「」
TR2=【瑠璃色】「」

[2]
ORI=【百々花】「ひさしぶりね」
TR1=【百々花】「」
TR2=【百々花】「好久不见」
''');
      final r = await scanProgress(targetPath: f.path, isSingleFile: true);
      expect(r.totalLines, 2);
      expect(r.translatedLines, 1); // 仅块2 真正翻译
      expect(r.draftTranslated, 0); // 「」占位不算初翻
    });

    test('块头带后缀（[600]opt）仍按块边界统计', () async {
      final f = File('${dir.path}/test.txt');
      f.writeAsStringSync('''
[600]opt
ORI=本編を見る
TR1=本編を見る
TR2=本編を見る

[612]opt
ORI=Ｈシーンを見る
TR1=
TR2=观看H场景
''');
      final r = await scanProgress(targetPath: f.path, isSingleFile: true);
      expect(r.totalLines, 2); // 两个块必须分开统计
      expect(r.translatedLines, 1); // 仅块2 已翻译
    });

    test('TR2 预填与原文相同，不算翻译', () async {
      final f = File('${dir.path}/test.txt');
      f.writeAsStringSync('''
[1]
ORI=【瑠璃色】「…………」
TR1=
TR2=【瑠璃色】「…………」
''');
      final r = await scanProgress(targetPath: f.path, isSingleFile: true);
      expect(r.translatedLines, 0);
    });

    test('TR2 与原文相同但 TR1 已被编辑成占位模板，算翻译', () async {
      final f = File('${dir.path}/test.txt');
      f.writeAsStringSync('''
[1]
ORI=【瑠璃色】「…………」
TR1=【瑠璃色】「」
TR2=【瑠璃色】「…………」

[2]
ORI=【水萌】「…………」
TR1=【水萌】「」
TR2=【水萌】「」

[3]
ORI=【凪】「え？」
TR1=【凪】「え？」
TR2=【凪】「え？」

[4]
ORI=これはまだの文です。
TR1=这是初翻。
TR2=これはまだの文です。
''');
      final r = await scanProgress(targetPath: f.path, isSingleFile: true);
      // 块1：TR1 占位模板 + TR2 内容相同（已处理）→ 算翻译
      // 块2：TR2 为占位「」→ 不算
      // 块3：TR1 与 ORI 相同（未处理预填）→ 不算
      // 块4：TR1 是真实草稿（非占位），但 TR2 未定稿
      expect(r.totalLines, 4);
      expect(r.translatedLines, 1);
      expect(r.draftTranslated, 1); // 仅块4 的初翻
    });
  });

  group('siglus 格式（○/●）扫描', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hanbar_test_');
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('翻译判定基于 ● 与原文比对，忽略人名与占位', () async {
      final f = File('${dir.path}/test.txt');
      f.writeAsStringSync('''
○00001○「こんにちは」
●00001●「你好」

○00002○雪月
●00002●雪月

○00003○％Ｂ
●00003●

○00004○「さようなら」
●00004●「」

○00005○これは未翻訳の文です
●00005●これは未翻訳の文です
''');
      final r = await scanProgress(targetPath: f.path, isSingleFile: true);
      expect(r.format, 'siglus');
      // 块1：翻译了 → total+1, translated+1
      // 块2：人名（与原文相同）→ 忽略
      // 块3：控制块（％Ｂ + 空●）→ 忽略
      // 块4：占位「」→ 未翻译槽位（计入分母）
      // 块5：未翻译（●=○ 且含假名）→ total+1, translated+0
      expect(r.totalLines, 3);
      expect(r.translatedLines, 1);
    });

    test('●为空且原文非控制，视为未翻译槽位', () async {
      final f = File('${dir.path}/test.txt');
      f.writeAsStringSync('''
○00001○「おはよう」
●00001●

○00002○「こんにちは」
●00002●「你好」
''');
      final r = await scanProgress(targetPath: f.path, isSingleFile: true);
      expect(r.totalLines, 2);
      expect(r.translatedLines, 1); // 仅第二块翻译
    });

    test('○人名用简体替换（優子→优子）不算翻译', () async {
      final f = File('${dir.path}/test.txt');
      f.writeAsStringSync('''
○00001○優子
●00001●优子

○00002○雪月
●00002●雪月

○00003○「こんにちは」
●00003●「你好」
''');
      final r = await scanProgress(targetPath: f.path, isSingleFile: true);
      // 块1/块2 是纯人名显示名，整对忽略；仅块3 计入
      expect(r.totalLines, 1);
      expect(r.translatedLines, 1);
    });

    test('真实文件场景：人名替换 + 引号片段 → 0 翻译', () async {
      final f = File('${dir.path}/test.txt');
      f.writeAsStringSync('''
○00001○優子
●00001●优子

○00002○雪月への思いを「おにーちゃん」という殻で隠しながら
●00002●

○00003○【百々花】「ひさしぶりね」
●00003●

○00004○「距離感…一歩下がってみる…」
●00004●「」
''');
      final r = await scanProgress(targetPath: f.path, isSingleFile: true);
      expect(r.totalLines, 3); // 块2/3/4 都是未翻译槽位
      expect(r.translatedLines, 0); // 没有任何翻译
    });
  });

  group('generic 格式扫描', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hanbar_test_');
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('含汉字行为已翻译', () async {
      final f = File('${dir.path}/test.txt');
      f.writeAsStringSync('你好世界\n\\text {cmd}\n; comment\n\nこんにちは');
      final r = await scanProgress(targetPath: f.path, isSingleFile: true);
      expect(r.format, 'generic');
      expect(r.totalLines, 2); // 你好世界 / こんにちは
      expect(r.translatedLines, 1); // 仅含汉字行
    });
  });
}
