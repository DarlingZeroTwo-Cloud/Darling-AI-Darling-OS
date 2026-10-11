import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';

/// 模型选择对话框（对话页顶栏切换模型）
class ModelPickerDialog extends StatelessWidget {
  final AppState state;
  const ModelPickerDialog({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final models = state.models;
    // 按供应商分组
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final raw in models) {
      final m = raw as Map<String, dynamic>;
      final pid = (m['provider_id'] ?? '').toString();
      grouped.putIfAbsent(pid, () => []).add(m);
    }

    return AlertDialog(
      title: const Text('选择模型'),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: SizedBox(
        width: 440,
        height: 460,
        child: models.isEmpty
            ? const Center(
                child: Text('还没有可用模型，请先到“模型”页添加。',
                    style: TextStyle(color: Color(0xFF9AA1AC))))
            : ListView(
                children: [
                  for (final entry in grouped.entries)
                    _Group(
                      provider: state.provider(entry.key),
                      models: entry.value,
                      currentId: state.currentModelId,
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

class _Group extends StatelessWidget {
  final Map<String, dynamic>? provider;
  final List<Map<String, dynamic>> models;
  final String? currentId;
  const _Group(
      {required this.provider, required this.models, required this.currentId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pname = provider?['name'] ?? '未知供应商';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Text(pname,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant)),
        ),
        for (final m in models)
          _ModelRow(model: m, selected: m['id'] == currentId),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  final Map<String, dynamic> model;
  final bool selected;
  const _ModelRow({required this.model, required this.selected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = (model['name'] ?? '').toString();
    final display = (model['display'] ?? name).toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.pop(context, model['id'] as String?),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? cs.primary.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 17,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected
                                  ? cs.onSecondaryContainer
                                  : cs.onSurface)),
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: cs.onSurfaceVariant)),
                    ],
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
