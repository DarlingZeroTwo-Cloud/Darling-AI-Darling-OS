import 'dart:async';
import 'dart:io';

/// 屏幕读取：grim 截图 + tesseract OCR（Darling OS / Hyprland 专属）
class ScreenReader {
  /// 截取当前屏幕并识别文字，返回 (文本, 截图路径)
  static Future<Map<String, String>> captureText() async {
    final shot = '${Directory.systemTemp.path}/darling-ai-shot-${DateTime.now().millisecondsSinceEpoch}.png';
    final ocrOut = '${Directory.systemTemp.path}/darling-ai-ocr-${DateTime.now().millisecondsSinceEpoch}';
    try {
      // 1. grim 截全屏
      final grim = await Process.run('grim', [shot]).timeout(const Duration(seconds: 10));
      if (grim.exitCode != 0 || !File(shot).existsSync()) {
        return {'text': '', 'image': '', 'error': 'grim 截图失败：${grim.stderr}'};
      }
      // 2. tesseract OCR（中英）
      final t = await Process.run('tesseract', [shot, ocrOut, '-l', 'chi_sim+eng'])
          .timeout(const Duration(seconds: 30));
      final txtFile = File('$ocrOut.txt');
      final text = t.exitCode == 0 && txtFile.existsSync()
          ? txtFile.readAsStringSync().trim()
          : '';
      return {'text': text, 'image': shot, 'error': ''};
    } catch (e) {
      return {'text': '', 'image': '', 'error': '读屏失败：$e'};
    }
  }
}
