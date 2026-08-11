import 'package:flutter/material.dart';

/// ==================================================================
///  配色方案与进度条样式定义
/// ==================================================================

/// 进度条样式（每种样式自带配套动画效果）
enum BarStyle {
  classic('经典'),
  drip('滴水'),
  mosaic('马赛克'),
  striped('条纹'),
  glow('发光'),
  wave('波纹');

  const BarStyle(this.label);
  final String label;
}

/// 一套完整的配色方案
class AppTheme {
  const AppTheme({
    required this.name,
    required this.cardColor,
    required this.cardBorder,
    required this.trackColor,
    required this.mainGradient,
    required this.draftGradient,
    required this.titleColor,
    required this.textColor,
    required this.subTextColor,
    required this.dimTextColor,
    required this.accentColor,
    required this.dangerColor,
    required this.warnColor,
    required this.menuColor,
  });

  final String name;
  final Color cardColor; // 卡片背景
  final Color cardBorder; // 卡片描边
  final Color trackColor; // 进度条轨道
  final List<Color> mainGradient; // 主进度条渐变（定稿 / 翻译）
  final List<Color> draftGradient; // 副进度条渐变（初翻）
  final Color titleColor; // 标题文字
  final Color textColor; // 主数字
  final Color subTextColor; // 副数字
  final Color dimTextColor; // 状态 / 次要文字
  final Color accentColor; // 强调色（Logo / 加载圈）
  final Color dangerColor; // 危险 / 错误
  final Color warnColor; // 警告
  final Color menuColor; // 菜单背景
}

/// 全部配色方案
const List<AppTheme> kThemes = [
  // 紫罗兰（默认）
  AppTheme(
    name: '紫罗兰',
    cardColor: Color(0xE6161620),
    cardBorder: Color(0x33FFFFFF),
    trackColor: Color(0xFF26262F),
    mainGradient: [Color(0xFF8B7CFF), Color(0xFF4CC9F0)],
    draftGradient: [Color(0xFF4CC9F0), Color(0xFF6EE7B7)],
    titleColor: Color(0xFFE8EAF0),
    textColor: Colors.white,
    subTextColor: Color(0xFFC4CAD8),
    dimTextColor: Color(0xFF9AA0AF),
    accentColor: Color(0xFF8B7CFF),
    dangerColor: Color(0xFFFF7B72),
    warnColor: Color(0xFFFFB454),
    menuColor: Color(0xF2292736),
  ),
  // 深海
  AppTheme(
    name: '深海',
    cardColor: Color(0xE60A1824),
    cardBorder: Color(0x33E0F7FF),
    trackColor: Color(0xFF12232F),
    mainGradient: [Color(0xFF4FC3F7), Color(0xFF00E5FF)],
    draftGradient: [Color(0xFF00E5FF), Color(0xFF1DE9B6)],
    titleColor: Color(0xFFE1F7FF),
    textColor: Colors.white,
    subTextColor: Color(0xFFBFE3EF),
    dimTextColor: Color(0xFF8FB4C4),
    accentColor: Color(0xFF4FC3F7),
    dangerColor: Color(0xFFFF7B72),
    warnColor: Color(0xFFFFB454),
    menuColor: Color(0xF20E2233),
  ),
  // 森林
  AppTheme(
    name: '森林',
    cardColor: Color(0xE60E1F16),
    cardBorder: Color(0x3366BB6A),
    trackColor: Color(0xFF173022),
    mainGradient: [Color(0xFF66BB6A), Color(0xFFAEEA00)],
    draftGradient: [Color(0xFFAEEA00), Color(0xFF4DB6AC)],
    titleColor: Color(0xFFE9F7EC),
    textColor: Colors.white,
    subTextColor: Color(0xFFC3E3C8),
    dimTextColor: Color(0xFF93B49A),
    accentColor: Color(0xFF66BB6A),
    dangerColor: Color(0xFFFF7B72),
    warnColor: Color(0xFFFFB454),
    menuColor: Color(0xF21A2B1E),
  ),
  // 落日
  AppTheme(
    name: '落日',
    cardColor: Color(0xE6241216),
    cardBorder: Color(0x33FFB74D),
    trackColor: Color(0xFF2E1C18),
    mainGradient: [Color(0xFFFF8A65), Color(0xFFFFD54F)],
    draftGradient: [Color(0xFFFFD54F), Color(0xFFFF7043)],
    titleColor: Color(0xFFFFF3E2),
    textColor: Colors.white,
    subTextColor: Color(0xFFF0D9C0),
    dimTextColor: Color(0xFFC0A488),
    accentColor: Color(0xFFFF8A65),
    dangerColor: Color(0xFFFF7B72),
    warnColor: Color(0xFFFFB454),
    menuColor: Color(0xF22A1A1C),
  ),
  // 赛博霓虹
  AppTheme(
    name: '赛博霓虹',
    cardColor: Color(0xE6130B26),
    cardBorder: Color(0x33FF2D95),
    trackColor: Color(0xFF1E1233),
    mainGradient: [Color(0xFFFF2D95), Color(0xFF7A5CFF)],
    draftGradient: [Color(0xFF7A5CFF), Color(0xFF00E5FF)],
    titleColor: Color(0xFFF5E9FF),
    textColor: Colors.white,
    subTextColor: Color(0xFFD9C8F5),
    dimTextColor: Color(0xFFA78FD0),
    accentColor: Color(0xFFFF2D95),
    dangerColor: Color(0xFFFF7B72),
    warnColor: Color(0xFFFFB454),
    menuColor: Color(0xF21E1233),
  ),
  // 极简
  AppTheme(
    name: '极简',
    cardColor: Color(0xE61A1D23),
    cardBorder: Color(0x33FFFFFF),
    trackColor: Color(0xFF26292F),
    mainGradient: [Color(0xFFE8EAF0), Color(0xFF9AA0AF)],
    draftGradient: [Color(0xFF9AA0AF), Color(0xFF6E7A8C)],
    titleColor: Color(0xFFEDEFF4),
    textColor: Colors.white,
    subTextColor: Color(0xFFC3C8D2),
    dimTextColor: Color(0xFF9398A3),
    accentColor: Color(0xFFE8EAF0),
    dangerColor: Color(0xFFFF7B72),
    warnColor: Color(0xFFFFB454),
    menuColor: Color(0xF2272A30),
  ),
];
