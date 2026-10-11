import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';
import '../dialogs/provider_dialog.dart';
import '../dialogs/add_model_dialog.dart';

class ModelsPage extends StatelessWidget {
  final AppState state;
  const ModelsPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('模型',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 2),
                    Text('管理 API 供应商与已添加的模型',
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _addProvider(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加供应商'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                _SectionCard(
                  title: '已连接供应商',
                  pill: '${state.providers.length} 个',
                  child: state.providers.isEmpty
                      ? _EmptyNote(
                          '还没有供应商。点击右上角“添加供应商”，或选择内置供应商（OpenAI / DeepSeek / 智谱等）。')
                      : Column(
                          children: [
                            for (final raw in state.providers)
                              _ProviderRow(
                                provider: raw as Map<String, dynamic>,
                                state: state,
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: '已添加模型',
                  pill: '${state.models.length} 个',
                  child: state.models.isEmpty
                      ? _EmptyNote('还没有模型。为供应商点击“+ 添加模型”，拉取列表或手动输入模型名称。')
                      : Column(
                          children: [
                            for (final raw in state.models)
                              _ModelRow(state: state, m: raw as Map<String, dynamic>),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addProvider(BuildContext context) async {
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ProviderDialog(state: state),
    );
    if (p == null) return;
    final existing = state.provider(p['id']);
    if (existing != null) {
      if ((p['api_key'] ?? '').toString().isNotEmpty) {
        existing['api_key'] = p['api_key'];
        state.saveProvidersModels();
      }
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('供应商“${p['name']}”已存在，Key 已更新')));
      _addModel(context, existing);
      return;
    }
    state.providers.add(p);
    state.saveProvidersModels();
    _addModel(context, p);
  }

  Future<void> _addModel(BuildContext context, Map<String, dynamic> provider) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => AddModelDialog(state: state, provider: provider),
    );
  }

  void _delModel(BuildContext context, Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定删除模型“${m['display']}”？'),
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
      state.models.removeWhere((x) => x['id'] == m['id']);
      await state.saveProvidersModels();
    }
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String pill;
  final Widget child;
  const _SectionCard({required this.title, required this.pill, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: dark
                            ? const Color(0xFF245A52)
                            : const Color(0xFFB8E2DD)),
                  ),
                  child: Text(pill,
                      style: TextStyle(fontSize: 11, color: cs.primary)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(text,
          style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  final Map<String, dynamic> provider;
  final AppState state;
  const _ProviderRow({required this.provider, required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final key = (provider['api_key'] ?? '').toString();
    final nModels = state.models
        .where((m) => m['provider_id'] == provider['id'])
        .length;
    final name = (provider['name'] ?? '未知').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(name.substring(0, 1),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.primary)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                const SizedBox(height: 2),
                Text(
                  '${provider['base_url']} · Key ${key.isEmpty ? '(空)' : key.length > 6 ? '${key.substring(0, 6)}…' : key}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text('$nModels 模型',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AddModelDialog(state: state, provider: provider),
            ),
            child: const Text('+ 添加模型'),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: cs.error,
            tooltip: '删除供应商',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('删除供应商'),
                  content: Text('确定删除"$name"及其所有模型？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
                  ],
                ),
              );
              if (ok == true) {
                await state.api.deleteProvider(provider['id'] as String);
                await state.reload();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  final AppState state;
  final Map<String, dynamic> m;
  const _ModelRow({required this.state, required this.m});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pname = (state.provider(m['provider_id']) ?? const {})['name'] ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.smart_toy_outlined, size: 18, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((m['display'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                Text((m['name'] ?? '').toString() + (pname.isEmpty ? '' : ' · $pname'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _confirmDelete(context),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('删除', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定删除模型“${m['display']}”？'),
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
      state.models.removeWhere((x) => x['id'] == m['id']);
      await state.saveProvidersModels();
    }
  }
}
