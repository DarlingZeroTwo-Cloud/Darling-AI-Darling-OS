import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';
import '../dialogs/provider_dialog.dart';
import '../dialogs/add_model_dialog.dart';

class ModelsPage extends StatefulWidget {
  final AppState state;
  const ModelsPage({super.key, required this.state});

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  String _query = '';

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // 进入模型市场时，如果已登录，自动刷新云端模型列表
    if (state.cloudLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => state.refreshCloud());
    }
  }

  /// 按名称/ID/供应商名过滤模型
  List<dynamic> _filteredModels(List<dynamic> models) {
    if (_query.isEmpty) return models;
    final q = _query.toLowerCase();
    return models.where((m) {
      final display = (m['display'] ?? '').toString().toLowerCase();
      final name = (m['name'] ?? '').toString().toLowerCase();
      final pname = (state.provider(m['provider_id']) ?? const {})['name']
              ?.toString()
              .toLowerCase() ??
          '';
      return display.contains(q) ||
          name.contains(q) ||
          pname.contains(q);
    }).toList();
  }

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
                // ===== 4.0 官方免费模型分组（登录后显示） =====
                if (state.cloudLoggedIn)
                  _SectionCard(
                    title: '⚡ 官方免费模型',
                    pill: '${state.cloudModels.length} 个 · 5h 额度',
                    child: state.cloudModels.isEmpty
                        ? const _EmptyNote('服务端还没配置模型，等管理员添加。')
                        : Column(
                            children: [
                              for (final raw in state.cloudModels)
                                _CloudModelRow(
                                  model: raw as Map<String, dynamic>,
                                  state: state,
                                ),
                            ],
                          ),
                  )
                else
                  _SectionCard(
                    title: '⚡ 官方免费模型',
                    pill: '未登录',
                    child: const _EmptyNote('到 设置 → 账号 登录后，即可使用官方免费模型（5h 每周期重置额度）。'),
                  ),
                if (state.cloudLoggedIn) const SizedBox(height: 16),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (state.models.isNotEmpty) ...[
                        TextField(
                          onChanged: (v) => setState(() => _query = v.trim()),
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixIcon: Icon(Icons.search, size: 18),
                            hintText: '搜索模型名称 / ID…',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (state.models.isEmpty)
                        _EmptyNote('还没有模型。为供应商点击“+ 添加模型”，拉取列表或手动输入模型名称。')
                      else
                        Column(
                          children: [
                            for (final raw in _filteredModels(state.models))
                              _ModelRow(state: state, m: raw as Map<String, dynamic>),
                          ],
                        ),
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
    final isOfficial = provider['official'] == true || provider['id'] == 'darling-official';
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
                  isOfficial
                      ? '官方云端 · 登录后自动管理，无需填写 Key'
                      : '${provider['base_url']} · Key ${key.isEmpty ? '(空)' : key.length > 6 ? '${key.substring(0, 6)}…' : key}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text('$nModels 模型',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          if (!isOfficial) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => _TestDialog(
                      state: state, providerId: provider['id'] as String),
                );
              },
              child: const Text('测试连接'),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 17),
              color: cs.onSurfaceVariant,
              tooltip: '编辑供应商',
              onPressed: () async {
                final p = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) =>
                      ProviderDialog(state: state, existing: provider),
                );
                if (p == null) return;
                final idx = state.providers
                    .indexWhere((x) => x['id'] == provider['id']);
                if (idx >= 0) {
                  state.providers[idx] = p;
                  await state.saveProvidersModels();
                }
              },
            ),
            const SizedBox(width: 6),
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
        ],
      ),
    );
  }
}

class _CloudModelRow extends StatelessWidget {
  final AppState state;
  final Map<String, dynamic> model;
  const _CloudModelRow({required this.state, required this.model});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final id = (model['id'] ?? '').toString();
    final selected = state.currentModelId == id;
    final type = (model['type'] ?? 'text').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.bolt, size: 18, color: Colors.amber.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((model['name'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                Text('$type · $id',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: selected
                ? null
                : () {
                    state.setModel(id);
                  },
            child: Text(selected ? '使用中' : '选用'),
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

/// 测试供应商连接对话框：自动发起请求并显示结果
class _TestDialog extends StatefulWidget {
  final AppState state;
  final String providerId;
  const _TestDialog({required this.state, required this.providerId});

  @override
  State<_TestDialog> createState() => _TestDialogState();
}

class _TestDialogState extends State<_TestDialog> {
  bool _busy = true;
  bool? _ok;
  String _info = '正在测试连接…';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    final prov = widget.state.provider(widget.providerId);
    // 客户端直连（不依赖本地后端，安卓/桌面统一，证书已全局放行）
    final r = prov == null
        ? {'ok': false, 'error': '供应商不存在'}
        : await widget.state.api.fetchProviderModels(prov);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = r['ok'] == true;
      if (_ok == true) {
        final models = (r['models'] as List<dynamic>? ?? []);
        _info = models.isEmpty
            ? '连接成功（未返回模型列表）'
            : '连接成功，识别到 ${models.length} 个模型：\n${models.join('、')}';
      } else {
        _info = '连接失败：${r['error'] ?? '未知错误'}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('测试连接'),
      content: SizedBox(
        width: 360,
        child: _busy
            ? const Row(children: [
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('正在测试连接…'),
              ])
            : Text(
                _info,
                style: TextStyle(
                    color: _ok == true ? cs.primary : cs.error,
                    fontSize: 13,
                    height: 1.5),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_busy ? '关闭' : '确定'),
        ),
        if (!_busy && _ok != true)
          TextButton(
            onPressed: _run,
            child: const Text('重试'),
          ),
      ],
    );
  }
}
