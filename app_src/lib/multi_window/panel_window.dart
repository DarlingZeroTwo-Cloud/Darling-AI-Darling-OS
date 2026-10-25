import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../bridge.dart';
import '../state.dart';
import '../widgets/message_bubble.dart';
import '../widgets/tool_card.dart';
import 'ball_window.dart' show kCtrlChannel;
import 'screen_read.dart';

/// 悬浮对话窗：点击悬浮球弹出的快速 AI 对话
class PanelWindow extends StatefulWidget {
  const PanelWindow({super.key});

  @override
  State<PanelWindow> createState() => _PanelWindowState();
}

class _PanelWindowState extends State<PanelWindow> {
  AppState? _state;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _reading = false;
  final WindowMethodChannel _channel = const WindowMethodChannel(
    kCtrlChannel,
    mode: ChannelMode.unidirectional,
  );
  String _modelName = '02';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 无边框悬浮窗：置顶 + 固定尺寸
    final wm = windowManager;
    await wm.setAsFrameless();
    await wm.setAlwaysOnTop(true);
    await wm.setSize(const Size(400, 620));
    await wm.setBackgroundColor(Colors.transparent);

    // 独立 AppState 实例：连接同一本地桥接 → 云端账号/模型/配置共享
    try {
      final st = AppState(BridgeClient());
      await st.load();
      _state = st;
      final mid = st.currentModelId;
      if (mid != null) {
        final m = st.model(mid);
        _modelName = (m?['name'] ?? mid).toString();
      }
      st.addListener(_onState);
      // 未登录先拉一次
      if (st.cloudLoggedIn) st.refreshCloud();
    } catch (_) {}

    // 接收显隐由主窗口 WindowController 直接控制（不在此注册通道 handler，
    // unidirectional 通道全局仅主窗口注册）

    if (mounted) setState(() {});
  }

  void _onState() {
    if (mounted) {
      setState(() {});
      if (_scroll.hasClients) {
        Future.delayed(const Duration(milliseconds: 60), () {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _state?.removeListener(_onState);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final st = _state;
    final text = _input.text.trim();
    if (st == null || text.isEmpty || st.busy) return;
    _input.clear();
    await st.send(text);
  }

  /// 读屏：截图 + OCR → 翻译/解释当前屏幕
  Future<void> _readScreen({bool translate = true}) async {
    final st = _state;
    if (st == null || st.busy) return;
    setState(() => _reading = true);
    final r = await ScreenReader.captureText();
    setState(() => _reading = false);
    if (r['error']!.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r['error']!)),
        );
      }
      return;
    }
    final text = r['text']!;
    if (text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('屏幕上没有识别到文字')),
        );
      }
      return;
    }
    final hint = translate
        ? '请翻译并简要解释以下屏幕内容（原文在下方，直接给出翻译和解释）：\n\n'
        : '请根据以下屏幕内容回答我的问题：\n\n';
    await st.send('$hint$text');
  }

  void _hide() {
    try {
      windowManager.hide();
    } catch (_) {}
  }

  Future<void> _openMain() async {
    try {
      await _channel.invokeMethod('showMain');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xE61D2027) : const Color(0xEFFFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: dark ? const Color(0x66FFFFFF) : const Color(0x40000000),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        margin: const EdgeInsets.all(1),
        child: Column(
          children: [
            // ── 顶栏 ──
            Container(
              height: 42,
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF262A33) : const Color(0xFFF4F6F8),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2BBBAD), Color(0xFF0F766E)],
                      ),
                    ),
                    child: const Center(
                      child: Text('02', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '02 悬浮助手 · $_modelName',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_full, size: 17),
                    tooltip: '打开主窗口',
                    color: cs.onSurfaceVariant,
                    onPressed: _openMain,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 17),
                    tooltip: '收起',
                    color: cs.onSurfaceVariant,
                    onPressed: _hide,
                  ),
                ],
              ),
            ),
            // ── 消息区 ──
            Expanded(
              child: st == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      itemCount: st.messages.length + (st.busy ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i >= st.messages.length) {
                          return Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                const SizedBox(width: 4, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                const SizedBox(width: 8),
                                Text(st.thinkingText.isEmpty ? '正在思考…' : st.thinkingText,
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                              ],
                            ),
                          );
                        }
                        final m = st.messages[i];
                        switch (m.kind) {
                          case MsgKind.user:
                            return MessageBubble(
                                role: 'user', text: m.text, ts: m.ts);
                          case MsgKind.ai:
                            return MessageBubble(
                                role: 'ai',
                                text: m.text,
                                ts: m.ts,
                                modelName: _modelName);
                          case MsgKind.tool:
                            return ToolCard(
                                title: m.title, content: m.text, ok: m.ok);
                          case MsgKind.error:
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(children: [
                                Icon(Icons.error_outline,
                                    size: 15,
                                    color: dark
                                        ? const Color(0xFFF07178)
                                        : const Color(0xFFD64545)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(m.text,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: dark
                                              ? const Color(0xFFF07178)
                                              : const Color(0xFFD64545))),
                                ),
                              ]),
                            );
                          case MsgKind.think:
                            return const SizedBox.shrink();
                        }
                      },
                    ),
            ),
            // ── 输入区 ──
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1D2027) : const Color(0xFFFBFCFD),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                border: Border(
                  top: BorderSide(color: dark ? const Color(0x33FFFFFF) : const Color(0x22000000)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 工具行
                  Row(
                    children: [
                      _toolBtn(
                        icon: Icons.screenshot_monitor,
                        label: '读屏翻译',
                        onTap: _reading ? null : () => _readScreen(translate: true),
                      ),
                      const SizedBox(width: 6),
                      _toolBtn(
                        icon: Icons.remove_red_eye_outlined,
                        label: '读屏提问',
                        onTap: _reading ? null : () => _readScreen(translate: false),
                      ),
                      const Spacer(),
                      if (st != null && st.busy)
                        TextButton(
                          onPressed: () => st.stop(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('停止', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          style: const TextStyle(fontSize: 13.5),
                          decoration: InputDecoration(
                            hintText: '和 02 说点什么…',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        icon: const Icon(Icons.send, size: 18),
                        color: const Color(0xFF0F766E),
                        onPressed: st == null || st.busy ? null : _send,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.secondaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: cs.primary),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, color: cs.primary)),
          ],
        ),
      ),
    );
  }
}
