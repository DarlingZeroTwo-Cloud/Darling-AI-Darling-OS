import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'bridge.dart';
import 'dialogs/model_picker.dart';

/// 渲染消息种类
enum MsgKind { user, ai, tool, error, think }

/// 一条渲染消息
class ChatMsg {
  MsgKind kind;
  String text;
  String title;
  bool ok;
  double ts;
  ChatMsg(this.kind, this.text, {this.title = '', this.ok = true, this.ts = 0});
}

class AppState extends ChangeNotifier {
  final BridgeClient api;

  AppState(this.api);

  Map<String, dynamic> config = {};
  List<dynamic> providers = [];
  List<dynamic> models = [];
  Map<String, dynamic> settings = {};
  List<dynamic> conversations = [];
  String? activeConvId;
  String? currentModelId;

  /// 当前活动对话的标题（导出文件名用）
  String get activeConvTitle {
    if (activeConvId == null) return '对话';
    for (final c in conversations) {
      if (c is Map && c['id'] == activeConvId) {
        return (c['title'] ?? '对话').toString();
      }
    }
    return '对话';
  }

  List<ChatMsg> messages = [];
  bool busy = false;
  String thinkingText = '';
  bool askPending = false;
  /// 待填入输入框的编辑草稿（编辑消息后重发）
  String editDraft = '';
  String askCmd = '';
  int _seq = 0;

  ThemeMode get themeMode {
    final m = settings['theme_mode'];
    if (m == 'light') return ThemeMode.light;
    if (m == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  /// UI 模式：compact=精简（当前样式），classic=经典（Zed 风格侧边栏 + 独立窗口）
  String get uiMode => (settings['ui_mode'] ?? 'compact').toString();

  /// 当前应用版本号
  String get appVersion => '4.1.5';

  // ---------------- 4.0 云端账号 ----------------
  // 双地址：先 https，握手失败自动切 http
  static const List<String> kCloudBases = [
    'https://api.darling02.de5.net',
    'http://api.darling02.de5.net',
  ];
  String get cloudServer => kCloudBases.first;

  // 桌面应用：自定义域名证书可能不被 BoringSSL 信任，直接放行
  HttpClient _makeClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => true;
  String get cloudToken => (settings['cloud_token'] ?? '').toString();
  String get cloudEmail => (settings['cloud_email'] ?? '').toString();
  bool get cloudLoggedIn => cloudToken.isNotEmpty && cloudServer.isNotEmpty;
  Map<String, dynamic> cloudQuota = {};
  List<dynamic> cloudModels = [];

  Future<void> setCloudServer(String v) async {
    settings['cloud_server'] = v.trim().replaceAll(RegExp(r'/+$'), '');
    await saveSettings();
    notifyListeners();
  }

  Future<void> setCloudAuth({required String token, required String email, String refresh = ''}) async {
    settings['cloud_token'] = token;
    settings['cloud_email'] = email;
    if (refresh.isNotEmpty) settings['cloud_refresh'] = refresh;
    await saveSettings();
    notifyListeners();
  }

  String get cloudRefresh => (settings['cloud_refresh'] ?? '').toString();

  Future<void> cloudLogout() async {
    settings['cloud_token'] = '';
    settings['cloud_email'] = '';
    settings['cloud_refresh'] = '';
    cloudQuota = {};
    cloudModels = [];
    await saveSettings();
    notifyListeners();
  }

  /// 调云端接口
  Future<Map<String, dynamic>> cloudGet(String path) async {
    Object? lastErr;
    for (final base in kCloudBases) {
      final uri = Uri.parse('$base$path');
      final client = _makeClient();
      try {
        final req = await client.getUrl(uri);
        req.headers.set('Authorization', 'Bearer $cloudToken');
        final resp = await req.close().timeout(const Duration(seconds: 20));
        final body = await resp.transform(utf8.decoder).join();
        // 不是 JSON（HTML 错误页）就切下一个 base
        final trimmed = body.trim();
        if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
          final snippet = trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed;
          throw Exception('HTTP ${resp.statusCode}: $snippet');
        }
        return {'status': resp.statusCode, 'data': jsonDecode(body)};
      } catch (e) {
        lastErr = e;
        continue;
      } finally {
        client.close(force: true);
      }
    }
    throw lastErr ?? Exception('cloud get failed');
  }

  Future<Map<String, dynamic>> cloudPost(String path, Map<String, dynamic> body) async {
    Object? lastErr;
    for (final base in kCloudBases) {
      final uri = Uri.parse('$base$path');
      final client = _makeClient();
      try {
        final req = await client.postUrl(uri);
        req.headers.set('Content-Type', 'application/json; charset=utf-8');
        if (cloudToken.isNotEmpty) {
          req.headers.set('Authorization', 'Bearer $cloudToken');
        }
        req.add(utf8.encode(jsonEncode(body)));
        final resp = await req.close().timeout(const Duration(seconds: 120));
        final raw = await resp.transform(utf8.decoder).join();
        // 非 JSON 响应（HTML 错误页）切下一个 base
        final trimmed = raw.trim();
        if (!trimmed.startsWith('{') && !trimmed.startsWith('[') && !trimmed.startsWith('data:')) {
          final snippet = trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed;
          throw Exception('HTTP ${resp.statusCode}: $snippet');
        }
        // SSE 流（/api/chat）：解析所有 data: 行，拼 delta
        final ctype = resp.headers.contentType?.toString() ?? '';
        if (ctype.contains('text/event-stream') || raw.contains('data: ')) {
          String content = '';
          Map<String, dynamic>? usage;
          for (final line in raw.split('\n')) {
            final t = line.trim();
            if (!t.startsWith('data:')) continue;
            final payload = t.substring(5).trim();
            if (payload.isEmpty) continue;
            try {
              final j = jsonDecode(payload) as Map<String, dynamic>;
              if (j['type'] == 'delta') {
                content += (j['content'] ?? '').toString();
              } else if (j['type'] == 'done') {
                usage = (j['usage'] as Map?)?.cast<String, dynamic>();
              }
            } catch (_) {}
          }
          return {
            'status': resp.statusCode,
            'data': {'content': content, if (usage != null) 'usage': usage},
          };
        }
        return {'status': resp.statusCode, 'data': jsonDecode(raw)};
      } catch (e) {
        lastErr = e;
        continue;
      } finally {
        client.close(force: true);
      }
    }
    throw lastErr ?? Exception('cloud post failed');
  }

  /// 拉云端用户信息（额度）+ 模型列表
  Future<void> refreshCloud() async {
    if (!cloudLoggedIn) return;
    try {
      final me = await cloudGet('/api/me');
      if (me['status'] == 200) cloudQuota = (me['data']['quota'] as Map).cast<String, dynamic>();
      final ms = await cloudGet('/api/models');
      if (ms['status'] == 200) cloudModels = (ms['data']['models'] as List);
      notifyListeners();
    } catch (_) {}
  }

  /// 判断某模型 ID 是否为云端官方模型（slug 在 cloudModels 列表里）
  bool isCloudModel(String? id) {
    if (id == null) return false;
    return cloudModels.any((m) =>
        (m is Map && (m['id']?.toString() == id || m['slug']?.toString() == id)));
  }

  /// AI 优化提示词：把输入改写为更结构化提示词（云端/本地双模式，不依赖桥接 job）
  Future<String?> optimizePrompt(String text) async {
    if (text.trim().isEmpty || busy) return null;
    final prompt =
        '请把下面的用户输入改写成一个更清晰、结构化的提示词（保持原意，不要执行任务本身），只输出改写结果：\n\n$text';
    if (cloudLoggedIn && isCloudModel(currentModelId)) {
      try {
        final r = await cloudPost('/api/chat', {
          'model_id': currentModelId,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        });
        if (r['status'] == 200) {
          return (r['data']['content'] ?? '').toString().trim();
        }
      } catch (_) {}
      return null;
    }
    final m = model(currentModelId);
    if (m == null) return null;
    final sb = StringBuffer();
    try {
      await api.chat(m['id'] as String, prompt, (ev) {
        if (ev['type'] == 'token') sb.write(ev['text'] ?? '');
      });
    } catch (_) {
      return null;
    }
    final out = sb.toString().trim();
    return out.isEmpty ? null : out;
  }

  Future<void> setUiMode(String mode) async {
    settings['ui_mode'] = mode;
    await saveSettings();
    notifyListeners();
  }

  Map<String, dynamic>? model(String? id) {
    if (id == null) return null;
    for (final m in models) {
      if (m['id'] == id) return m as Map<String, dynamic>;
    }
    return null;
  }

  Map<String, dynamic>? provider(String? id) {
    if (id == null) return null;
    for (final p in providers) {
      if (p['id'] == id) return p as Map<String, dynamic>;
    }
    return null;
  }

  Map<String, dynamic>? activeConversation() {
    for (final c in conversations) {
      if (c['id'] == activeConvId) return c as Map<String, dynamic>;
    }
    return null;
  }

  // ---------------- 初始化 ----------------
  Future<void> load() async {
    config = await api.getJson('/api/config');
    providers = (config['providers'] is List ? config['providers'] as List : []);
    models = (config['models'] is List ? config['models'] as List : []);
    settings = ((config['settings'] ?? {}) as Map).cast<String, dynamic>();
    conversations = (config['conversations'] is List ? config['conversations'] as List : []);
    activeConvId = config['active_conv'] as String?;

    // 默认模型：活动会话记录的模型，否则第一个
    final conv = activeConversation();
    currentModelId = conv?['model_id'] as String?;
    if (currentModelId == null && models.isNotEmpty) {
      currentModelId = models.first['id'] as String;
    }
    _renderFromHist();
    notifyListeners();
  }

  Future<void> reload() async {
    config = await api.getJson('/api/config');
    providers = (config['providers'] is List ? config['providers'] as List : []);
    models = (config['models'] is List ? config['models'] as List : []);
    settings = ((config['settings'] ?? {}) as Map).cast<String, dynamic>();
    conversations = (config['conversations'] is List ? config['conversations'] as List : []);
    activeConvId = config['active_conv'] as String?;
    notifyListeners();
  }

  // ---------------- 会话 ----------------
  Future<void> newConversation() async {
    if (busy) return;
    final r = await api.postJson('/api/convo/new', {'model_id': currentModelId});
    await reload();
    activeConvId = r['conv_id'] as String?;
    messages = [];
    notifyListeners();
  }

  Future<void> loadConversation(String convId) async {
    if (busy) return;
    final r = await api.postJson('/api/convo/load', {'conv_id': convId});
    await reload();
    activeConvId = convId;
    currentModelId = (r['model_id'] as String?) ?? currentModelId;
    if (currentModelId == null && models.isNotEmpty) {
      currentModelId = models.first['id'] as String;
    }
    _renderFromHist(r['hist'] as List?);
    notifyListeners();
  }

  Future<void> deleteConversation(String convId) async {
    try {
      await api.postJson('/api/convo/delete', {'conv_id': convId});
    } catch (_) {}
    if (activeConvId == convId) {
      activeConvId = null;
      messages = [];
    }
    await reload();
    _renderFromHist();
    notifyListeners();
  }

  Future<void> confirmDeleteConversation(BuildContext context, String convId, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text('确定删除"${title.isEmpty ? '新对话' : title}"？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await deleteConversation(convId);
    }
  }

  /// 切换对话置顶（持久化到后端 + 本地同步）
  Future<void> togglePinConversation(String convId) async {
    var newVal = false;
    for (final c in conversations) {
      if (c is Map && c['id'] == convId) {
        newVal = !(c['pinned'] == true);
        c['pinned'] = newVal;
        break;
      }
    }
    notifyListeners();
    await api.setConversationPin(convId);
  }

  void setModel(String? modelId) {
    if (modelId == null) return;
    currentModelId = modelId;
    // 持久化到当前会话
    final cid = activeConvId;
    if (cid != null) {
      api.setConversationModel(cid, modelId);
    }
    notifyListeners();
  }

  /// 编辑消息：把文本填入输入框待修改后重发
  void editMessage(String text) {
    editDraft = text;
    notifyListeners();
  }

  /// 重新生成：取最后一条用户消息重发
  Future<void> regenerate() {
    String? lastUser;
    for (final m in messages) {
      if (m.kind == MsgKind.user) lastUser = m.text;
    }
    if (lastUser == null || lastUser.trim().isEmpty) return Future.value();
    return send(lastUser);
  }

  /// 停止当前生成
  Future<void> stop() async {
    final jobId = _jobId;
    if (jobId == null) return;
    await api.chatStop(jobId);
  }

  /// 重命名任意对话（对话框输入）
  Future<void> renameActiveConversationFor(
      BuildContext context, String convId, String curTitle) async {
    final ctl = TextEditingController(text: curTitle);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新名称'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await api.renameConversation(convId, name);
      await reload();
      notifyListeners();
    }
  }

  /// 重命名当前对话（对话框输入）
  Future<void> renameActiveConversation(BuildContext context) async {
    final cid = activeConvId;
    if (cid == null) return;
    final cur = activeConversation()?['title'] ?? '新对话';
    await renameActiveConversationFor(context, cid, cur.toString());
  }

  /// 清空当前对话历史
  Future<void> clearActiveConversation() async {
    final cid = activeConvId;
    if (cid == null) return;
    await api.postJson('/api/convo/clear', {'conv_id': cid});
    await reload();
    messages = [];
    notifyListeners();
  }

  /// 模型切换弹窗（斜杠命令 /model 用）
  Future<void> switchModelDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换模型'),
        content: SizedBox(
          width: 420,
          height: 430,
          child: ModelPickerPanel(state: this, onClose: () => Navigator.pop(ctx)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 导出当前对话为文件。format: 'md' / 'json' / 'html'。
  /// 返回成功时的文件路径，失败返回 null（错误信息通过抛异常由调用方捕获）。
  Future<String?> exportConversation({String format = 'md'}) async {
    if (messages.isEmpty) return null;
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final dir = '$home/Documents';
    if (!Directory(dir).existsSync()) {
      Directory(dir).createSync(recursive: true);
    }
    final ts = DateTime.now();
    final stamp =
        '${ts.year}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}-'
        '${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}';
    // 文件名带当前对话标题（不含非法字符）
    String safeTitle(String s) =>
        s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    final convTitle = safeTitle(
        (activeConvTitle ?? '对话').toString());
    final base = 'darling-ai-$convTitle-$stamp';
    if (format == 'json') {
      final items = messages.where((m) =>
          m.kind == MsgKind.user ||
          m.kind == MsgKind.ai ||
          m.kind == MsgKind.tool).map((m) {
        final role = switch (m.kind) {
          MsgKind.user => 'user',
          MsgKind.ai => 'assistant',
          _ => 'tool',
        };
        return {'role': role, 'content': m.text};
      }).toList();
      final payload = {
        'app': 'darling-ai',
        'version': '3.3.8',
        'exported_at': ts.toIso8601String(),
        'model_id': currentModelId,
        'messages': items,
      };
      final file = File('$dir/$base.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
      return file.path;
    }
    if (format == 'html') {
      String esc(String s) => s
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;');
      final buf = StringBuffer();
      buf.writeln('<!DOCTYPE html>');
      buf.writeln('<html lang="zh-CN"><head><meta charset="utf-8">');
      buf.writeln('<meta name="viewport" content="width=device-width, initial-scale=1">');
      buf.writeln('<title>darling-ai 对话导出</title>');
      buf.writeln('<style>');
      buf.writeln('body{font-family:-apple-system,"Segoe UI","Microsoft YaHei",sans-serif;');
      buf.writeln('max-width:860px;margin:0 auto;padding:24px 16px 48px;color:#24292f;background:#fff}');
      buf.writeln('h1{font-size:20px;margin:0 0 4px}');
      buf.writeln('.meta{font-size:12px;color:#888;margin-bottom:24px}');
      buf.writeln('.msg{margin:12px 0;padding:12px 14px;border-radius:10px;line-height:1.6;font-size:14px;white-space:pre-wrap;word-break:break-word}');
      buf.writeln('.user{background:#e8f4fd;border:1px solid #d0e8f8}');
      buf.writeln('.ai{background:#f2f4f7;border:1px solid #e4e7ec}');
      buf.writeln('.tool{background:#fbf3e6;border:1px solid #f2e2c0;font-size:12.5px}');
      buf.writeln('.role{font-size:12px;font-weight:600;margin-bottom:6px;color:#57606a}');
      buf.writeln('pre{background:#0d1117;color:#e6edf3;padding:10px 12px;border-radius:8px;overflow-x:auto;font-size:12.5px}');
      buf.writeln('code{font-family:"SF Mono",Consolas,"Courier New",monospace}');
      buf.writeln('</style></head><body>');
      buf.writeln('<h1>darling-ai 对话导出</h1>');
      buf.writeln('<div class="meta">模型：${esc(currentModelId ?? '未知')} · 导出时间：${ts.toIso8601String()}</div>');
      for (final m in messages) {
        final body = esc(m.text).replaceAll('\n', '<br>');
        switch (m.kind) {
          case MsgKind.user:
            buf.writeln('<div class="msg user"><div class="role">👤 用户</div>$body</div>');
            break;
          case MsgKind.ai:
            buf.writeln('<div class="msg ai"><div class="role">🤖 AI</div>$body</div>');
            break;
          case MsgKind.tool:
            buf.writeln('<div class="msg tool"><div class="role">🛠️ ${esc(m.title ?? '')}</div>$body</div>');
            break;
          default:
            break;
        }
      }
      buf.writeln('</body></html>');
      final file = File('$dir/$base.html');
      await file.writeAsString(buf.toString());
      return file.path;
    }
    final buf = StringBuffer();
    buf.writeln('# 对话导出');
    buf.writeln();
    for (final m in messages) {
      switch (m.kind) {
        case MsgKind.user:
          buf.writeln('## 👤 用户\n\n${m.text}\n');
          break;
        case MsgKind.ai:
          buf.writeln('## 🤖 AI\n\n${m.text}\n');
          break;
        case MsgKind.tool:
          buf.writeln('### 🛠️ ${m.title}\n\n${m.text}\n');
          break;
        default:
          break;
      }
    }
    final file = File('$dir/$base.md');
    await file.writeAsString(buf.toString());
    return file.path;
  }

  /// 把当前对话拼成 Markdown 文本（用于复制到剪贴板）
  String conversationToMarkdown() {
    final buf = StringBuffer();
    buf.writeln('# 对话导出');
    buf.writeln();
    for (final m in messages) {
      switch (m.kind) {
        case MsgKind.user:
          buf.writeln('## 用户\n\n${m.text}\n');
          break;
        case MsgKind.ai:
          buf.writeln('## AI\n\n${m.text}\n');
          break;
        case MsgKind.tool:
          buf.writeln('### ${m.title}\n\n${m.text}\n');
          break;
        default:
          break;
      }
    }
    return buf.toString().trimRight();
  }

  /// 删除一个模型（保存配置；若删的是当前模型则回退到第一个）
  Future<void> deleteModel(String modelId) async {
    models.removeWhere((m) => m['id'] == modelId);
    if (currentModelId == modelId) {
      currentModelId = models.isNotEmpty ? models.first['id'] as String? : null;
    }
    await saveProvidersModels();
    notifyListeners();
  }

  // ---------------- 渲染 ----------------
  void _renderFromHist([List? hist]) {
    messages = [];
    final h = hist ?? (activeConversation()?['hist'] as List? ?? []);
    if (h.isEmpty) return; // 空历史就保持空，走空状态 logo
    for (final raw in h) {
      final msg = raw as Map<String, dynamic>;
      final role = msg['role'];
      final content = (msg['content'] ?? '').toString();
      if (role == 'system') continue;
      if (content.startsWith('[命令执行结果]')) {
        final p = _parseNote(content);
        messages.add(ChatMsg(MsgKind.tool, p['out'] ?? '',
            title: '执行命令 · ${p['cmd']}', ok: !content.contains('失败')));
        continue;
      }
      if (content.startsWith('[插件执行结果]')) {
        final p = _parseNote(content);
        messages.add(ChatMsg(MsgKind.tool, p['out'] ?? '',
            title: '插件 · ${p['plugin']}/${p['tool']}', ok: !content.contains('失败')));
        continue;
      }
      if (content.startsWith('[插件调用失败]') ||
          content.startsWith('用户取消了') ||
          content.startsWith('用户没有回应')) {
        messages.add(ChatMsg(MsgKind.tool, content, ok: false));
        continue;
      }
      messages.add(ChatMsg(role == 'user' ? MsgKind.user : MsgKind.ai, content,
          ts: (msg['ts'] is num ? msg['ts'] as num : 0).toDouble()));
    }
  }

  Map<String, String> _parseNote(String content) {
    final out = <String, String>{};
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.startsWith('命令: ')) out['cmd'] = l.substring(4);
      if (l.startsWith('插件: ')) out['plugin'] = l.substring(4);
      if (l.startsWith('工具: ')) out['tool'] = l.substring(4);
      if (l.startsWith('输出: ')) out['out'] = lines.sublist(i + 1).join('\n');
      if (l.startsWith('结果: ')) out['out'] = lines.sublist(i + 1).join('\n');
    }
    return out;
  }

  // ---------------- 对话 ----------------
  Future<void> send(String text) => _send(text, const [], const []);

  /// 带联网搜索结果的发送
  Future<void> sendWithWeb(String text, List<Map<String, dynamic>> webResults) =>
      _send(text, webResults, const []);

  /// 带图片的发送
  Future<void> sendWithImages(String text, List<String> images) =>
      _send(text, const [], images);

  Future<void> _send(
      String text, List<Map<String, dynamic>> webResults, List<String> images) async {
    // 4.0 云端官方模型：走云端网关，不经过本地桥接
    if (isCloudModel(currentModelId)) {
      if (busy || text.trim().isEmpty) return;
      if (!cloudLoggedIn) {
        messages.add(ChatMsg(MsgKind.error, '请先到 设置 → 账号 登录后使用官方模型'));
        notifyListeners();
        return;
      }
      busy = true;
      thinkingText = '正在连接官方模型…';
      messages.add(ChatMsg(MsgKind.user, text, ts: DateTime.now().millisecondsSinceEpoch / 1000.0));
      messages.add(ChatMsg(MsgKind.ai, ''));
      notifyListeners();
      try {
        final hist = messages
            .where((e) =>
                (e.kind == MsgKind.user || e.kind == MsgKind.ai) && e.text.isNotEmpty)
            .map((e) => {
                  'role': e.kind == MsgKind.user ? 'user' : 'assistant',
                  'content': e.text,
                })
            .toList();
        final r = await cloudPost('/api/chat', {
          'model_id': currentModelId,
          'messages': hist,
        });
        thinkingText = '';
        if (r['status'] == 200) {
          messages.last.text = (r['data']['content'] ?? '').toString();
        } else {
          messages.last.kind = MsgKind.error;
          messages.last.text = (r['data']['error'] ?? '请求失败').toString();
        }
        await refreshCloud();
      } catch (e) {
        messages.last.kind = MsgKind.error;
        messages.last.text = '网络错误：$e';
      } finally {
        busy = false;
        notifyListeners();
      }
      return;
    }
    final m = model(currentModelId);
    if (m == null || busy || text.trim().isEmpty) return;
    busy = true;
    askPending = false;
    thinkingText = '正在连接服务器…';
    _seq = 0;
    String? jobId;
    messages.add(ChatMsg(MsgKind.user, text, ts: DateTime.now().millisecondsSinceEpoch / 1000.0));
    notifyListeners();

    try {
      await api.chat(m['id'] as String, text, (ev) {
        switch (ev['type']) {
          case 'state':
            thinkingText = (ev['text'] ?? '').toString();
            break;
          case 'token':
            if (messages.isEmpty || messages.last.kind != MsgKind.ai) {
              messages.add(ChatMsg(MsgKind.ai, ''));
            }
            messages.last.text += (ev['text'] ?? '').toString();
            break;
          case 'tool':
            final t = (ev['title'] ?? '').toString();
            final c = (ev['content'] ?? '').toString();
            final ok = ev['ok'] == true;
            if (c.isNotEmpty) {
              messages.add(ChatMsg(MsgKind.tool, c, title: t, ok: ok));
            }
            break;
          case 'ask':
            askPending = true;
            askCmd = (ev['cmd'] ?? '').toString();
            break;
          case 'error':
            final e = (ev['text'] ?? '').toString();
            messages.add(ChatMsg(MsgKind.error, e));
            break;
        }
        notifyListeners();
      }, onJob: (id) {
        jobId = id;
        _jobId = id;
      }, webResults: webResults, images: images);
      // 完成：恢复默认 thinking（无流时占位）
      if (messages.isEmpty || messages.last.kind != MsgKind.ai) {
        messages.add(ChatMsg(MsgKind.think, ''));
      }
      thinkingText = '';
      await reload();
      // 同步活动会话标题到列表
      notifyListeners();
    } catch (e) {
      messages.add(ChatMsg(MsgKind.error, '对话中断：$e'));
    } finally {
      busy = false;
      askPending = false;
      thinkingText = '';
      notifyListeners();
    }
  }

  Future<void> answerAsk(bool allow) async {
    final jobId = _jobId;
    askPending = false;
    notifyListeners();
    if (jobId != null) {
      try {
        await api.postJson('/api/decision', {'job': jobId, 'allow': allow});
      } catch (_) {}
    }
  }

  String? _jobId;

  // ---------------- 设置 ----------------
  /// 恢复默认设置（后端重置 settings，保留服务监听配置）
  Future<void> restoreDefaultSettings() async {
    await api.postJson('/api/settings/reset', {});
    await reload();
    notifyListeners();
  }

  Future<void> saveSettings() async {
    await api.postJson('/api/config', {'settings': settings});
    await reload();
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    settings['theme_mode'] = mode;
    await saveSettings();
    notifyListeners();
  }

  /// 切换助手角色预设
  Future<void> setAssistantRole(String role) async {
    settings['assistant_role'] = role;
    await saveSettings();
    notifyListeners();
  }

  Future<void> saveProvidersModels() async {
    await api.postJson('/api/config', {
      'providers': providers,
      'models': models,
    });
    await reload();
    notifyListeners();
  }
}
