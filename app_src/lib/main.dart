import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'bridge.dart';
import 'state.dart';
import 'classic_shell.dart';
import 'widgets/sidebar.dart';
import 'pages/chat_page.dart';
import 'pages/models_page.dart';
import 'pages/plugins_page.dart';
import 'pages/settings_page.dart';

const Color kPrimaryLight = Color(0xFF0F766E);
const Color kPrimaryDark = Color(0xFF2BBBAD);
const Color kBgLight = Color(0xFFF4F5F7);
const Color kBgDark = Color(0xFF15171C);
const Color kSurfaceLight = Color(0xFFFFFFFF);
const Color kSurfaceDark = Color(0xFF1D2027);
const Color kOnSurfaceLight = Color(0xFF1B1E24);
const Color kOnSurfaceDark = Color(0xFFE6E8EE);
const Color kSubLight = Color(0xFF6A707C);
const Color kSubDark = Color(0xFF9AA2AF);
const Color kOutlineLight = Color(0xFFD6DAE1);
const Color kOutlineDark = Color(0xFF3A3F4A);
const Color kSelLight = Color(0xFFE2F3F1);
const Color kSelDark = Color(0xFF163A36);
const Color kErrLight = Color(0xFFD64545);
const Color kErrDark = Color(0xFFF07178);
const Color kOkLight = Color(0xFF2F9E6E);
const Color kOkDark = Color(0xFF5EC798);
const Color kHoverLight = Color(0xFFF0F2F5);
const Color kHoverDark = Color(0xFF262A33);
const Color kMeBubbleLight = Color(0xFFEEF0F4);
const Color kMeBubbleDark = Color(0xFF2A2E37);

/// 跟随系统的深浅主题（MD3 + 高对比，色值映射自 Qt 版）
ThemeData buildTheme(Brightness b, {int? accent}) {
  final dark = b == Brightness.dark;
  final accentColor = accent != null ? Color(accent) : null;
  final primary = accentColor ?? (dark ? kPrimaryDark : kPrimaryLight);
  var scheme = ColorScheme.fromSeed(seedColor: primary, brightness: b);
  scheme = scheme.copyWith(
    primary: primary,
    onPrimary: Colors.white,
    surface: dark ? kSurfaceDark : kSurfaceLight,
    onSurface: dark ? kOnSurfaceDark : kOnSurfaceLight,
    onSurfaceVariant: dark ? kSubDark : kSubLight,
    outline: dark ? kOutlineDark : kOutlineLight,
    outlineVariant: dark ? const Color(0xFF343A45) : const Color(0xFFE4E6EA),
    secondaryContainer: dark ? kSelDark : kSelLight,
    onSecondaryContainer: primary,
    error: dark ? kErrDark : kErrLight,
    surfaceContainerLowest: dark ? kBgDark : kBgLight,
    surfaceContainerLow: dark ? const Color(0xFF191C22) : const Color(0xFFF9FAFB),
    surfaceContainer: dark ? const Color(0xFF21252D) : const Color(0xFFFAFBFC),
    surfaceContainerHigh: dark ? const Color(0xFF262A33) : const Color(0xFFF0F2F5),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // 液态玻璃：全局半透明，透出 Windows 亚克力模糊
    scaffoldBackgroundColor: dark
        ? const Color(0xB31A1D24)
        : const Color(0xE6F2F4F8),
    canvasColor: dark
        ? const Color(0xB31A1D24)
        : const Color(0xE6F2F4F8),
    dividerColor: dark ? kOutlineDark : kOutlineLight,
    fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'Segoe UI', 'Noto Sans CJK SC'],
    cardTheme: CardThemeData(
      color: dark ? const Color(0x9923272F) : const Color(0x99FFFFFF),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dark ? const Color(0x40FFFFFF) : const Color(0x33000000)),
      ),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xF023272F) : const Color(0xF5FFFFFF),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: dark ? const Color(0x40FFFFFF) : const Color(0x33000000)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0x6621252D) : const Color(0x66FFFFFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: dark ? kOutlineDark : kOutlineLight, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: dark ? kOutlineDark : kOutlineLight, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
            color: primary, width: 1.6),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? kSurfaceDark : kSurfaceLight,
      indicatorColor: dark ? kSelDark : kSelLight,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF2D313A) : const Color(0xFF2D313A),
    ),
  );
}

/// 启动前确保后端桥接服务在线（打包后 backend/darling-backend 与 exe 同级）
Process? _backendProc;

Future<void> ensureBackend() async {
  final api = BridgeClient();
  if (await api.ping()) return;

  // 定位后端可执行文件
  String? backend;
  final env = Platform.environment['DARLING_AI_BACKEND'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) {
    backend = env;
  } else {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final cands = [
      '$exeDir/backend/darling-backend.exe',
      '$exeDir/backend/darling-backend',
      '$exeDir/darling-backend.exe',
      '$exeDir/darling-backend',
    ];
    for (final c in cands) {
      if (File(c).existsSync()) {
        backend = c;
        break;
      }
    }
  }
  if (backend == null) {
    // 开发模式：未找到打包后端，依赖手动启动
    return;
  }
  try {
    // 不 detached：持有进程句柄，退出时能干净关闭（释放 GGUF 句柄）
    _backendProc = await Process.start(backend, [], mode: ProcessStartMode.normal);
  } catch (_) {}

  // 轮询等就绪（最长 15 秒）
  for (var i = 0; i < 50; i++) {
    await Future.delayed(const Duration(milliseconds: 300));
    if (await api.ping()) return;
  }
}

/// 关闭后端：先调 /api/shutdown 让它释放 GGUF 文件句柄，再杀进程
Future<void> shutdownBackend() async {
  try {
    final api = BridgeClient();
    // 发 shutdown 请求（不等响应也行）
    final uri = Uri.parse('http://127.0.0.1:19730/api/shutdown');
    await HttpClient().getUrl(uri).timeout(const Duration(seconds: 2));
  } catch (_) {}
  await Future.delayed(const Duration(milliseconds: 400));
  try {
    _backendProc?.kill();
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 构建异常可见化：release 模式不再显示灰色 ErrorWidget，
  // 而是显示带错误信息的红框，方便定位问题
  ErrorWidget.builder = (details) {
    return Material(
      color: const Color(0xFFFFF3F0),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '界面构建出错，请截图反馈：\n${details.exception}',
            style: const TextStyle(color: Color(0xFFB3261E), fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  };
  await ensureBackend();
  final api = BridgeClient();
  final state = AppState(api);
  try {
    await state.load();
  } catch (_) {
    state.messages.add(ChatMsg(MsgKind.error, '无法连接本地桥接服务 (127.0.0.1:19730)。'));
  }
  runApp(DarlingApp(state: state));
}

class DarlingApp extends StatefulWidget {
  final AppState state;
  const DarlingApp({super.key, required this.state});

  @override
  State<DarlingApp> createState() => _DarlingAppState();
}

class _DarlingAppState extends State<DarlingApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 退出时干净关闭后端，释放 GGUF 文件句柄（否则 Windows 删目录报占用）
    shutdownBackend();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android/iOS 切后台时也顺手关一下（桌面端窗口关闭走 dispose）
    if (state == AppLifecycleState.detached) {
      shutdownBackend();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return MaterialApp(
          title: 'darling-ai',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light,
              accent: state.settings['accent_color'] is int
                  ? state.settings['accent_color'] as int
                  : null),
          darkTheme: buildTheme(Brightness.dark,
              accent: state.settings['accent_color'] is int
                  ? state.settings['accent_color'] as int
                  : null),
          themeMode: state.themeMode,
          home: HomeShell(state: state),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  final AppState state;
  const HomeShell({super.key, required this.state});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _nav = 0;

  @override
  void initState() {
    super.initState();
    // 启动时静默检查更新（设置可关）
    if (widget.state.settings['auto_check_update'] == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoCheckUpdate();
      });
    }
  }

  Future<void> _autoCheckUpdate() async {
    try {
      final resp = await http
          .get(Uri.parse(
              'https://api.github.com/repos/DarlingZeroTwo-Cloud/Darling-ai/releases/latest'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final latest =
          ((data['tag_name'] ?? '') as String).replaceFirst(RegExp(r'^v'), '');
      final current = widget.state.appVersion;
      if (latest.isNotEmpty && _versionAtLeast(latest, current) == false) {
        final url = (data['html_url'] ?? '').toString();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('发现新版本 $latest（当前 $current）'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '查看',
            onPressed: () {
              try {
                if (Platform.isWindows) {
                  Process.start('cmd', ['/c', 'start', '', url]);
                } else {
                  Process.start('xdg-open', [url]);
                }
              } catch (_) {}
            },
          ),
        ));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // 经典模式：Zed 风格侧边栏 + 独立窗口
    if (widget.state.uiMode == 'classic') {
      return ClassicShell(state: widget.state);
    }
    // 精简模式：现有顶部标签栏 + 页面切换
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.state.settings;
    final bgImage = (s['bg_image'] ?? '').toString();
    final bgOpacity = (s['bg_opacity'] ?? 0.85).toDouble();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            () => widget.state.newConversation(),
      },
      child: Scaffold(
      backgroundColor: dark ? const Color(0xFF15171C) : const Color(0xFFF4F5F7),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 背景层：自定义图片 or 纯色
          if (bgImage.isNotEmpty && File(bgImage).existsSync())
            Opacity(
              opacity: bgOpacity,
              child: Image.file(File(bgImage), fit: BoxFit.cover),
            ),
          Column(
            children: [
          // 顶部标签栏
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF1D2027) : const Color(0xFFFFFFFF),
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 2),
                // 汉堡菜单：所有页面入口都在这里（新建对话只在右侧 +）
                PopupMenuButton<int>(
                  tooltip: '菜单',
                  icon: Icon(Icons.menu, size: 20, color: cs.onSurfaceVariant),
                  onSelected: (i) => setState(() => _nav = i),
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 0,
                      child: Row(children: [
                        Icon(Icons.forum_outlined, size: 18, color: _nav == 0 ? cs.primary : cs.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Text('对话', style: TextStyle(fontWeight: _nav == 0 ? FontWeight.w600 : FontWeight.w400)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 1,
                      child: Row(children: [
                        Icon(Icons.model_training_outlined, size: 18, color: _nav == 1 ? cs.primary : cs.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Text('模型', style: TextStyle(fontWeight: _nav == 1 ? FontWeight.w600 : FontWeight.w400)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 2,
                      child: Row(children: [
                        Icon(Icons.extension_outlined, size: 18, color: _nav == 2 ? cs.primary : cs.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Text('插件', style: TextStyle(fontWeight: _nav == 2 ? FontWeight.w600 : FontWeight.w400)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 3,
                      child: Row(children: [
                        Icon(Icons.settings_outlined, size: 18, color: _nav == 3 ? cs.primary : cs.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Text('设置', style: TextStyle(fontWeight: _nav == 3 ? FontWeight.w600 : FontWeight.w400)),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(width: 2),
                // 会话标签 + 新对话按钮：只在对话页显示
                if (_nav == 0) ...[
                  PopupMenuButton<String>(
                    tooltip: '历史对话',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_note, size: 15, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          const Text('会话', style: TextStyle(fontSize: 12.5)),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down, size: 16, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                    itemBuilder: (ctx) => [
                      for (final raw in widget.state.conversations)
                        PopupMenuItem(
                          value: raw['id'] as String,
                          child: Text(raw['title'] ?? '未命名',
                              style: TextStyle(
                                fontWeight: raw['id'] == widget.state.activeConvId
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              )),
                        ),
                      if (widget.state.conversations.isEmpty)
                        const PopupMenuItem(enabled: false, child: Text('暂无历史对话')),
                    ],
                    onSelected: (cid) => widget.state.loadConversation(cid),
                  ),
                ],
                const Spacer(),
                if (_nav == 0)
                  IconButton(
                    icon: Icon(Icons.add, size: 20, color: cs.onSurfaceVariant),
                    onPressed: () => widget.state.newConversation(),
                    tooltip: '新对话',
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Expanded(
            child: _nav == 0
                ? ChatPage(state: widget.state)
                : _nav == 1
                    ? ModelsPage(state: widget.state)
                    : _nav == 2
                        ? PluginsPage(state: widget.state)
                        : SettingsPage(state: widget.state),
          ),
        ],
          ),
        ],
      ),
    ),
    );
  }
}

/// 版本比较：latest 是否 >= current
bool _versionAtLeast(String latest, String current) {
  List<int> parse(String v) => v
      .split('.')
      .map((s) => int.tryParse(s.trim()) ?? 0)
      .toList();
  final a = parse(latest), b = parse(current);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return true;
}
