import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 跨窗口控制通道（主窗口注册 handler，悬浮球/悬浮窗 invoke）
const String kCtrlChannel = 'darling_ai';

/// 悬浮球窗口：无边框透明小圆点，常驻所有虚拟桌面
class BallWindow extends StatefulWidget {
  const BallWindow({super.key});

  @override
  State<BallWindow> createState() => _BallWindowState();
}

class _BallWindowState extends State<BallWindow> {
  WindowController? _ctrl;
  bool _panelOpen = false;
  final WindowMethodChannel _channel = const WindowMethodChannel(
    kCtrlChannel,
    mode: ChannelMode.unidirectional,
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = await WindowController.fromCurrentEngine();
    _ctrl = ctrl;
    // 无边框 + 透明 + 置顶 + 固定大小
    final wm = windowManager;
    await wm.setTitle('darling-ball');
    await wm.setAsFrameless();
    await wm.setAlwaysOnTop(true);
    await wm.setSize(const Size(56, 56));
    await wm.setBackgroundColor(Colors.transparent);
    await wm.show();
    if (mounted) setState(() {});
  }

  Future<void> _openPanel() async {
    try {
      await _channel.invokeMethod('openPanel');
    } catch (_) {}
  }

  void _onRightClick(Offset pos) {
    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 1, child: Text('打开主窗口')),
        const PopupMenuItem(value: 2, child: Text('退出 Darling AI')),
      ],
    ).then((v) async {
      if (v == 1) {
        try {
          await _channel.invokeMethod('showMain');
        } catch (_) {}
      } else if (v == 2) {
        try {
          await _channel.invokeMethod('quit');
        } catch (_) {}
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: _openPanel,
        onSecondaryTapDown: (d) => _onRightClick(d.globalPosition),
        child: Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2BBBAD), Color(0xFF0F766E)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: dark ? const Color(0x55FFFFFF) : const Color(0x33FFFFFF),
                width: 1,
              ),
            ),
            child: const Center(
              child: Text(
                '02',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
