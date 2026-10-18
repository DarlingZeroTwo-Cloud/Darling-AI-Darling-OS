import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';

/// 简化 Markdown 渲染：代码块 / 粗体 / 行内链接
class RichMarkdown extends StatefulWidget {
  final String text;
  final double fontSize;
  const RichMarkdown(this.text, {super.key, this.fontSize = 14});

  @override
  State<RichMarkdown> createState() => _RichMarkdownState();
}

class _RichMarkdownState extends State<RichMarkdown> {
  String? _copiedCode;

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    setState(() => _copiedCode = code);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copiedCode = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final segments = _parse(widget.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final seg in segments)
          if (seg is _CodeBlock)
            Stack(
              children: [
                if (seg.lang != null && seg.lang!.isNotEmpty)
                  Positioned(
                    top: 2,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xFF3FD0C2) : const Color(0xFFE0F2F1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(seg.lang!,
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: dark
                                  ? const Color(0xFF0B2E2B)
                                  : const Color(0xFF0E5E58))),
                    ),
                  ),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  padding: EdgeInsets.fromLTRB(
                      10,
                      (seg.lang != null && seg.lang!.isNotEmpty) ? 24 : 10,
                      10,
                      10),
                  decoration: BoxDecoration(
                    color: dark ? const Color(0x66111318) : const Color(0x88FAFBFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: dark ? kOutlineDark : kOutlineLight),
                  ),
                  child: SelectableText(
                    seg.code,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: widget.fontSize - 1.5,
                      color: dark ? const Color(0xFF3FD0C2) : const Color(0xFF115E58),
                      height: 1.45,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: InkWell(
                    onTap: () => _copyCode(seg.code),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xFF2A2E37) : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        _copiedCode == seg.code ? Icons.check : Icons.copy,
                        size: 13,
                        color: _copiedCode == seg.code ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            )
          else if (seg is _TextSeg)
            _InlineRich(text: seg.text, fontSize: widget.fontSize),
      ],
    );
  }
}

/// 行内富文本（粗体 + 链接）
class _InlineRich extends StatefulWidget {
  final String text;
  final double fontSize;
  const _InlineRich({required this.text, required this.fontSize});

  @override
  State<_InlineRich> createState() => _InlineRichState();
}

class _InlineRichState extends State<_InlineRich> {
  final List<TapGestureRecognizer> _recs = [];

  @override
  void dispose() {
    for (final r in _recs) {
      r.dispose();
    }
    super.dispose();
  }

  void _openUrl(String tapped) {
    final url = RegExp(r'https?://[^\s<]+').firstMatch(tapped)?.group(0);
    if (url == null) return;
    try {
      if (Platform.isWindows) {
        Process.start('cmd', ['/c', 'start', '', url]);
      } else {
        Process.start('xdg-open', [url]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inline = _parseInline(widget.text);
    return SelectableText.rich(
      TextSpan(
        children: [
          for (final p in inline)
            if (p.$2 == 'bold')
              TextSpan(
                text: p.$1,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: widget.fontSize, color: cs.onSurface),
              )
            else if (p.$2 == 'link')
              TextSpan(
                text: p.$1,
                style: TextStyle(
                    fontSize: widget.fontSize,
                    color: cs.primary,
                    decoration: TextDecoration.underline,
                    decorationColor: cs.primary),
                recognizer: (() {
                  final r = TapGestureRecognizer()
                    ..onTap = () => _openUrl(p.$1);
                  _recs.add(r);
                  return r;
                })(),
              )
            else if (p.$2 == 'code')
              TextSpan(
                text: p.$1,
                style: TextStyle(
                    fontSize: widget.fontSize - 1,
                    fontFamily: 'monospace',
                    color: dark ? const Color(0xFF7DE2D6) : const Color(0xFF0E5E58),
                    backgroundColor:
                        dark ? const Color(0x33111318) : const Color(0x33E8EAED)),
              )
            else
              TextSpan(
                text: p.$1,
                style: TextStyle(fontSize: widget.fontSize, color: cs.onSurface),
              ),
        ],
      ),
    );
  }

  List<(String, String)> _parseInline(String s) {
    final out = <(String, String)>[];
    final re = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`|https?://[^\s<]+)');
    var last = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > last) out.add((s.substring(last, m.start), 'plain'));
      final tok = m.group(0)!;
      if (tok.startsWith('**')) {
        out.add((tok.substring(2, tok.length - 2), 'bold'));
      } else if (tok.startsWith('`')) {
        out.add((tok.substring(1, tok.length - 1), 'code'));
      } else {
        out.add((tok, 'link'));
      }
      last = m.end;
    }
    if (last < s.length) out.add((s.substring(last), 'plain'));
    return out;
  }
}

class _CodeBlock {
  final String code;
  final String? lang;
  _CodeBlock(this.code, [this.lang]);
}

class _TextSeg {
  final String text;
  _TextSeg(this.text);
}

List<Object> _parse(String text) {
  final out = <Object>[];
  final re = RegExp(r'```([a-zA-Z0-9_\-]*)\n?([\s\S]*?)```');
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) out.add(_TextSeg(text.substring(last, m.start)));
    out.add(_CodeBlock(m.group(2)!.trimRight(), m.group(1)!.trim()));
    last = m.end;
  }
  if (last < text.length) out.add(_TextSeg(text.substring(last)));
  if (out.isEmpty) out.add(_TextSeg(text));
  return out;
}

/// 消息气泡
class MessageBubble extends StatefulWidget {
  final String role;
  final String text;
  final double ts;
  final bool showTimestamp;
  final String? modelName; // AI 消息显示模型名（设置开启时）
  final VoidCallback? onResend;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  const MessageBubble({super.key, required this.role, required this.text, this.ts = 0, this.showTimestamp = true, this.modelName, this.onResend, this.onEdit, this.onRegenerate});

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _hover = false;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    setState(() => _copied = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isMe = widget.role == 'user';
    final text = widget.text;

    if (isMe) {
      return Align(
        alignment: Alignment.centerRight,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 重新发送（常驻显示）
                  if (widget.onResend != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Tooltip(
                        message: '重新发送',
                        child: InkWell(
                          onTap: widget.onResend,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            child: Icon(Icons.refresh, size: 14, color: cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                  // 编辑（常驻显示）
                  if (widget.onEdit != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Tooltip(
                        message: '编辑',
                        child: InkWell(
                          onTap: widget.onEdit,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            child: Icon(Icons.edit_outlined, size: 14, color: cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 640),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: dark ? const Color(0x992A2E37) : const Color(0x99EEF0F4),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(4),
                      ),
                      border: Border.all(color: dark ? kOutlineDark : kOutlineLight),
                    ),
                    child: RichMarkdown(text, fontSize: 14),
                  ),
                ],
              ),
              if (widget.ts > 0 && widget.showTimestamp)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(_fmtTime(widget.ts),
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                ),
            ],
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('AI',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.modelName != null &&
                          widget.modelName!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(widget.modelName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: cs.onSurfaceVariant)),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: RichMarkdown(text, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                // 复制按钮（常驻显示）
                Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Tooltip(
                      message: _copied ? '已复制' : '复制',
                      child: InkWell(
                        onTap: _copy,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          child: Icon(
                            _copied ? Icons.check : Icons.content_copy,
                            size: 14,
                            color: _copied ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                // 重新生成（常驻显示）
                if (widget.onRegenerate != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Tooltip(
                      message: '重新生成',
                      child: InkWell(
                        onTap: widget.onRegenerate,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          child: Icon(Icons.refresh, size: 14, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (widget.ts > 0 && widget.showTimestamp)
              Padding(
                padding: const EdgeInsets.only(left: 44, top: 2),
                child: Text(_fmtTime(widget.ts),
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }

  static String _fmtTime(double ts) {
    final d = DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }
}
