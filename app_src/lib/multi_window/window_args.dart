import 'dart:convert';

/// 窗口类型：主窗口 / 悬浮球 / 悬浮对话窗
enum WinKind { main, ball, panel }

/// 窗口参数（通过 desktop_multi_window 的 arguments 字符串传递）
class WinArgs {
  final WinKind kind;
  const WinArgs(this.kind);

  String encode() => jsonEncode({'k': kind.name});

  static WinArgs parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const WinArgs(WinKind.main);
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final k = (j['k'] ?? 'main').toString();
      for (final v in WinKind.values) {
        if (v.name == k) return WinArgs(v);
      }
    } catch (_) {}
    return const WinArgs(WinKind.main);
  }
}
