import 'package:flutter/material.dart';

import '../main.dart';

/// 工具调用卡片（命令执行 / 插件调用）
class ToolCard extends StatelessWidget {
  final String title;
  final String content;
  final bool ok;
  const ToolCard({super.key, required this.title, required this.content, required this.ok});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF21252D) : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: dark ? kOutlineDark : kOutlineLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 15,
                color: ok
                    ? (dark ? kOkDark : kOkLight)
                    : (dark ? kErrDark : kErrLight),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: cs.primary),
                ),
              ),
              Text(ok ? '成功' : '失败',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: ok
                          ? (dark ? kOkDark : kOkLight)
                          : (dark ? kErrDark : kErrLight))),
            ],
          ),
          if (content.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            SelectableText(
              content,
              style: TextStyle(
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
