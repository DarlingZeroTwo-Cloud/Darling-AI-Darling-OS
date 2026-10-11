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

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctl.text;
    if (text.trim().isEmpty || widget.state.busy) return;
    _ctl.clear();
    widget.state.send(text);
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
              TextField(
                controller: _ctl,
                minLines: 1,
                maxLines: 6,
                enabled: !busy,
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
                    // 当前模型（点击弹出选择，opencode 风格）
                    InkWell(
                      onTap: () async {
                        final picked = await showDialog<String>(
                          context: context,
                          builder: (_) => ModelPickerDialog(state: widget.state),
                        );
                        if (picked != null) widget.state.setModel(picked);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.state.currentModelId == null
                                  ? '选择模型'
                                  : (widget.state.model(widget.state.currentModelId)?['display'] ??
                                      widget.state.currentModelId.toString()),
                              style: TextStyle(fontSize: 13, color: cs.onSurface),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Icon(Icons.arrow_drop_down,
                                size: 16, color: cs.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: FilledButton(
                        onPressed: busy ? null : _send,
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
