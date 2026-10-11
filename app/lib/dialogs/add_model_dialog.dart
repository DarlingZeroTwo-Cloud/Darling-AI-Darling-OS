import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';

/// 添加模型对话框：拉取模型列表（勾选添加）或手动输入
class AddModelDialog extends StatefulWidget {
  final AppState state;
  final Map<String, dynamic> provider;
  const AddModelDialog({super.key, required this.state, required this.provider});

  @override
  State<AddModelDialog> createState() => _AddModelDialogState();
}

class _AddModelDialogState extends State<AddModelDialog> {
  List<String> _fetched = [];
  final Set<String> _selected = {};
  bool _pulling = false;
  String _status = '点击“拉取模型列表”获取可用模型；也可以直接手动输入模型名称。';
  final TextEditingController _manualCtl = TextEditingController();

  @override
  void dispose() {
    _manualCtl.dispose();
    super.dispose();
  }

  Future<void> _pull() async {
    setState(() {
      _pulling = true;
      _status = '正在拉取模型列表…';
    });
    try {
      final r = await widget.state.api.postJson(
          '/api/provider/fetch', {'provider_id': widget.provider['id']});
      if (!mounted) return;
      setState(() {
        _pulling = false;
        final err = r['error'];
        if (err != null && (r['models'] as List? ?? []).isEmpty) {
          _status = '拉取失败：$err\n可手动输入模型名称添加。';
          _fetched = [];
        } else {
          _fetched = (r['models'] as List)
              .map((x) => x.toString())
              .where((x) => x.isNotEmpty)
              .toList();
          _status = '拉取到 ${_fetched.length} 个模型，勾选后点“添加选中”。';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pulling = false;
        _status = '拉取失败：$e\n可手动输入模型名称添加。';
      });
    }
  }

  void _addSelected() {
    final toAdd = _selected
        .where((name) => !widget.state.models.any((m) =>
            m['provider_id'] == widget.provider['id'] && m['name'] == name))
        .toList();
    if (toAdd.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('所选模型都已添加')));
      return;
    }
    for (final name in toAdd) {
      widget.state.models.add({
        'id': '${widget.provider['id']}-$name',
        'provider_id': widget.provider['id'],
        'name': name,
        'display': '${widget.provider['name']} - $name',
      });
    }
    widget.state.saveProvidersModels();
    Navigator.pop(context, true);
  }

  void _addManual() {
    final name = _manualCtl.text.trim();
    if (name.isEmpty) return;
    if (widget.state.models
        .any((m) => m['provider_id'] == widget.provider['id'] && m['name'] == name)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('该模型已存在')));
      return;
    }
    widget.state.models.add({
      'id': '${widget.provider['id']}-$name',
      'provider_id': widget.provider['id'],
      'name': name,
      'display': '${widget.provider['name']} - $name',
    });
    widget.state.saveProvidersModels();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final existing = widget.state.models
        .where((m) => m['provider_id'] == widget.provider['id'])
        .map((m) => m['name'].toString())
        .toSet();
    return AlertDialog(
      title: Text('添加模型 · ${widget.provider['name']}'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 440,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_status,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _pulling ? null : _pull,
                  icon: _pulling
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined, size: 17),
                  label: Text(_pulling ? '拉取中…' : '拉取模型列表'),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _fetched.isEmpty
                  ? Center(
                      child: Text('暂无拉取结果',
                          style: TextStyle(
                              fontSize: 12.5, color: cs.onSurfaceVariant)))
                  : ListView.builder(
                      itemCount: _fetched.length,
                      itemBuilder: (context, i) {
                        final name = _fetched[i];
                        final added = existing.contains(name);
                        return CheckboxListTile(
                          dense: true,
                          value: added || _selected.contains(name),
                          onChanged: added
                              ? null
                              : (v) => setState(() {
                                    if (v == true) {
                                      _selected.add(name);
                                    } else {
                                      _selected.remove(name);
                                    }
                                  }),
                          title: Text(name,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: added
                                      ? cs.onSurfaceVariant
                                      : cs.onSurface)),
                          subtitle: added
                              ? const Text('已添加', style: TextStyle(fontSize: 11))
                              : null,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 6),
            if (_selected.isNotEmpty)
              FilledButton(
                onPressed: _addSelected,
                child: Text('添加选中（${_selected.length}）'),
              ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualCtl,
                    decoration: const InputDecoration(
                      labelText: '手动输入模型名称',
                      hintText: '例如 glm-4-plus',
                    ),
                    onSubmitted: (_) => _addManual(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _addManual,
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: '添加',
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭')),
      ],
    );
  }
}
