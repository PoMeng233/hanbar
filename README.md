# 汉化进度实时统计 · 桌面悬浮窗（hanbar）

轻量级 Flutter Desktop（Windows / macOS）小工具：始终置顶的透明悬浮窗，
实时显示汉化脚本的翻译进度；文件被外部编辑器 / 封包工具改动时自动重算。
vibe的，自用，动画和支持文本格式暂不完善

## 功能

- 无边框、置顶、透明圆角卡片悬浮窗
- 卡片任意位置按住左键拖动窗口
- 右键（或右上角齿轮）菜单：
  「选择目标文件夹…」「选择目标文件…」「立即刷新」「退出应用」
- 进度条平滑动画 + 进度文本（如 `1234 / 5678 (21.7%)`）
- 全部扫描 / 解析在后台 Isolate 完成，UI 零卡顿
- 只读方式一次性读入文件，不加锁，完全不影响外部程序写入或封包
- `watcher` 轻量目录监听，保存后自动刷新（500ms 防抖）
- 记住上次选择的目标，重启自动恢复

## 首次运行

1. 安装 Flutter（3.13 及以上），并启用桌面支持：

   ```sh
   flutter config --enable-windows-desktop --enable-macos-desktop
   ```

2. Windows：双击 `setup.bat`（自动生成 windows/macos 平台工程并安装依赖）。
   macOS / 手动方式：在本目录执行

   ```sh
   flutter create --project-name hanbar --platforms=windows,macos .
   flutter pub get
   ```

   > 目录名带有空格，因此必须用 `--project-name` 指定合法包名。

3. 运行：

   ```sh
   flutter run -d windows     # 或 -d macos
   ```

   发布 Release：

   ```sh
   flutter build windows --release
   ```

> **macOS 注意**：若 Release 构建无法使用「选择文件夹 / 文件」对话框，
> 请在 `macos/Runner/Release.entitlements` 中追加：
> `<key>com.apple.security.files.user-selected.read-write</key><true/>`

## 使用

1. 启动后右键点击卡片 →「选择目标文件夹…」，选中汉化脚本根目录
   （例如 True Colors 的 `trans_work` 目录，内含 `*.ybn.tra.txt`）。
2. 进度条与「已翻译 / 总有效行」实时显示；在编辑器里保存文件后自动刷新。
3. 也可以「选择目标文件…」仅统计单个脚本文件。

## 统计口径（lib/scanner/progress_scanner.dart）

- 递归扫描扩展名为 `yst` / `txt` 的脚本（常量 `kScriptExtensions`，可增删）
- **已翻译判定 = 译文槽内容 ≠ 原文**（预填的日文原文不算翻译）
- 百分比 = 已翻译 ÷ 总槽位数

> 为什么不看“是否含汉字”？因为日文汉字也在 U+4E00–U+9FA5 区间内，
> 纯日文的原文行会因此被误判为“已翻译”。必须与原文比对。

扫描时自动检测三种脚本格式：

| 格式 | 说明 | 统计方式 |
| --- | --- | --- |
|Yuristool提取的三行（`.tra.txt`） | 块结构 `[编号]` / `ORI=` 原文 / `TR1=` 初翻 / `TR2=` 定稿 | **双进度条**：TR1 初翻进度、TR2 定稿进度（各自与 ORI 比对，不同才算完成） |
| siglus（○/● 配对脚本） | ○ 行为原文，● 行为翻译槽位 | 单进度条：● 内容 ≠ ○ 原文算已翻译；**忽略**：空 ●（动画控制块）、纯人名行、占位 `「」` |
| generic（普通文本） | 无上述标记 | 有效行 = 非空且不以 `\`/`;` 开头；含汉字行为已翻译 |

遍历时会自动忽略构建产物与隐藏目录（`build`、`windows`、`macos`、`.git`、`node_modules` 等，常量 `kIgnoredDirNames`）。

若需严格按通用规则统计，可自行修改上述函数。

## 文件安全设计（核心）

- 读取一律使用只读一次性加载（`readAsBytesSync`），读完立即释放句柄，
  不使用写模式、不创建锁文件，绝不阻塞外部编辑器 / 封包工具；
- 文件正被其他程序独占时，跳过该文件并计数显示（如「N 个跳过」），绝不等待；
- 编码自动识别：UTF-8 → 回退 GBK（`fast_gbk`，纯 Dart）→ 宽松 UTF-8 兜底；
- 文件扫描与逐行解析全部在 `Isolate.run` 后台线程完成。

## 代码结构

```
lib/
├── main.dart                       # 入口：窗口初始化（无边框/置顶/透明）
├── scanner/
│   └── progress_scanner.dart       # 后台扫描 + 统计口径（核心提取函数）
└── ui/
    └── progress_card.dart          # 悬浮卡片 UI + 右键菜单 + 文件监听
test/widget_test.dart               # 统计口径单元测试
tool/scan_smoke.dart                # 扫描冒烟测试（dart run tool/scan_smoke.dart <目录>）
```
