import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';

/// 模型选择浮层面板（opencode 风格：点模型名 → 按钮下方展开面板）
/// 顶部搜索框 + 可滚动模型列表；选择后回调并关闭。
class ModelPickerPanel extends StatefulWidget {
  final AppState state;
  const ModelPickerPanel({super.key, required this.state});

  @override
  State<ModelPickerPanel> createState() => _ModelPickerPanelState();
}

class _ModelPickerPanelState extends State<ModelPickerPanel> {
  final TextEditingController _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _isFree(Map<String, dynamic> m) {
    final s = '${m['name']} ${m['display']} ${m['id']}'.toLowerCase();
    return s.contains('free');
  }

  List<Map<String, dynamic>> _filtered() {
    final all = widget.state.models.cast<Map<String, dynamic>>();
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((m) {
      final hay = '${m['name']} ${m['display']} ${m['provider_id']}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  void _pick(BuildContext context, String id) {
    widget.state.setModel(id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final state = widget.state;
    final list = _filtered();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final m in list) {
      final pid = (m['provider_id'] ?? '').toString();
      grouped.putIfAbsent(pid, () => []).add(m);
    }

    return SizedBox(
      width: 420,
      height: 430,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: TextField(
              controller: _search,
              autofocus: false,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: '搜索模型',
                prefixIcon: const Icon(Icons.search, size: 19),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                filled: true,
                fillColor:
                    dark ? const Color(0xFF262B34) : const Color(0xFFF0F2F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 模型列表（可滚轮滚动）
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      _q.isEmpty ? '还没有可用模型，请先到“模型”页添加。'
                                 : '没有匹配的模型',
                      style: const TextStyle(color: Color(0xFF9AA1AC)),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
                    children: [
                      for (final entry in grouped.entries) ...[
                        _GroupHeader(
                            name: state.provider(entry.key)?['name']
                                    as String? ??
                                '未知供应商'),
                        for (final m in entry.value)
                          _ModelRow(
                            model: m,
                            selected: m['id'] == state.currentModelId,
                            free: _isFree(m),
                            onTap: () => _pick(context, m['id'] as String),
                          ),
                      ],
                    ],
                  ),
          ),
          // 底部：当前选中模型
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF1A1E25) : const Color(0xFFF4F5F7),
              border: Border(
                  top: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.6))),
            ),
            child: Row(
              children: [
                Icon(Icons.radio_button_checked, size: 14, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.model(state.currentModelId)?['display'] as String? ??
                        '未选择模型',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String name;
  const _GroupHeader({required this.name});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 3),
      child: Text(name,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant)),
    );
  }
}

class _ModelRow extends StatelessWidget {
  final Map<String, dynamic> model;
  final bool selected;
  final bool free;
  final VoidCallback onTap;
  const _ModelRow(
      {required this.model,
      required this.selected,
      required this.free,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = (model['name'] ?? '').toString();
    final display = (model['display'] ?? name).toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected
                    ? cs.primary.withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 16,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected
                                  ? cs.onSecondaryContainer
                                  : cs.onSurface)),
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (free) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('免费',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.onTertiaryContainer)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
