import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';
import '../widgets/message_bubble.dart';
import '../widgets/thinking_row.dart';
import '../widgets/tool_card.dart';
import '../dialogs/model_picker.dart';

class ChatPage extends StatelessWidget {
  final AppState state;
  const ChatPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final empty = state.messages.isEmpty && !state.busy;
        return Column(
          children: [
            Expanded(
              child: empty ? _EmptyState(state: state) : _MessageList(state: state),
            ),
            if (!empty) _Composer(state: state),
          ],
        );
      },
    );
  }
}

// ==================== 空状态（opencode 中央 logo + 居中输入框） ====================
class _EmptyState extends StatelessWidget {
  final AppState state;
  const _EmptyState({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final m = state.model(state.currentModelId);
    return Column(
      children: [
        const Spacer(flex: 2),
        // 中央大 logo（大写，颜色清晰）
        Text(
          'DARLING-AI',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            color: dark ? const Color(0xFFB8BEC8) : const Color(0xFF8A9099),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '本地 AI 工作台',
          style: TextStyle(
            fontSize: 14,
            letterSpacing: 5,
            color: dark ? const Color(0xFF6A707C) : const Color(0xFF9AA1AC),
          ),
        ),
        const SizedBox(height: 44),
        _Composer(state: state),
        const Spacer(flex: 2),
        // 底部状态行（仿 opencode：Default Project / 无 Git）
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_outlined, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 5),
              Text('Default Project',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(width: 18),
              Icon(Icons.gite, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 5),
              Text('无 Git',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              if (m != null) ...[
                const SizedBox(width: 18),
                Icon(Icons.smart_toy_outlined, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 5),
                Text(m['display'] ?? m['id'] ?? '',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ==================== 消息列表 ====================
class _MessageList extends StatelessWidget {
  final AppState state;
  const _MessageList({required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final msgs = state.messages;
        // ask 确认弹窗
        if (state.askPending) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showAskDialog(context);
          });
        }
        if (msgs.isEmpty) {
          return const Center(
              child: Text('选择模型开始对话', style: TextStyle(color: Color(0xFF9AA1AC))));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          itemCount: msgs.length + (state.busy ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == msgs.length) {
              return ThinkingRow(text: state.thinkingText);
            }
            final msg = msgs[i];
            switch (msg.kind) {
              case MsgKind.user:
                return MessageBubble(role: 'user', text: msg.text);
              case MsgKind.ai:
                return MessageBubble(role: 'ai', text: msg.text);
              case MsgKind.tool:
                return ToolCard(title: msg.title, content: msg.text, ok: msg.ok);
              case MsgKind.error:
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(msg.text,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: Theme.of(context).colorScheme.error)),
                      ),
                    ],
                  ),
                );
              case MsgKind.think:
                return const SizedBox.shrink();
            }
          },
        );
      },
    );
  }

  Future<void> _showAskDialog(BuildContext context) async {
    final cmd = state.askCmd;
    if (!state.askPending) return;
    state.askPending = false; // 阻止重复弹窗
    final allow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('执行命令确认'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI 请求在按需模式下执行以下命令：',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).brightness == Brightness.dark
                    ? const Color(0xFF21252D)
                    : const Color(0xFFFAFBFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Theme.of(ctx).brightness == Brightness.dark
                        ? kOutlineDark
                        : kOutlineLight),
              ),
              child: Text(cmd, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('拒绝')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('允许')),
        ],
      ),
    );
    await state.answerAsk(allow ?? false);
  }
}

// ==================== 输入区 ====================
class _Composer extends StatefulWidget {
  final AppState state;
  const _Composer({required this.state});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _showSlash = false;
  int _slashSel = 0;

  static const _slashItems = [
    ('/new', '新建对话', Icons.add_comment_outlined),
    ('/rename', '重命名当前对话', Icons.edit_outlined),
    ('/clear', '清空当前对话', Icons.delete_sweep_outlined),
    ('/help', '查看所有命令', Icons.help_outline),
    ('/model', '切换模型', Icons.model_training_outlined),
    ('/export', '导出对话', Icons.file_download_outlined),
  ];

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctl.text;
    if (text.trim().isEmpty || widget.state.busy) return;
    // 斜杠命令
    if (text.startsWith('/')) {
      _runCommand(text.trim());
      return;
    }
    _ctl.clear();
    widget.state.send(text);
  }

  void _runCommand(String text) {
    final cmd = text.split(' ').first.toLowerCase();
    final state = widget.state;
    switch (cmd) {
      case '/new':
        state.newConversation();
        _ctl.clear();
        break;
      case '/rename':
        state.renameActiveConversation(context);
        _ctl.clear();
        break;
      case '/clear':
        state.clearActiveConversation();
        _ctl.clear();
        break;
      case '/model':
        state.switchModelDialog(context);
        _ctl.clear();
        break;
      case '/export':
        state.exportConversation();
        _ctl.clear();
        break;
      case '/help':
      default:
        _showHelpDialog();
        _ctl.clear();
        break;
    }
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('命令列表'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (cmd, desc, _) in _slashItems)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text(cmd,
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: Theme.of(ctx).colorScheme.primary)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(desc)),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _onTextChanged(String v) {
    if (v.startsWith('/') && !v.contains(' ') && widget.state.busy == false) {
      if (!_showSlash) setState(() => _showSlash = true);
    } else {
      if (_showSlash) setState(() => _showSlash = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final busy = widget.state.busy;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 760),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF21252D) : const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: dark ? kOutlineDark : const Color(0xFFE5E7EB), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 斜杠命令面板
              if (_showSlash)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF1A1D24) : const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < _slashItems.length; i++)
                        InkWell(
                          onTap: () {
                            _ctl.text = _slashItems[i].$1;
                            _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
                            setState(() => _showSlash = false);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            child: Row(
                              children: [
                                Icon(_slashItems[i].$3, size: 15, color: cs.onSurfaceVariant),
                                const SizedBox(width: 10),
                                Text(_slashItems[i].$1,
                                    style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w700,
                                        color: cs.primary,
                                        fontSize: 13)),
                                const SizedBox(width: 14),
                                Text(_slashItems[i].$2,
                                    style: TextStyle(fontSize: 13, color: cs.onSurface)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              TextField(
                controller: _ctl,
                focusNode: _focus,
                minLines: 1,
                maxLines: 6,
                enabled: !busy,
                onChanged: _onTextChanged,
                onSubmitted: (_) => _send(),
                style: TextStyle(fontSize: 14, color: cs.onSurface),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: busy ? 'AI 正在回复…' : '随便问点什么，/可查看命令，@可添加上下文...',
                  hintStyle:
                      TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                  contentPadding:
                      const EdgeInsets.fromLTRB(16, 14, 16, 10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  children: [
                    // 当前模型（点击展开下拉面板，opencode 风格）
                    MenuAnchor(
                      alignmentOffset: const Offset(0, 8),
                      style: MenuStyle(
                        backgroundColor: WidgetStatePropertyAll(
                            dark ? const Color(0xFF1D2027) : const Color(0xFFFFFFFF)),
                        surfaceTintColor:
                            WidgetStatePropertyAll(Colors.transparent),
                        elevation: WidgetStatePropertyAll(10),
                        shadowColor: WidgetStatePropertyAll(Colors.black26),
                        side: WidgetStatePropertyAll(
                            BorderSide(color: cs.outlineVariant)),
                        shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        padding: WidgetStatePropertyAll(EdgeInsets.zero),
                      ),
                      menuChildren: [
                        ModelPickerPanel(state: widget.state),
                      ],
                      builder: (context, controller, child) {
                        return InkWell(
                          onTap: () => controller.isOpen
                              ? controller.close()
                              : controller.open(),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.state.currentModelId == null
                                      ? '选择模型'
                                      : (widget.state.model(widget.state
                                              .currentModelId)?['display'] ??
                                          widget.state.currentModelId.toString()),
                                  style: TextStyle(
                                      fontSize: 13, color: cs.onSurface),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Icon(Icons.arrow_drop_down,
                                    size: 16, color: cs.onSurfaceVariant),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const Spacer(),
                    // 停止 / 发送按钮
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: busy
                          ? IconButton.filled(
                              onPressed: () => widget.state.stop(),
                              style: IconButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor: cs.errorContainer,
                                foregroundColor: cs.onErrorContainer,
                              ),
                              icon: const Icon(Icons.stop, size: 18),
                              tooltip: '停止生成',
                            )
                          : FilledButton(
                              onPressed: _send,
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Icon(Icons.arrow_upward, size: 18),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
