import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../main.dart';

/// Markdown 渲染（flutter_markdown_plus，表格不包代码框）
class RichMarkdown extends StatelessWidget {
  final String text;
  final double fontSize;
  const RichMarkdown(this.text, {super.key, this.fontSize = 14});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: fontSize, height: 1.55, color: cs.onSurface),
        code: TextStyle(
          fontSize: fontSize - 1,
          fontFamily: 'monospace',
          background: Paint()..color = dark ? const Color(0x333FD0C2) : const Color(0xFFE8F5F3),
          color: dark ? const Color(0xFF7FE8DC) : const Color(0xFF00695C),
        ),
        codeblockDecoration: BoxDecoration(
          color: dark ? const Color(0xFF1E242B) : const Color(0xFFF4F6F8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: dark ? kOutlineDark : kOutlineLight),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        tableHead: TextStyle(fontSize: fontSize - 1, fontWeight: FontWeight.w700, color: cs.onSurface),
        tableBody: TextStyle(fontSize: fontSize - 1, color: cs.onSurface),
        tableColumnPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        blockquote: TextStyle(fontSize: fontSize, color: cs.onSurfaceVariant, height: 1.5),
        h1: TextStyle(fontSize: fontSize + 8, fontWeight: FontWeight.w700, color: cs.onSurface),
        h2: TextStyle(fontSize: fontSize + 5, fontWeight: FontWeight.w700, color: cs.onSurface),
        h3: TextStyle(fontSize: fontSize + 3, fontWeight: FontWeight.w600, color: cs.onSurface),
        a: TextStyle(fontSize: fontSize, color: cs.primary, decoration: TextDecoration.underline),
      ),
    );
  }
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
