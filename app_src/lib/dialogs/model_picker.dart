import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';

/// 模型选择对话框（对话页顶栏切换模型）
/// 顶部搜索框 + 可滚动模型列表 + 底部当前模型与管理模型入口。
class ModelPickerDialog extends StatefulWidget {
  final AppState state;
  const ModelPickerDialog({super.key, required this.state});

  @override
  State<ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<ModelPickerDialog> {
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

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      content: SizedBox(
        width: 460,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 搜索框
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: '搜索模型',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: dark ? const Color(0xFF262B34) : const Color(0xFFF0F2F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
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
                      padding: const EdgeInsets.only(bottom: 4),
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
                              onTap: () =>
                                  Navigator.pop(context, m['id'] as String?),
                            ),
                        ],
                      ],
                    ),
            ),
            // 底部：当前模型 + 管理模型
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
              ),
              child: Row(
                children: [
                  Icon(Icons.radio_button_checked,
                      size: 15, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.model(state.currentModelId)?['display'] as String? ??
                          '未选择模型',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openManage(context),
                    icon: const Icon(Icons.tune, size: 16),
                    label: const Text('管理模型'),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openManage(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ManageModelsDialog(state: widget.state),
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
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Text(name,
          style: TextStyle(
              fontSize: 11.5,
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
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
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
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
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
                if (free) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('免费',
                        style: TextStyle(
                            fontSize: 10.5,
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

/// 管理模型：列出所有模型，可删除。
class ManageModelsDialog extends StatefulWidget {
  final AppState state;
  const ManageModelsDialog({super.key, required this.state});

  @override
  State<ManageModelsDialog> createState() => _ManageModelsDialogState();
}

class _ManageModelsDialogState extends State<ManageModelsDialog> {
  final TextEditingController _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filtered() {
    final all = widget.state.models.cast<Map<String, dynamic>>();
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((m) {
      final hay =
          '${m['name']} ${m['display']} ${m['provider_id']}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _remove(BuildContext context, Map<String, dynamic> m) async {
    final cs = Theme.of(context).colorScheme;
    final name = (m['display'] ?? m['name'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定删除“$name”吗？删除后对话中不再显示该模型。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: cs.error, foregroundColor: cs.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.state.deleteModel(m['id'] as String);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final list = _filtered();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
      backgroundColor: dark ? const Color(0xFF1D2027) : const Color(0xFFFAFBFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          children: [
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF21252D) : const Color(0xFFF0F2F5),
                border: Border(bottom: BorderSide(color: cs.outlineVariant)),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('管理模型',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                  const Spacer(),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          size: 17, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: '搜索模型',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const Center(
                      child: Text('没有模型',
                          style: TextStyle(color: Color(0xFF9AA1AC))))
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        for (final m in list)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: cs.outlineVariant
                                          .withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (m['display'] ?? m['name'] ?? '')
                                                .toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: cs.onSurface),
                                          ),
                                          Text(
                                            '${(m['name'] ?? '').toString()} · ${widget.state.provider(m['provider_id'] as String?)?['name'] ?? '未知供应商'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 11.5,
                                                color: cs.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline,
                                          size: 18,
                                          color: cs.error.withValues(alpha: 0.9)),
                                      tooltip: '删除',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _remove(context, m),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
