import 'package:flutter/material.dart';

import '../state.dart';

/// 系统提示词 查看/编辑对话框
class PromptDialog extends StatefulWidget {
  final AppState state;
  const PromptDialog({super.key, required this.state});

  @override
  State<PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<PromptDialog> {
  late final TextEditingController _ctl =
      TextEditingController(
          text: (widget.state.settings['system_prompt'] ?? '').toString());

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('系统提示词'),
      content: SizedBox(
        width: 520,
        height: 340,
        child: TextField(
          controller: _ctl,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(fontSize: 13.5, height: 1.5),
          decoration: const InputDecoration(
            hintText: '定义 AI 的角色与能力边界…',
            alignLabelWithHint: true,
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
          onPressed: () {
            widget.state.settings['system_prompt'] = _ctl.text;
            widget.state.saveSettings();
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
