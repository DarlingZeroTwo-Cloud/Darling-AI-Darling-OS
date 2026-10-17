import 'dart:async';
import 'package:flutter/material.dart';

import '../bridge.dart';
import '../main.dart';
import '../state.dart';

class LocalModelsPage extends StatefulWidget {
  final AppState state;
  const LocalModelsPage({super.key, required this.state});

  @override
  State<LocalModelsPage> createState() => _LocalModelsPageState();
}

class _LocalModelsPageState extends State<LocalModelsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<dynamic> _catalog = [];
  List<dynamic> _local = [];
  Map<String, dynamic> _gpu = {};
  String _query = '';
  String _sizeFilter = 'all';
  String _capFilter = 'all';
  final Map<String, Map<String, dynamic>> _dlProgress = {};
  Timer? _poll;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _pollDownloads());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tab.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    // 三个请求独立容错：任一失败（如无 GPU 机器）不影响模型市场列表
    try {
      final c = await widget.state.api.localCatalog();
      if (mounted) setState(() => _catalog = c);
    } catch (_) {}
    try {
      final l = await widget.state.api.localList();
      if (mounted) setState(() => _local = l);
    } catch (_) {}
    try {
      final g = await widget.state.api.localGpu();
      if (mounted) setState(() => _gpu = g);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pollDownloads() async {
    try {
      final r = await widget.state.api.localDownloadsAll();
      final tasks = (r['tasks'] as List<dynamic>? ?? []);
      if (tasks.isEmpty) return;
      setState(() {
        for (final t in tasks) {
          final m = t as Map<String, dynamic>;
          _dlProgress[m['id'] as String] = m;
        }
      });
    } catch (_) {}
  }

  List<dynamic> get _filtered => _catalog.where((raw) {
        final m = raw as Map<String, dynamic>;
        if (_sizeFilter != 'all' && m['size_class'] != _sizeFilter) return false;
        if (_capFilter != 'all' && m['capability'] != _capFilter) return false;
        if (_query.trim().isNotEmpty) {
          final q = _query.toLowerCase();
          final name = (m['name'] as String? ?? '').toLowerCase();
          final blurb = (m['blurb'] as String? ?? '').toLowerCase();
          if (!name.contains(q) && !blurb.contains(q)) return false;
        }
        return true;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
          child: Row(
            children: [
              Text('本地模型',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
              const Spacer(),
              IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text('GGUF 开源模型本地推理，离线可用，隐私安全',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ),
        if (_gpu['cards'] is List && (_gpu['cards'] as List).isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              '显卡：${(_gpu['cards'] as List).join('、')}'
              '${_gpu['has_nvidia'] == true ? '（建议开启 GPU 加速）' : ''}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        TabBar(
          controller: _tab,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          tabs: const [
            Tab(height: 44, text: '模型市场'),
            Tab(height: 44, text: '已下载'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [_marketTab(), _downloadedTab()],
          ),
        ),
      ],
    );
  }

  Widget _marketTab() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: TextField(
            decoration: const InputDecoration(
              hintText: '搜索模型（Qwen / Llama / DeepSeek…）',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        // 大小筛选
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
          child: Row(children: [
            Text('大小', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(width: 8),
            for (final e in {
              'all': '全部',
              'small': '轻量',
              'medium': '中型',
              'large': '重型',
            }.entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(e.value),
                  selected: _sizeFilter == e.key,
                  onSelected: (_) => setState(() => _sizeFilter = e.key),
                ),
              ),
          ]),
        ),
        // 能力筛选
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
          child: Row(children: [
            Text('能力', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(width: 8),
            for (final e in {
              'all': '全部',
              'text': '文本',
              'vision': '识图',
              'image': '生图',
              'video': '生视频',
            }.entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(e.value),
                  selected: _capFilter == e.key,
                  onSelected: (_) => setState(() => _capFilter = e.key),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? Center(child: Text('没有匹配的模型',
                      style: TextStyle(color: cs.onSurfaceVariant)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) =>
                          _modelCard(_filtered[i] as Map<String, dynamic>),
                    ),
        ),
      ],
    );
  }

  Widget _modelCard(Map<String, dynamic> m) {
    final cs = Theme.of(context).colorScheme;
    final supported = m['v1_supported'] != false;
    final dl = _dlProgress.values
        .where((p) => p['catalog_id'] == m['id'])
        .toList();
    final downloading = dl.isNotEmpty ? dl.last : null;
    final isDone = _local.any((l) =>
        (l as Map<String, dynamic>)['path'].toString().endsWith(m['file']));

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(m['name'] as String,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                _tag(_sizeLabel(m['size_class']), cs.secondaryContainer),
                const SizedBox(width: 6),
                _tag(_capLabel(m['capability']), cs.tertiaryContainer),
              ]),
              const SizedBox(height: 6),
              Text(m['blurb'] as String? ?? '',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              const SizedBox(height: 10),
              Row(children: [
                Text('${m['size_mb']} MB · ${m['params_b']}B 参数',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const Spacer(),
                if (isDone)
                  _tag('已就绪', cs.primaryContainer)
                else if (!supported)
                  _tag('下一版开放', cs.errorContainer)
                else if (downloading != null)
                  _downloadControls(downloading)
                else
                  FilledButton.tonal(
                    onPressed: () => _startDownload(m),
                    child: const Text('下载'),
                  ),
              ]),
              if (downloading != null &&
                  (downloading['status'] == 'downloading' ||
                      downloading['status'] == 'paused'))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: _pct(downloading),
                        minHeight: 6,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_mb(downloading['done'])} / ${_mb(downloading['total'])} MB'
                        '${downloading['paused'] == true ? ' · 已暂停' : ''}',
                        style: TextStyle(
                            fontSize: 11.5, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double _pct(Map<String, dynamic> t) {
    final total = (t['total'] is num ? t['total'] as num : 0).toDouble();
    final done = (t['done'] is num ? t['done'] as num : 0).toDouble();
    if (total <= 0) return 0;
    return (done / total).clamp(0.0, 1.0).toDouble();
  }

  String _mb(d) =>
      ((d is num ? d.toDouble() : 0) / 1024 / 1024).toStringAsFixed(0);

  Widget _downloadControls(Map<String, dynamic> t) {
    final paused = t['paused'] == true;
    final id = t['id'] as String;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          if (paused) {
            await widget.state.api.postJson('/api/local/download/resume', {'id': id});
          } else {
            await widget.state.api.postJson('/api/local/download/pause', {'id': id});
          }
          _pollDownloads();
        },
        icon: Icon(paused ? Icons.play_arrow : Icons.pause),
        tooltip: paused ? '继续' : '暂停',
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          await widget.state.api.postJson('/api/local/download/cancel', {'id': id});
          _pollDownloads();
        },
        icon: const Icon(Icons.close),
        tooltip: '取消',
      ),
    ]);
  }

  Widget _tag(String text, Color bg) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, color: cs.onSurface)),
    );
  }

  String _sizeLabel(s) =>
      {'small': '轻量', 'medium': '中型', 'large': '重型'}[s] ?? s.toString();
  String _capLabel(s) =>
      {'text': '文本', 'vision': '识图', 'image': '生图', 'video': '生视频'}[s] ??
      s.toString();

  Future<void> _startDownload(Map<String, dynamic> m) async {
    try {
      final r = await widget.state.api.localDownloadStart(m['id'] as String);
      if (r['status'] == 'error' && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('下载失败: ${r['error']}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('启动下载失败: $e')));
      }
    }
  }

  Widget _downloadedTab() {
    final cs = Theme.of(context).colorScheme;
    return _local.isEmpty
        ? Center(
            child: Text('还没有本地模型，去模型市场下载一个吧',
                style: TextStyle(color: cs.onSurfaceVariant)))
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            itemCount: _local.length,
            itemBuilder: (_, i) {
              final m = _local[i] as Map<String, dynamic>;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(Icons.memory, color: cs.primary),
                  title: Text(m['name'] as String),
                  subtitle: Text('${m['size_mb']} MB · 可直接对话'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      await widget.state.api.localDelete(m['path'] as String);
                      await _refresh();
                    },
                  ),
                ),
              );
            },
          );
  }
}
