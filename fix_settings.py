# -*- coding: utf-8 -*-
import re

p = '/home/user/Doubao/chats/38445728458548482/repo-tmp/app_src/lib/pages/settings_page.dart'
src = open(p, encoding='utf-8').read()

# 1) 在类顶部加安全 helper（插到 _SettingsPageState 之前）
helper = '''
// 安全读取数值：settings 来自后端 JSON，旧版本可能存了字符串/非法类型
num _num(Map<String, dynamic> s, String key, num def) {
  final v = s[key];
  return (v is num) ? v : def;
}

int _int(Map<String, dynamic> s, String key, int def) {
  final v = s[key];
  return (v is int) ? v : def;
}

// 安全读取枚举值：不在合法集合内时回退默认
String _opt(Map<String, dynamic> s, String key, String def, Set<String> valid) {
  final v = s[key];
  return (v is String && valid.contains(v)) ? v : def;
}
'''

anchor = 'class _SettingsPageState extends State<SettingsPage> {'
assert anchor in src, 'anchor not found'
src = src.replace(anchor, helper + '\n' + anchor, 1)

# 2) 替换所有 (s['xxx'] as num? ?? def) -> _num(...)
src = re.sub(r"\(s\['(\w+)'\] as num\? \?\? ([0-9.]+)\)",
             lambda m: "_num(s, '%s', %s)" % (m.group(1), m.group(2)), src)

# 3) 替换 (s['xxx'] as int? ?? 0xFFxxxx) -> _int(...)
src = re.sub(r"\(s\['(\w+)'\] as int\? \?\? (0x[0-9A-Fa-f]+)\)",
             lambda m: "_int(s, '%s', %s)" % (m.group(1), m.group(2)), src)

# 4) _TempSlider: (state.settings['temperature'] as num? ?? 0.7)
src = src.replace("(state.settings['temperature'] as num? ?? 0.7)",
                  "_num(state.settings, 'temperature', 0.7)")

# 5) SegmentedButton selected 越界保护
src = src.replace("selected: {s['websearch_engine'] ?? 'duckduckgo'}",
                  "selected: {_opt(s, 'websearch_engine', 'duckduckgo', const {'duckduckgo', 'tavily'})}")
src = src.replace("selected: {s['container_type'] ?? 'auto'}",
                  "selected: {_opt(s, 'container_type', 'auto', const {'auto', 'wsl', 'docker'})}")
src = src.replace("selected: {s['local_gpu'] ?? 'auto'}",
                  "selected: {_opt(s, 'local_gpu', 'auto', const {'auto', 'cpu', 'vulkan'})}")
src = src.replace("selected: {s['theme_mode'] ?? 'system'}",
                  "selected: {_opt(s, 'theme_mode', 'system', const {'system', 'light', 'dark'})}")

# 6) _RolePicker value 越界保护
old_role = """    final cur = state.settings['assistant_role']?.toString() ?? 'general';
    return DropdownButton<String>(
      value: cur,"""
new_role = """    final raw = state.settings['assistant_role']?.toString() ?? 'general';
    final cur = roles.any((r) => r.$1 == raw) ? raw : 'general';
    return DropdownButton<String>(
      value: cur,"""
assert old_role in src, 'role picker block not found'
src = src.replace(old_role, new_role, 1)

# 7) _ContainerDetectCard distros 安全读取
old_det = """                      Text(
                        info!['platform'] == 'windows'
                            ? (info['wsl_installed'] == true
                                ? '已检测到 WSL，发行版：${(info['distros'] as List).join('、')}'
                                : '未检测到 WSL（可到微软商店安装）')"""
new_det = """                      Text(
                        (info?['distros'] is List
                            ? (info!['platform'] == 'windows'
                                ? (info['wsl_installed'] == true
                                    ? '已检测到 WSL，发行版：${(info['distros'] as List).join('、')}'
                                    : '未检测到 WSL（可到微软商店安装）')
                                : (info['docker_installed'] == true
                                    ? '已检测到 Docker${info['docker_running'] == true ? '（运行中）' : '（未运行）'}'
                                    : '未检测到 Docker'))
                            : '尚未检测容器环境')"""
assert old_det in src, 'container detect block not found'
src = src.replace(old_det, new_det, 1)

# 8) 关于页版本号：3.0.14 -> 3.1.7
src = src.replace("Text('版本 3.0.14', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))",
                  "Text('版本 3.1.7', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))")

open(p, 'w', encoding='utf-8').write(src)
print('OK, all replacements done')

# 校验：不应再有 as num? / as int? 残留
left = re.findall(r"as num\?|as int\?", src)
print('remaining as num/int casts:', left)
