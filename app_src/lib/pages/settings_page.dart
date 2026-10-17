import 'dart:io';
import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';
import '../widgets/spin_field.dart';

class SettingsPage extends StatefulWidget {
  final AppState state;
  const SettingsPage({super.key, required this.state});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}


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

class _SettingsPageState extends State<SettingsPage> {
  int _nav = 0;

  static const _sections = [
    ('对话', Icons.chat_bubble_outline),
    ('网络', Icons.public),
    ('权限', Icons.shield_outlined),
    ('高级功能', Icons.auto_awesome),
    ('本地推理', Icons.memory),
    ('服务', Icons.dns_outlined),
    ('个性化', Icons.palette_outlined),
    ('关于', Icons.info_outline),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final state = widget.state;
        return SizedBox.expand(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 侧边栏导航
            Container(
              width: 180,
              margin: const EdgeInsets.fromLTRB(16, 20, 0, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Text('设置', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
                  ),
                  for (int i = 0; i < _sections.length; i++)
                    _NavItem(
                      icon: _sections[i].$2,
                      label: _sections[i].$1,
                      selected: _nav == i,
                      onTap: () => setState(() => _nav = i),
                    ),
                ],
              ),
            ),
            // 内容区 —— 按 _nav 显示对应页面
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 24, 24),
                child: _buildPage(state),
              ),
            ),
          ],
        ),
        );
      },
    );
  }

  Widget _buildPage(AppState state) {
    switch (_nav) {
      case 0: return _chatPage(state);
      case 1: return _networkPage(state);
      case 2: return _privacyPage(state);
      case 3: return _advancedPage(state);
      case 4: return _localPage(state);
      case 5: return _serverPage(state);
      case 6: return _appearancePage(state);
      case 7: return _aboutPage(state);
      default: return _chatPage(state);
    }
  }

  // ===== 对话 =====
  Widget _chatPage(AppState state) {
    final s = state.settings;
    return Column(children: [
      _Card(title: '对话', children: [
        _Row(label: '温度 temperature', desc: '控制回复随机性（0 ~ 2），默认 0.7。', trailing: _TempSlider(state: state)),
        _Row(label: '最大回复 tokens', desc: '单次回复长度上限。', trailing: SpinField(min: 256, max: 131072, value: _num(s, 'max_tokens', 4096).toDouble(), step: 512, onChanged: (v) { state.settings['max_tokens'] = v.toInt(); state.saveSettings(); })),
        _Row(label: '思考强度', desc: '控制 AI 思考深度（0=关闭, 3=最强）。', trailing: SpinField(min: 0, max: 3, value: _num(s, 'reasoning_effort', 1).toDouble(), step: 1, decimals: 0, onChanged: (v) { state.settings['reasoning_effort'] = v.toInt(); state.saveSettings(); })),
        _Row(label: '流式输出', desc: '逐字显示 AI 回复。', trailing: Switch(value: s['stream'] != false, onChanged: (v) { state.settings['stream'] = v; state.saveSettings(); })),
        _Row(label: '自动滚动到底部', desc: '新消息自动滚动到最新内容。', trailing: Switch(value: s['auto_scroll'] != false, onChanged: (v) { state.settings['auto_scroll'] = v; state.saveSettings(); })),
        _Row(label: '显示 token 用量', desc: '每条回复后显示消耗的 token 数。', trailing: Switch(value: s['show_tokens'] == true, onChanged: (v) { state.settings['show_tokens'] = v; state.saveSettings(); })),
        _Row(label: '消息时间戳', desc: '每条消息下方显示发送时间。', trailing: Switch(value: s['show_timestamp'] != false, onChanged: (v) { state.settings['show_timestamp'] = v; state.saveSettings(); })),
        _Row(label: '对话字体大小', desc: '聊天内容的字号（12 ~ 20）。', trailing: SpinField(min: 12, max: 20, value: _num(s, 'chat_font_size', 14).toDouble(), step: 1, decimals: 0, onChanged: (v) { state.settings['chat_font_size'] = v.toInt(); state.saveSettings(); })),
        _Row(label: '历史消息保留条数', desc: '发给 AI 的最近消息数（默认 20）。', trailing: SpinField(min: 4, max: 100, value: _num(s, 'history_limit', 20).toDouble(), step: 2, decimals: 0, onChanged: (v) { state.settings['history_limit'] = v.toInt(); state.saveSettings(); })),
        _Row(label: '自动压缩阈值', desc: '历史 token 超过此值时自动压缩（默认 60000）。', trailing: SpinField(min: 4000, max: 200000, value: _num(s, 'context_compress_threshold', 60000).toDouble(), step: 2000, onChanged: (v) { state.settings['context_compress_threshold'] = v.toInt(); state.saveSettings(); })),
        _Row(label: '助手角色', desc: '预设角色决定 AI 的行为风格；自定义角色可在下方编辑。', trailing: _RolePicker(state: state)),
        if ((s['assistant_role'] ?? 'general') == 'custom')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: TextEditingController(text: (s['assistant_role_custom'] ?? '').toString()),
              maxLines: 4,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '自定义角色系统提示词，例如：你是一位精通日语的旅行顾问…',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) { state.settings['assistant_role_custom'] = v; state.saveSettings(); },
            ),
          ),
      ]),
    ]);
  }

  // ===== 网络 =====
  Widget _networkPage(AppState state) {
    final s = state.settings;
    return Column(children: [
      _Card(title: '网络', children: [
        _Row(label: '连接超时（秒）', desc: '连不上时快速失败并重试。', trailing: SpinField(min: 3, max: 120, value: _num(s, 'connect_timeout', 15).toDouble(), step: 1, onChanged: (v) { state.settings['connect_timeout'] = v.toInt(); state.saveSettings(); })),
        _Row(label: 'API 失败重试次数', desc: '流式请求失败后的额外重试次数（0 ~ 5）。', trailing: SpinField(min: 0, max: 5, value: _num(s, 'api_retries', 1).toDouble(), step: 1, decimals: 0, onChanged: (v) { state.settings['api_retries'] = v.toInt(); state.saveSettings(); })),
        _Row(label: '使用系统代理', desc: '默认直连。需要走代理时再开启。', trailing: Switch(value: s['use_proxy'] == true, onChanged: (v) { state.settings['use_proxy'] = v; state.saveSettings(); })),
        _Row(label: 'SSE 断线重连次数', desc: '流式断开后自动重连次数（0 ~ 10）。', trailing: SpinField(min: 0, max: 10, value: _num(s, 'sse_reconnects', 3).toDouble(), step: 1, decimals: 0, onChanged: (v) { state.settings['sse_reconnects'] = v.toInt(); state.saveSettings(); })),
        _Row(label: '请求间隔（毫秒）', desc: '连续请求之间的等待，避免触发限流。', trailing: SpinField(min: 0, max: 5000, value: _num(s, 'request_delay_ms', 0).toDouble(), step: 100, onChanged: (v) { state.settings['request_delay_ms'] = v.toInt(); state.saveSettings(); })),
      ]),
      const SizedBox(height: 14),
      _Card(title: '联网搜索', children: [
        _Row(label: '搜索引擎', desc: 'DuckDuckGo 免费无需 Key；Tavily 更稳定需 API Key。', trailing: SegmentedButton<String>(segments: const [ButtonSegment(value: 'duckduckgo', label: Text('DuckDuckGo')), ButtonSegment(value: 'tavily', label: Text('Tavily'))], selected: {_opt(s, 'websearch_engine', 'duckduckgo', const {'duckduckgo', 'tavily'})}, onSelectionChanged: (sel) { state.settings['websearch_engine'] = sel.first; state.saveSettings(); })),
        _Row(label: 'Tavily API Key', desc: '选择 Tavily 时必填。', trailing: SizedBox(width: 260, child: TextField(controller: TextEditingController(text: (s['tavily_api_key'] ?? '').toString()), obscureText: true, decoration: const InputDecoration(isDense: true, hintText: 'tvly-...'), onSubmitted: (v) { state.settings['tavily_api_key'] = v.trim(); state.saveSettings(); }))),
      ]),
    ]);
  }

  // ===== 权限 =====
  Widget _privacyPage(AppState state) {
    final s = state.settings;
    return Column(children: [
      _Card(title: '权限与隐私', children: [
        _Row(label: '工作目录', desc: 'AI 可访问的文件根目录。', trailing: SizedBox(width: 260, child: TextFormField(initialValue: s['workspace'] ?? '', decoration: const InputDecoration(isDense: true, hintText: '留空 = 用户主目录'), onFieldSubmitted: (v) { state.settings['workspace'] = v.trim(); state.saveSettings(); }))),
        _Row(label: '允许读取文件', desc: 'AI 可读工作目录下的文件内容。', trailing: Switch(value: s['allow_read'] != false, onChanged: (v) { state.settings['allow_read'] = v; state.saveSettings(); })),
        _Row(label: '允许写入文件', desc: 'AI 可创建/修改工作目录下的文件。', trailing: Switch(value: s['allow_write'] == true, onChanged: (v) { state.settings['allow_write'] = v; state.saveSettings(); })),
        _Row(label: '允许执行命令', desc: 'AI 可在容器或本机终端执行命令。', trailing: Switch(value: s['allow_exec'] == true, onChanged: (v) { state.settings['allow_exec'] = v; state.saveSettings(); })),
        _Row(label: '命令确认', desc: '执行命令前弹出确认对话框。', trailing: Switch(value: s['exec_confirm'] != false, onChanged: (v) { state.settings['exec_confirm'] = v; state.saveSettings(); })),
        _Row(label: '遥测', desc: '发送匿名使用数据帮助改进。', trailing: Switch(value: s['telemetry'] == true, onChanged: (v) { state.settings['telemetry'] = v; state.saveSettings(); })),
      ]),
    ]);
  }

  // ===== 高级功能 =====
  Widget _advancedPage(AppState state) {
    final s = state.settings;
    return Column(children: [
      _Card(title: '高级功能（默认关闭，开启后才加载）', children: [
        _Row(label: 'MCP 客户端', desc: '连接 MCP 服务器扩展 AI 能力。', trailing: Switch(value: s['mcp_enabled'] == true, onChanged: (v) { state.settings['mcp_enabled'] = v; state.saveSettings(); })),
        if (s['mcp_enabled'] == true)
          _Row(label: 'MCP Servers', desc: '配置 stdio MCP 服务器命令和参数（JSON）。', trailing: OutlinedButton(onPressed: () => showDialog(context: context, builder: (_) => AlertDialog(title: const Text('MCP Servers'), content: SizedBox(width: 400, child: TextField(maxLines: 8, controller: TextEditingController(text: (s['mcp_config'] ?? '').toString()), decoration: const InputDecoration(hintText: '{"filesystem": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem"]}}'))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () { state.saveSettings(); Navigator.pop(context); }, child: const Text('保存'))])), child: const Text('配置…'))),
        _Row(label: '长期记忆', desc: 'AI 跨对话记住关键信息。', trailing: Switch(value: s['memory_enabled'] == true, onChanged: (v) { state.settings['memory_enabled'] = v; state.saveSettings(); })),
        if (s['memory_enabled'] == true)
          _Row(label: '记忆容量（条）', desc: '长期记忆最多保存条数。', trailing: SpinField(min: 10, max: 5000, value: _num(s, 'memory_capacity', 500).toDouble(), step: 50, onChanged: (v) { state.settings['memory_capacity'] = v.toInt(); state.saveSettings(); })),
        _Row(label: '任务模式', desc: 'AI 自动多步执行任务。', trailing: Switch(value: s['task_mode'] == true, onChanged: (v) { state.settings['task_mode'] = v; state.saveSettings(); })),
        if (s['task_mode'] == true)
          _Row(label: '最大任务步数', desc: '一次提问最多连续执行多少步。', trailing: SpinField(min: 3, max: 50, value: _num(s, 'max_agent_steps', 8).toDouble(), step: 1, decimals: 0, onChanged: (v) { state.settings['max_agent_steps'] = v.toInt(); state.saveSettings(); })),
        _Row(label: '文件 / Git 工具', desc: 'AI 可操作文件和 Git 仓库。', trailing: Switch(value: s['file_git_enabled'] == true, onChanged: (v) { state.settings['file_git_enabled'] = v; state.saveSettings(); })),
        _Row(label: '内置浏览器', desc: 'AI 可打开网页、提取内容。', trailing: Switch(value: s['browser_enabled'] == true, onChanged: (v) { state.settings['browser_enabled'] = v; state.saveSettings(); })),
        _Row(label: '多模态图片输入', desc: '对话中可粘贴/选择图片发送给视觉模型。', trailing: Switch(value: s['image_input_enabled'] == true, onChanged: (v) { state.settings['image_input_enabled'] = v; state.saveSettings(); })),
        _Row(label: '对话导出', desc: '对话界面出现导出按钮，保存为 Markdown。', trailing: Switch(value: s['export_enabled'] == true, onChanged: (v) { state.settings['export_enabled'] = v; state.saveSettings(); })),
        _Row(label: '容器工作区', desc: 'AI 在 WSL/Docker 隔离环境中执行命令。', trailing: Switch(value: s['container_enabled'] == true, onChanged: (v) { state.settings['container_enabled'] = v; state.saveSettings(); })),
        if (s['container_enabled'] == true) ...[
          _ContainerDetectCard(state: state),
          _Row(label: '容器类型', desc: '自动检测当前系统可用的容器环境。', trailing: SegmentedButton<String>(segments: const [ButtonSegment(value: 'auto', label: Text('自动')), ButtonSegment(value: 'wsl', label: Text('WSL')), ButtonSegment(value: 'docker', label: Text('Docker'))], selected: {_opt(s, 'container_type', 'auto', const {'auto', 'wsl', 'docker'})}, onSelectionChanged: (sel) { state.settings['container_type'] = sel.first; state.saveSettings(); })),
          _Row(label: '发行版 / 镜像', desc: '自动检测时留空；手动指定如 Ubuntu-22.04。', trailing: SizedBox(width: 220, child: TextField(controller: TextEditingController(text: (s['container_distro'] ?? '').toString()), decoration: const InputDecoration(isDense: true, hintText: '自动检测'), onSubmitted: (v) { state.settings['container_distro'] = v.trim(); state.saveSettings(); }))),
          _Row(label: '自动配置国内镜像', desc: '容器内自动配置 apt/pip 国内源加速。', trailing: Switch(value: s['container_mirror'] != false, onChanged: (v) { state.settings['container_mirror'] = v; state.saveSettings(); })),
        ],
      ]),
    ]);
  }

  // ===== 本地推理 =====
  Widget _localPage(AppState state) {
    final s = state.settings;
    return Column(children: [
      _Card(title: '本地推理', children: [
        _Row(label: 'GPU 加速', desc: '自动检测 / 纯 CPU / Vulkan（兼容 N/A/I 卡）。', trailing: SegmentedButton<String>(segments: const [ButtonSegment(value: 'auto', label: Text('自动')), ButtonSegment(value: 'cpu', label: Text('CPU')), ButtonSegment(value: 'vulkan', label: Text('Vulkan'))], selected: {_opt(s, 'local_gpu', 'auto', const {'auto', 'cpu', 'vulkan'})}, onSelectionChanged: (sel) { state.settings['local_gpu'] = sel.first; state.saveSettings(); })),
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [const SizedBox(width: 120, child: Text('GPU 层数', style: TextStyle(fontSize: 13))), const SizedBox(width: 12), Expanded(child: Slider(value: _num(s, 'local_gpu_layers', 0).toDouble().clamp(0, 100), min: 0, max: 100, divisions: 10, label: '${s['local_gpu_layers'] ?? 0}', onChanged: (v) { state.settings['local_gpu_layers'] = v.round(); state.saveSettings(); })), SizedBox(width: 36, child: Text('${s['local_gpu_layers'] ?? 0}', style: const TextStyle(fontSize: 13)))]),),
        _Row(label: '上下文长度', desc: '本地模型单次可处理的 token 数。', trailing: SpinField(min: 512, max: 131072, value: _num(s, 'local_n_ctx', 4096).toDouble(), step: 512, onChanged: (v) { state.settings['local_n_ctx'] = v.toInt(); state.saveSettings(); })),
        _Row(label: '使用 HF 国内镜像', desc: '模型市场下载走 hf-mirror.com。', trailing: Switch(value: s['hf_mirror'] != false, onChanged: (v) { state.settings['hf_mirror'] = v; state.saveSettings(); })),
      ]),
    ]);
  }

  // ===== 服务 =====
  Widget _serverPage(AppState state) {
    final s = state.settings;
    return Column(children: [
      _Card(title: '服务监听', children: [
        _Row(label: '监听地址', desc: '127.0.0.1 = 仅本机；0.0.0.0 = 局域网可连。重启后端生效。', trailing: SizedBox(width: 200, child: TextField(controller: TextEditingController(text: (s['api_host'] ?? '127.0.0.1').toString()), decoration: const InputDecoration(isDense: true, hintText: '127.0.0.1'), onSubmitted: (v) { state.settings['api_host'] = v.trim(); state.saveSettings(); }))),
        _Row(label: '端口', desc: '后端 API 端口。重启后端生效。', trailing: SpinField(min: 1024, max: 65535, value: _num(s, 'api_port', 19730).toDouble(), step: 1, decimals: 0, onChanged: (v) { state.settings['api_port'] = v.toInt(); state.saveSettings(); })),
        _Row(label: 'API Key', desc: '远程调用时的鉴权密钥（留空不校验）。', trailing: SizedBox(width: 200, child: TextField(controller: TextEditingController(text: (s['api_key'] ?? '').toString()), obscureText: true, decoration: const InputDecoration(isDense: true, hintText: '留空 = 不校验'), onSubmitted: (v) { state.settings['api_key'] = v.trim(); state.saveSettings(); }))),
      ]),
    ]);
  }

  // ===== 个性化 =====
  Widget _appearancePage(AppState state) {
    final s = state.settings;
    return Column(children: [
      _Card(title: '个性化', children: [
        _Row(label: 'UI 模式', desc: '精简：顶部菜单切换；经典：左侧历史对话栏。', trailing: SegmentedButton<String>(segments: const [ButtonSegment(value: 'compact', label: Text('精简')), ButtonSegment(value: 'classic', label: Text('经典'))], selected: {state.uiMode}, onSelectionChanged: (sel) { state.setUiMode(sel.first); })),
        const SizedBox(height: 14),
        _Row(label: '界面主题', desc: '跟随系统，或手动固定深浅色。', trailing: SegmentedButton<String>(segments: const [ButtonSegment(value: 'system', label: Text('跟随系统')), ButtonSegment(value: 'light', label: Text('浅色')), ButtonSegment(value: 'dark', label: Text('深色'))], selected: {_opt(s, 'theme_mode', 'system', const {'system', 'light', 'dark'})}, onSelectionChanged: (sel) { state.setThemeMode(sel.first); })),
        const SizedBox(height: 14),
        // 强调色
        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
          const SizedBox(width: 120, child: Text('强调色', style: TextStyle(fontSize: 13))),
          const SizedBox(width: 12),
          Wrap(spacing: 10, children: [
            for (final c in [0xFF10A37F, 0xFF6750A4, 0xFFB3261E, 0xFF006A6A, 0xFF7C4D00, 0xFF1976D2, 0xFFE91E63, 0xFFFF5722])
              GestureDetector(
                onTap: () { state.settings['accent_color'] = c; state.saveSettings(); },
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: Color(c), shape: BoxShape.circle,
                    border: Border.all(color: _int(s, 'accent_color', 0xFF10A37F) == c ? Colors.white : Colors.transparent, width: 2),
                  ),
                ),
              ),
          ]),
        ])),
        _Row(label: '圆角大小', desc: '卡片和按钮的圆角半径（0 ~ 24）。', trailing: SpinField(min: 0, max: 24, value: _num(s, 'corner_radius', 12).toDouble(), step: 2, decimals: 0, onChanged: (v) { state.settings['corner_radius'] = v.toInt(); state.saveSettings(); })),
        // 背景图片
        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
          const SizedBox(width: 120, child: Text('背景图片', style: TextStyle(fontSize: 13))),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(initialValue: s['bg_image'] ?? '', decoration: const InputDecoration(hintText: '留空 = 纯色背景', isDense: true), onChanged: (v) { state.settings['bg_image'] = v; state.saveSettings(); })),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () { state.settings['bg_image'] = ''; state.saveSettings(); }, child: const Text('清除')),
        ])),
        _Row(label: '背景不透明度', desc: '设置了背景图片时的不透明度（0.1 ~ 1.0）。', trailing: SizedBox(width: 200, child: Slider(value: _num(s, 'bg_opacity', 0.9).toDouble().clamp(0.1, 1.0), min: 0.1, max: 1.0, divisions: 9, label: '${(_num(s, 'bg_opacity', 0.9) * 100).round()}%', onChanged: (v) { state.settings['bg_opacity'] = v; state.saveSettings(); }))),
      ]),
    ]);
  }

  // ===== 关于 =====
  Widget _aboutPage(AppState state) {
    final cs = Theme.of(context).colorScheme;
    return _Card(title: '关于', children: [
      Row(children: [
        Container(
          width: 48, height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(14)),
          child: const Text('D', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('darling-ai', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
          Text('版本 3.1.8', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ])),
      ]),
      const SizedBox(height: 16),
      const Text('本地 AI 工作台 · Flutter + Python 桥接', style: TextStyle(fontSize: 13)),
      const SizedBox(height: 6),
      const Text('GitHub: DarlingZeroTwo-Cloud/Darling-ai', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () async {
          const url = 'https://github.com/DarlingZeroTwo-Cloud/Darling-ai/releases/latest';
          try {
            if (Platform.isWindows) {
              await Process.start('cmd', ['/c', 'start', '', url]);
            } else {
              await Process.start('xdg-open', [url]);
            }
          } catch (_) {}
        },
        icon: const Icon(Icons.open_in_new, size: 14),
        label: const Text('检查更新'),
      ),
    ]);
  }
}

// ===== 通用控件 =====

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(icon, size: 18, color: selected ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? cs.primary : cs.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Card({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String desc;
  final Widget trailing;
  const _Row({required this.label, required this.desc, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: 160, child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: cs.onSurface))),
        const SizedBox(width: 16),
        Expanded(child: Text(desc, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
        const SizedBox(width: 16),
        trailing,
      ]),
    );
  }
}

class _TempSlider extends StatelessWidget {
  final AppState state;
  const _TempSlider({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = _num(state.settings, 'temperature', 0.7).toDouble();
    return SizedBox(
      width: 200,
      child: Row(children: [
        Expanded(child: Slider(value: t.clamp(0.0, 2.0), min: 0, max: 2, divisions: 20, label: t.toStringAsFixed(1), onChanged: (v) { state.settings['temperature'] = v; state.saveSettings(); })),
        SizedBox(width: 36, child: Text(t.toStringAsFixed(1), style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

/// 容器环境自动检测结果卡片
class _ContainerDetectCard extends StatefulWidget {
  final AppState state;
  const _ContainerDetectCard({required this.state});

  @override
  State<_ContainerDetectCard> createState() => _ContainerDetectCardState();
}

class _ContainerDetectCardState extends State<_ContainerDetectCard> {
  Map<String, dynamic>? _info;
  bool _loading = false;

  Future<void> _detect() async {
    setState(() => _loading = true);
    try {
      final r = await widget.state.api.containerDetect();
      if (mounted) setState(() {
        _info = r;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _info = null;
        _loading = false;
      });
    }
  }

  String _summary(Map<String, dynamic> info) {
    final distros = info['distros'];
    final distroList = distros is List ? distros : <dynamic>[];
    if (info['platform'] == 'windows') {
      if (info['wsl_installed'] == true) {
        return '已检测到 WSL，发行版：${distroList.join('、')}';
      }
      return '未检测到 WSL（可到微软商店安装）';
    }
    if (info['docker_installed'] == true) {
      return info['docker_running'] == true
          ? '已检测到 Docker（运行中）'
          : '已检测到 Docker（未运行）';
    }
    return '未检测到 Docker';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = _info;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 160),
          const SizedBox(width: 16),
          Expanded(
            child: info == null
                ? Text('尚未检测容器环境',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _summary(info),
                        style: TextStyle(fontSize: 12.5, color: cs.onSurface),
                      ),
                      if ((info['distros'] is List &&
                              (info['distros'] as List).isNotEmpty) ||
                          (info['docker_installed'] == true))
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            info['platform'] == 'windows'
                                ? '在“发行版 / 镜像”留空即自动使用第一个发行版'
                                : '在“发行版 / 镜像”可填镜像名如 ubuntu:22.04',
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
          ),
          OutlinedButton.icon(
            onPressed: _loading ? null : _detect,
            icon: _loading
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 14),
            label: Text(_loading ? '检测中…' : '重新检测'),
          ),
        ],
      ),
    );
  }
}

class _RolePicker extends StatelessWidget {
  final AppState state;
  const _RolePicker({required this.state});

  static const roles = [
    ('general', '通用助手'),
    ('programmer', '程序员'),
    ('writer', '写作助手'),
    ('translator', '翻译'),
    ('analyst', '数据分析师'),
    ('mentor', '导师'),
    ('hr', 'HR 专家'),
    ('marketing', '营销策划'),
    ('custom', '自定义角色'),
  ];

  @override
  Widget build(BuildContext context) {
    final raw = state.settings['assistant_role']?.toString() ?? 'general';
    final cur = roles.any((r) => r.$1 == raw) ? raw : 'general';
    return DropdownButton<String>(
      value: cur,
      isDense: true,
      underline: const SizedBox.shrink(),
      items: [for (final (k, label) in roles) DropdownMenuItem(value: k, child: Text(label))],
      onChanged: (v) {
        if (v != null) state.setAssistantRole(v);
      },
    );
  }
}
