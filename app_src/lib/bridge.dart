import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 桥接服务客户端：127.0.0.1:19730
/// REST + SSE 流式对话。
class BridgeClient {
  static const String host = '127.0.0.1';
  static const int port = 19730;
  static const String base = 'http://$host:$port';
  final http.Client _client = http.Client();

  /// 后端是否在线
  Future<bool> ping() async {
    try {
      final r = await _client
          .get(Uri.parse('$base/api/ping'))
          .timeout(const Duration(seconds: 3));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        return d['ok'] == true;
      }
    } catch (_) {}
    return false;
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final r = await _client
        .get(Uri.parse('$base$path'))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) {
      throw Exception('GET $path -> ${r.statusCode}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final r = await _client
        .post(Uri.parse('$base$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) {
      throw Exception('POST $path -> ${r.statusCode}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// 流式对话：POST /api/chat 拿 job，再 GET /api/stream 逐事件回调。
  /// SSE 断线自动重连（最多 3 次，每次间隔 1 秒）。
  Future<void> chat(
    String modelId,
    String text,
    void Function(Map<String, dynamic> event) onEvent, {
    void Function(String jobId)? onJob,
    List<Map<String, dynamic>> webResults = const [],
    List<String> images = const [],
  }) async {
    final start = await postJson('/api/chat', {
      'model_id': modelId,
      'text': text,
      if (webResults.isNotEmpty) 'web_results': webResults,
      if (images.isNotEmpty) 'images': images,
    });
    final job = start['job'] as String;
    onJob?.call(job);

    var reconnects = 0;
    const maxReconnects = 3;
    while (true) {
      try {
        final req = http.Request('GET', Uri.parse('$base/api/stream?job=$job'));
        final resp = await _client.send(req).timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          throw Exception('SSE 连接失败: ${resp.statusCode}');
        }
        var done = false;
        var gotTokens = false;
        final stream = resp.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in stream) {
          final s = line.trim();
          if (!s.startsWith('data: ')) continue;
          final payload = s.substring(6);
          if (payload == '[DONE]') {
            done = true;
            break;
          }
          try {
            final ev = jsonDecode(payload) as Map<String, dynamic>;
            if (ev['type'] == 'token') gotTokens = true;
            if (ev['type'] == 'done') done = true; // 后端完成事件
            onEvent(ev);
          } catch (_) {}
        }
        // 正常结束：收到 DONE / done 事件，或已经收到 token 后流自然关闭
        if (done || gotTokens) return;
        // 流关闭但没收到任何内容 → 真断线，重连
        if (reconnects >= maxReconnects) return;
        reconnects++;
        onEvent({'type': 'state', 'text': '连接中断，正在重连 ($reconnects/$maxReconnects)…'});
        await Future.delayed(const Duration(seconds: 1));
      } catch (_) {
        if (reconnects >= maxReconnects) return;
        reconnects++;
        onEvent({'type': 'state', 'text': '连接中断，正在重连 ($reconnects/$maxReconnects)…'});
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  /// 订阅已有 job 的 SSE 事件流（用于后台任务如 AI 优化提示词）
  Future<void> streamJob(
    String jobId,
    void Function(Map<String, dynamic> event) onEvent,
  ) async {
    try {
      final req = http.Request('GET', Uri.parse('$base/api/stream?job=$jobId'));
      final resp = await _client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return;
      final stream = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in stream) {
        final s = line.trim();
        if (!s.startsWith('data: ')) continue;
        final payload = s.substring(6);
        if (payload == '[DONE]') break;
        try {
          final ev = jsonDecode(payload) as Map<String, dynamic>;
          onEvent(ev);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void dispose() => _client.close();

  /// 停止当前任务生成
  Future<void> chatStop(String jobId) async {
    try {
      await postJson('/api/chat/stop', {'job': jobId});
    } catch (_) {}
  }

  /// 重命名对话
  Future<void> renameConversation(String convId, String title) async {
    try {
      await postJson('/api/convo/rename', {'conv_id': convId, 'title': title});
    } catch (_) {}
  }

  /// 保存对话所用模型
  Future<void> setConversationModel(String convId, String modelId) async {
    try {
      await postJson('/api/convo/model', {'conv_id': convId, 'model_id': modelId});
    } catch (_) {}
  }

  /// 联网搜索
  Future<Map<String, dynamic>> webSearch(String q) async {
    try {
      final enc = Uri.encodeQueryComponent(q);
      return await getJson('/api/websearch?q=$enc');
    } catch (_) {
      return {'results': <dynamic>[], 'engine': 'none'};
    }
  }

  /// 容器环境自动检测
  Future<Map<String, dynamic>> containerDetect() async {
    try {
      return await getJson('/api/container/detect');
    } catch (_) {
      return {
        'wsl_installed': false,
        'distros': <dynamic>[],
        'docker_installed': false,
        'docker_running': false,
        'platform': 'unknown'
      };
    }
  }

  // ===== 本地模型 / 模型市场 =====
  Future<List<dynamic>> localCatalog() async {
    final r = await getJson('/api/local/catalog');
    final m = r['models'];
    return m is List ? m : <dynamic>[];
  }

  Future<List<dynamic>> localList() async {
    final r = await getJson('/api/local/list');
    final m = r['models'];
    return m is List ? m : <dynamic>[];
  }

  Future<Map<String, dynamic>> localGpu() => getJson('/api/local/gpu');

  Future<Map<String, dynamic>> localDownloadStart(String catalogId) =>
      postJson('/api/local/download/start', {'catalog_id': catalogId});

  Future<Map<String, dynamic>> localDownloadStatus(String id) =>
      getJson('/api/local/download/status?id=$id');

  Future<Map<String, dynamic>> localDownloadsAll() =>
      getJson('/api/local/download/status');

  /// 后台加载本地模型（不阻塞，前端轮询状态显示进度）
  Future<Map<String, dynamic>> localWarmup(String path) =>
      postJson('/api/model/warmup', {'path': path});

  /// 本地模型加载状态：{"loading": [path...], "ready": [path...]}
  Future<Map<String, dynamic>> localStatus() =>
      getJson('/api/model/status');

  Future<bool> localDelete(String path) async {
    final r = await postJson('/api/local/delete', {'path': path});
    return r['ok'] == true;
  }

  Future<bool> deleteProvider(String providerId) async {
    final r = await postJson('/api/provider/delete', {'provider_id': providerId});
    return r['ok'] == true;
  }
}
