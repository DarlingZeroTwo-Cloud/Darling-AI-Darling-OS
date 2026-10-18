import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';

const List<Map<String, String>> kDefaultProviders = [
  {'id': 'openai', 'name': 'OpenAI', 'base_url': 'https://api.openai.com/v1'},
  {'id': 'deepseek', 'name': 'DeepSeek', 'base_url': 'https://api.deepseek.com/v1'},
  {'id': 'qwen', 'name': '通义千问(阿里云)', 'base_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1'},
  {'id': 'zhipu', 'name': '智谱 GLM', 'base_url': 'https://open.bigmodel.cn/api/paas/v4'},
  {'id': 'kimi', 'name': 'Moonshot Kimi', 'base_url': 'https://api.moonshot.cn/v1'},
  {'id': 'siliconflow', 'name': '硅基流动', 'base_url': 'https://api.siliconflow.cn/v1'},
  {'id': 'ollama', 'name': 'Ollama(本地)', 'base_url': 'http://localhost:11434/v1'},
];

/// 添加供应商对话框
class ProviderDialog extends StatefulWidget {
  final AppState state;
  final Map<String, dynamic>? existing; // 传入时进入编辑模式
  const ProviderDialog({super.key, required this.state, this.existing});

  @override
  State<ProviderDialog> createState() => _ProviderDialogState();
}

class _ProviderDialogState extends State<ProviderDialog> {
  bool _custom = false;
  String? _presetId;
  String _apiKey = '';
  final TextEditingController _nameCtl = TextEditingController();
  final TextEditingController _urlCtl = TextEditingController();
  final TextEditingController _keyCtl = TextEditingController();
  bool _fullEndpoint = false;

  /// 编辑模式下保留原 id（否则改地址后模型关联丢失）
  String? get _existingId => widget.existing?['id'] as String?;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final eid = e['id'] as String? ?? '';
      final preset = kDefaultProviders.where((p) => p['id'] == eid);
      if (preset.isNotEmpty) {
        // 预设供应商：只允许改 Key
        _presetId = eid;
        _apiKey = (e['api_key'] ?? '').toString();
      } else {
        // 自定义供应商：可改全部字段
        _custom = true;
        _nameCtl.text = (e['name'] ?? '').toString();
        _urlCtl.text = (e['base_url'] ?? '').toString();
        _keyCtl.text = (e['api_key'] ?? '').toString();
        _fullEndpoint = e['full_endpoint'] == true;
      }
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _urlCtl.dispose();
    _keyCtl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _buildResult() {
    if (!_custom) {
      final pid = _presetId;
      if (pid == null) return null;
      final preset = kDefaultProviders.firstWhere((p) => p['id'] == pid);
      return {
        'id': _existingId ?? pid,
        'name': preset['name'],
        'base_url': preset['base_url'],
        'api_key': _apiKey.trim(),
        'full_endpoint': false,
      };
    }
    final name = _nameCtl.text.trim();
    final url = _urlCtl.text.trim();
    if (name.isEmpty || url.isEmpty) return null;
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return {
      'id': _existingId ?? 'custom-$slug',
      'name': name,
      'base_url': url,
      'api_key': _keyCtl.text.trim(),
      'full_endpoint': _fullEndpoint,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: Text(widget.existing == null ? '添加供应商' : '编辑供应商'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('预设供应商')),
                  ButtonSegment(value: true, label: Text('自定义')),
                ],
                selected: {_custom},
                onSelectionChanged: (s) => setState(() => _custom = s.first),
              ),
              const SizedBox(height: 14),
              if (!_custom) ...[
                DropdownMenu<String>(
                  initialSelection: _presetId,
                  dropdownMenuEntries: [
                    for (final p in kDefaultProviders)
                      DropdownMenuEntry(
                          value: p['id']!, label: '${p['name']}  (${p['base_url']})'),
                  ],
                  onSelected: (v) => setState(() => _presetId = v),
                  expandedInsets: EdgeInsets.zero,
                  label: const Text('选择供应商'),
                  width: 430,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyCtl,
                  onChanged: (v) => setState(() => _apiKey = v),
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    hintText: '预设供应商自带 API 地址，只需填 Key（Ollama 本地可留空）',
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _nameCtl,
                  decoration: const InputDecoration(labelText: '供应商名称'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _urlCtl,
                  decoration: const InputDecoration(
                    labelText: 'API 地址',
                    hintText: 'https://api.example.com/v1',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _keyCtl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API Key'),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('完整地址（补全）',
                      style: TextStyle(fontSize: 13.5)),
                  subtitle: const Text('开启后直接使用完整地址请求，不做 /chat/completions 补全',
                      style: TextStyle(fontSize: 11.5)),
                  value: _fullEndpoint,
                  onChanged: (v) => setState(() => _fullEndpoint = v),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final p = _buildResult();
            if (p == null) return;
            Navigator.pop(context, p);
          },
          child: Text(widget.existing == null ? '添加' : '保存'),
        ),
      ],
    );
  }
}
