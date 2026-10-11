import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';

/// 导入插件对话框：路径导入 / JSON 内容导入
class ImportPluginDialog extends StatefulWidget {
  final AppState state;
  const ImportPluginDialog({super.key, required this.state});

  @override
  State<ImportPluginDialog> createState() => _ImportPluginDialogState();
}

class _ImportPluginDialogState extends State<ImportPluginDialog> {
  bool _byPath = true;
  final TextEditingController _pathCtl = TextEditingController();
  final TextEditingController _contentCtl = TextEditingController();
  bool _busy = false;
  String _err = '';

  @override
  void dispose() {
    _pathCtl.dispose();
    _contentCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      final body = _byPath
          ? {'path': _pathCtl.text.trim()}
          : {'content': _contentCtl.text.trim()};
      final r = await widget.state.api.postJson('/api/plugin/import', body);
      if (!mounted) return;
      if (r['ok'] == true) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _busy = false;
          _err = (r['error'] ?? '导入失败').toString();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = '导入失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('导入插件'),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('浏览文件')),
                ButtonSegment(value: false, label: Text('粘贴 JSON')),
              ],
              selected: {_byPath},
              onSelectionChanged: (s) => setState(() => _byPath = s.first),
            ),
            const SizedBox(height: 14),
            if (_byPath)
              TextField(
                controller: _pathCtl,
                decoration: const InputDecoration(
                  labelText: '插件 JSON 文件路径',
                  hintText: r'例如 D:\plugins\my-plugin.json',
                ),
                onSubmitted: (_) => _submit(),
              )
            else
              TextField(
                controller: _contentCtl,
                minLines: 8,
                maxLines: 14,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                decoration: const InputDecoration(
                  labelText: '插件 JSON 内容',
                  alignLabelWithHint: true,
                ),
              ),
            if (_err.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_err,
                  style: TextStyle(fontSize: 12, color: cs.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('导入'),
        ),
      ],
    );
  }
}
