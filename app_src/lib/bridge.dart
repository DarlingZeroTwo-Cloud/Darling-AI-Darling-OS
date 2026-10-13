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
  }) async {
    final start = await postJson('/api/chat', {'model_id': modelId, 'text': text});
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
            onEvent(ev);
          } catch (_) {}
        }
        if (done) return;
        // 流结束但没收到 DONE → 断线，尝试重连
        if (reconnects >= maxReconnects) return;
        reconnects++;
        onEvent({'type': 'state', 'text': '连接中断，正在重连 ($reconnects/$maxReconnects)…'});
        await Future.delayed(const Duration(seconds: 1));
      } catch (_) {
        if (reconnects >= maxReconnects) rethrow;
        reconnects++;
        onEvent({'type': 'state', 'text': '连接中断，正在重连 ($reconnects/$maxReconnects)…'});
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  void dispose() => _client.close();

  // ===== 本地模型 / 模型市场 =====
  Future<List<dynamic>> localCatalog() async =>
      (await getJson('/api/local/catalog'))['models'] as List<dynamic>;

  Future<List<dynamic>> localList() async =>
      (await getJson('/api/local/list'))['models'] as List<dynamic>;

  Future<Map<String, dynamic>> localGpu() => getJson('/api/local/gpu');

  Future<Map<String, dynamic>> localDownloadStart(String catalogId) =>
      postJson('/api/local/download/start', {'catalog_id': catalogId});

  Future<Map<String, dynamic>> localDownloadStatus(String id) =>
      getJson('/api/local/download/status?id=$id');

  Future<Map<String, dynamic>> localDownloadsAll() =>
      getJson('/api/local/download/status');

  Future<bool> localDelete(String path) async {
    final r = await postJson('/api/local/delete', {'path': path});
    return r['ok'] == true;
  }

  Future<bool> deleteProvider(String providerId) async {
    final r = await postJson('/api/provider/delete', {'provider_id': providerId});
    return r['ok'] == true;
  }
}
