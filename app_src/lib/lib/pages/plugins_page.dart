import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';
import '../dialogs/import_plugin_dialog.dart';

class PluginsPage extends StatefulWidget {
  final AppState state;
  const PluginsPage({super.key, required this.state});

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  int _tick = 0;

  void _reload() => setState(() => _tick++);

  Future<List<Map<String, dynamic>>> _loadPlugins() async {
    final r = await widget.state.api.getJson('/api/plugins');
    return (r['plugins'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  Set<String> get _disabledTools {
    final raw = widget.state.settings['disabled_tools'];
    if (raw is List) return raw.map((e) => e.toString()).toSet();
    if (raw is Map) return (raw as Map<dynamic, dynamic>).keys.map((e) => e.toString()).toSet();
    return {};
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('插件',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                  const SizedBox(height: 2),
                  Text('管理 AI 可调用的扩展工具（联网搜索 / 插件工坊等）',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _import(),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('导入插件'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            key: ValueKey(_tick),
            future: _loadPlugins(),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final plugins = snap.data ?? [];
              if (plugins.isEmpty) {
                return const Center(
                    child: Text('暂无插件。点击“导入插件”添加，或让 AI 通过“插件工坊”自己编写。',
                        style: TextStyle(color: Color(0xFF9AA1AC))));
              }
              final disabled = _disabledTools;
              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  for (final p in plugins)
                    _PluginCard(
                      plugin: p,
                      disabledTools: disabled,
                      onToggle: (tool, enabled) =>
                          _toggleTool(p, tool, enabled),
                      onDelete: () => _delete(p),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _import() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ImportPluginDialog(state: widget.state),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('插件已导入并生效')));
      _reload();
    }
  }

  Future<void> _toggleTool(
      Map<String, dynamic> p, Map<String, dynamic> tool, bool enabled) async {
    final dis = _disabledTools;
    final key = '${p['name']}::${tool['name']}';
    if (enabled) {
      dis.remove(key);
    } else {
      dis.add(key);
    }
    widget.state.settings['disabled_tools'] = dis.toList();
    await widget.state.saveSettings();
    if (mounted) _reload();
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除插件'),
        content: Text('确定删除插件“${p['name']}”？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await widget.state.api
          .postJson('/api/plugin/delete', {'id': p['id'] ?? p['name']});
      _reload();
    }
  }
}

class _PluginCard extends StatelessWidget {
  final Map<String, dynamic> plugin;
  final Set<String> disabledTools;
  final void Function(Map<String, dynamic> tool, bool enabled) onToggle;
  final VoidCallback onDelete;

  const _PluginCard({
    required this.plugin,
    required this.disabledTools,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tools = (plugin['tools'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              Icon(Icons.extension, size: 18, color: cs.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text('${plugin['name']}',
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
              ),
              Text('v${plugin['version'] ?? '?'}',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
              const SizedBox(width: 6),
              Text('${plugin['id']}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              IconButton(
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline,
                    size: 17, color: cs.onSurfaceVariant),
                tooltip: '删除插件',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Text(plugin['description'] ?? '',
              style:
                  TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('作者：${plugin['author'] ?? '未知'}',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 6),
          for (final t in tools)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((t['name'] ?? '').toString(),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface)),
                      Text((t['description'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Switch(
                  value: !disabledTools.contains('${plugin['name']}::${t['name']}'),
                  onChanged: (v) => onToggle(t, v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
