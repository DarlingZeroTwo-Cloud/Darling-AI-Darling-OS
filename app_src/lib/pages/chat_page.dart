import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
                return MessageBubble(role: 'user', text: msg.text, ts: msg.ts,
                    showTimestamp: state.settings['show_timestamp'] != false,
                    onResend: () => state.send(msg.text),
                    onEdit: () => state.editMessage(msg.text));
              case MsgKind.ai:
                return MessageBubble(role: 'ai', text: msg.text, ts: msg.ts,
                    showTimestamp: state.settings['show_timestamp'] != false,
                    onRegenerate: () => state.regenerate());
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
  bool _webSearch = false;
  bool _searching = false;
  bool _optimizing = false;
  final List<String> _images = [];

  static const _slashItems = [
    ('/new', '新建对话', Icons.add_comment_outlined),
    ('/rename', '重命名当前对话', Icons.edit_outlined),
    ('/clear', '清空当前对话', Icons.delete_sweep_outlined),
    ('/help', '查看所有命令', Icons.help_outline),
    ('/model', '切换模型', Icons.model_training_outlined),
    ('/export', '导出对话', Icons.file_download_outlined),
  ];

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
    // Esc 清空输入框（FocusNode.onKeyEvent 兼容旧版 Flutter）
    _focus.onKeyEvent = (node, ev) {
      if (ev is KeyDownEvent && ev.logicalKey == LogicalKeyboardKey.escape) {
        if (_ctl.text.isNotEmpty) {
          _ctl.clear();
          setState(() {});
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };
  }

  void _onStateChanged() {
    final d = widget.state.editDraft;
    if (d.isNotEmpty) {
      widget.state.editDraft = '';
      _ctl.text = d;
      _ctl.selection = TextSelection.collapsed(offset: d.length);
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() async {
    final text = _ctl.text;
    if (text.trim().isEmpty || widget.state.busy) return;
    // 斜杠命令
    if (text.startsWith('/')) {
      _runCommand(text.trim());
      return;
    }
    final images = List<String>.from(_images);
    if (images.isNotEmpty) {
      _images.clear();
      _ctl.clear();
      setState(() {});
      widget.state.sendWithImages(text, images);
      return;
    }
    _ctl.clear();
    if (_webSearch) {
      setState(() => _searching = true);
      try {
        final r = await widget.state.api.webSearch(text);
        final results = (r['results'] is List ? r['results'] as List<dynamic> : <dynamic>[])
            .cast<Map<String, dynamic>>();
        widget.state.sendWithWeb(text, results);
      } catch (_) {
        widget.state.send(text);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    } else {
      widget.state.send(text);
    }
  }

  /// AI 优化提示词：把当前输入交给当前模型改写得更结构化
  Future<void> _optimizePrompt() async {
    final text = _ctl.text;
    if (text.trim().isEmpty || widget.state.busy) return;
    setState(() => _optimizing = true);
    try {
      final r = await widget.state.api.postJson('/api/chat', {
        'model_id': widget.state.currentModelId,
        'text':
            '请把下面的用户输入改写成一个更清晰、结构化的提示词（保持原意，不要执行任务本身），只输出改写结果：\n\n$text',
      });
      final jobId = (r['job_id'] ?? '').toString();
      if (jobId.isEmpty) return;
      final sb = StringBuffer();
      await widget.state.api.streamJob(jobId, (ev) {
        final t = ev['text'];
        if (t is String) sb.write(t);
      });
      final optimized = sb.toString().trim();
      if (optimized.isNotEmpty) _ctl.text = optimized;
    } catch (_) {}
    if (mounted) setState(() => _optimizing = false);
  }

  Future<void> _pickImages() async {
    const typeGroup = XTypeGroup(
      label: '图片',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
    );
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    for (final f in files) {
      final path = f.path;
      final file = File(path);
      if (!file.existsSync()) continue;
      try {
        final bytes = await file.readAsBytes();
        final mime = _mimeOf(path);
        final b64 = base64Encode(bytes);
        _images.add('data:$mime;base64,$b64');
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  String _mimeOf(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'image/png';
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

  static const _builtinPrompts = [
    ('代码审查', '请帮我审查以下代码，指出潜在 bug、安全隐患和可优化之处，并给出修改建议：\n'),
    ('写作文案', '请帮我把下面这段内容润色成更专业、更有吸引力的文案：\n'),
    ('翻译', '请把下面这段内容翻译成简体中文，保持原意和语气：\n'),
    ('总结', '请对下面这段内容做简洁总结，提取关键要点：\n'),
    ('周报生成', '请根据下面我的工作内容，帮我生成一份结构清晰的周报：\n'),
    ('头脑风暴', '请针对下面这个主题进行头脑风暴，给出 10 个有创意的想法：\n'),
  ];

  void _showPrompts() {
    final state = widget.state;
    final custom = (state.settings['prompts'] is List ? state.settings['prompts'] as List<dynamic> : <dynamic>[])
        .cast<Map<String, dynamic>>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示词库'),
        content: SizedBox(
          width: 460,
          height: 380,
          child: ListView(
            children: [
              if (custom.isNotEmpty) ...[
                Text('自定义',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                for (final p in custom)
                  _PromptRow(
                    title: (p['title'] ?? '').toString(),
                    desc: (p['text'] ?? '').toString(),
                    onTap: () {
                      final cur = _ctl.text;
                      final t = (p['text'] ?? '').toString();
                      _ctl.text = cur.isEmpty ? t : '$cur\n$t';
                      _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
                      Navigator.pop(ctx);
                    },
                    onDelete: () {
                      state.settings['prompts'] = custom
                          .where((x) => x['title'] != p['title'])
                          .toList();
                      state.saveSettings();
                      Navigator.pop(ctx);
                      _showPrompts();
                    },
                  ),
              ],
              Text('内置',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              for (final (t, txt) in _builtinPrompts)
                _PromptRow(
                  title: t,
                  desc: txt,
                  onTap: () {
                    final cur = _ctl.text;
                    _ctl.text = cur.isEmpty ? txt : '$cur\n$txt';
                    _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addPromptDialog();
            },
            child: const Text('新建提示词'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _addPromptDialog() {
    final state = widget.state;
    final tCtl = TextEditingController();
    final bCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建提示词'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tCtl,
                decoration: const InputDecoration(hintText: '名称（如：代码审查）', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bCtl,
                maxLines: 4,
                decoration: const InputDecoration(hintText: '提示词内容（可包含 {{输入}} 占位）', isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final t = tCtl.text.trim();
              final b = bCtl.text.trim();
              if (t.isEmpty || b.isEmpty) {
                Navigator.pop(ctx);
                return;
              }
              final list = (state.settings['prompts'] is List ? state.settings['prompts'] as List<dynamic> : <dynamic>[])
                  .cast<Map<String, dynamic>>()
                  .toList();
              list.add({'title': t, 'text': b});
              state.settings['prompts'] = list;
              state.saveSettings();
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {    showDialog(
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
              // 已选图片预览
              if (_images.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int i = 0; i < _images.length; i++)
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                base64Decode(_images[i].split(',').last),
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: InkWell(
                                onTap: () =>
                                    setState(() => _images.removeAt(i)),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.close,
                                      size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
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
                    const SizedBox(width: 6),
                    // 助手角色（点击切换预设角色）
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
                        _AssistantRolePanel(state: widget.state),
                      ],
                      builder: (context, controller, child) {
                        return Tooltip(
                          message: '切换助手角色',
                          child: InkWell(
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
                                  Icon(Icons.psychology_outlined,
                                      size: 15, color: cs.primary),
                                  const SizedBox(width: 3),
                                  Text(
                                    _roleLabel(
                                        widget.state.settings['assistant_role']
                                                ?.toString() ??
                                            'general'),
                                    style: TextStyle(
                                        fontSize: 12, color: cs.onSurfaceVariant),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const Spacer(),
                    // 附加图片
                    Tooltip(
                      message: '附加图片（视觉模型）',
                      child: InkWell(
                        onTap: busy ? null : _pickImages,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.image_outlined,
                              size: 17, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // AI 优化提示词
                    Tooltip(
                      message: 'AI 优化提示词',
                      child: InkWell(
                        onTap: busy || _optimizing ? null : _optimizePrompt,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: _optimizing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(Icons.bolt_outlined,
                                  size: 17, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 导出对话为 Markdown
                    Tooltip(
                      message: '导出当前对话为 Markdown',
                      child: InkWell(
                        onTap: busy ? null : widget.state.exportConversation,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.download_outlined,
                              size: 17, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 提示词库
                    Tooltip(
                      message: '提示词库',
                      child: InkWell(
                        onTap: () => _showPrompts(),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.lightbulb_outline,
                              size: 17, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 联网搜索开关（地球）
                    Tooltip(
                      message: _webSearch ? '联网搜索已开启' : '开启联网搜索',
                      child: InkWell(
                        onTap: busy
                            ? null
                            : () => setState(() => _webSearch = !_webSearch),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: _searching
                              ? SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: cs.primary),
                                )
                              : Icon(
                                  Icons.public,
                                  size: 17,
                                  color: _webSearch
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
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

class _AssistantRolePanel extends StatelessWidget {
  final AppState state;
  const _AssistantRolePanel({required this.state});

  static const roles = [
    ('general', '通用助手', '默认，回答简洁准确'),
    ('programmer', '程序员', '代码编写、调试、架构设计'),
    ('writer', '写作助手', '文案、文章、报告与创意写作'),
    ('translator', '翻译', '专业翻译，保留原文语气'),
    ('analyst', '数据分析师', '数据解读、业务分析与逻辑推演'),
    ('mentor', '导师', '把复杂概念讲得通俗易懂'),
    ('hr', 'HR 专家', '简历、面试、职场沟通与规划'),
    ('marketing', '营销策划', '品牌内容、推广文案、增长策略'),
    ('custom', '自定义角色', '在设置中编辑自己的角色提示词'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cur = state.settings['assistant_role']?.toString() ?? 'general';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420, maxWidth: 280),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text('切换助手角色',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
            ),
            for (final (key, label, desc) in roles)
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  state.setAssistantRole(key);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  color: cur == key
                      ? cs.primary.withValues(alpha: 0.10)
                      : Colors.transparent,
                  child: Row(
                    children: [
                      Icon(
                        cur == key
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 15,
                        color: cur == key ? cs.primary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: cur == key
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: cs.onSurface)),
                            Text(desc,
                                style: TextStyle(
                                    fontSize: 11, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

String _roleLabel(String key) {
  for (final (k, label, _) in _AssistantRolePanel.roles) {
    if (k == key) return label;
  }
  return '通用助手';
}

class _PromptRow extends StatelessWidget {
  final String title;
  final String desc;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const _PromptRow({
    required this.title,
    required this.desc,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
            child: Row(
              children: [
                Icon(Icons.bolt_outlined, size: 15, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface)),
                      const SizedBox(height: 1),
                      Text(desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 14),
                    visualDensity: VisualDensity.compact,
                    tooltip: '删除',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(24, 24),
                      padding: EdgeInsets.zero,
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
