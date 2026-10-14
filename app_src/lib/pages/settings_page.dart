import 'dart:io';
import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';
import '../dialogs/prompt_dialog.dart';
import '../widgets/spin_field.dart';

class SettingsPage extends StatefulWidget {
  final AppState state;
  const SettingsPage({super.key, required this.state});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _scroll = ScrollController();
  int _nav = 0;

  static const _sections = [
    ('对话', Icons.chat_bubble_outline),
    ('网络', Icons.public),
    ('权限', Icons.shield_outlined),
    ('高级功能', Icons.auto_awesome),
    ('本地推理', Icons.memory),
    ('服务', Icons.dns_outlined),
    ('个性化', Icons.palette_outlined),
  ];

  final _keys = List.generate(_sections.length, (_) => GlobalKey());

  void _jump(int i) {
    setState(() => _nav = i);
    final ctx = _keys[i].currentContext;
    if (ctx != null && _scroll.hasClients) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null) {
        final target = _scroll.position.minScrollExtent +
            box.localToGlobal(Offset.zero).dy -
            _scroll.position.viewportDimension * 0.1;
        _scroll.animateTo(
          target.clamp(_scroll.position.minScrollExtent, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final state = widget.state;
        final s = state.settings;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                      onTap: () => _jump(i),
                    ),
                ],
              ),
            ),
            // 内容区
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 20, 24, 24),
                children: [
                  _Card(
                    key: _keys[0],
                    title: '对话',
                    children: [
                      _Row(
                        label: '温度 temperature',
                        desc: '控制回复随机性（0 ~ 2），默认 0.7。',
                        trailing: _TempSlider(state: state),
                      ),
                      _Row(
                        label: '最大回复 tokens',
                        desc: '单次回复长度上限。',
                        trailing: SpinField(
                          min: 256,
                          max: 131072,
                          value: (s['max_tokens'] as num? ?? 4096).toDouble(),
                          step: 512,
                          onChanged: (v) {
                            state.settings['max_tokens'] = v.toInt();
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '思考强度',
                        desc: 'o 系列 / DeepSeek R1 等支持该参数的模型生效；不支持时请选“不发送”。',
                        trailing: _EffortMenu(state: state),
                      ),
                      _Row(
                        label: 'Top-P 核采样',
                        desc: '默认 1.0（不发送该参数）。',
                        trailing: SpinField(
                          min: 0.01,
                          max: 1.0,
                          value: (s['top_p'] as num? ?? 1.0).toDouble(),
                          step: 0.05,
                          decimals: 2,
                          onChanged: (v) {
                            state.settings['top_p'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '系统提示词',
                        desc: '定义 AI 的角色与能力边界。',
                        trailing: OutlinedButton(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => PromptDialog(state: state),
                          ),
                          child: const Text('查看 / 编辑'),
                        ),
                      ),
                      _Row(
                        label: '流式输出',
                        desc: '逐字显示 AI 回复。关闭则等全部生成完再显示。',
                        trailing: Switch(
                          value: s['stream'] != false,
                          onChanged: (v) {
                            state.settings['stream'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '自动滚动到底部',
                        desc: '新消息自动滚动到最新内容。',
                        trailing: Switch(
                          value: s['auto_scroll'] != false,
                          onChanged: (v) {
                            state.settings['auto_scroll'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '显示 token 用量',
                        desc: '每条回复后显示消耗的 token 数。',
                        trailing: Switch(
                          value: s['show_tokens'] == true,
                          onChanged: (v) {
                            state.settings['show_tokens'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '对话字体大小',
                        desc: '聊天内容的字号（12 ~ 20）。',
                        trailing: SpinField(
                          min: 12,
                          max: 20,
                          value: (s['chat_font_size'] as num? ?? 14).toDouble(),
                          step: 1,
                          decimals: 0,
                          onChanged: (v) {
                            state.settings['chat_font_size'] = v.toInt();
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '历史消息保留条数',
                        desc: '发给 AI 的最近消息数（越大越占 token，默认 20）。',
                        trailing: SpinField(
                          min: 4,
                          max: 100,
                          value: (s['history_limit'] as num? ?? 20).toDouble(),
                          step: 2,
                          decimals: 0,
                          onChanged: (v) {
                            state.settings['history_limit'] = v.toInt();
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '自动压缩阈值',
                        desc: '历史 token 超过此值时自动压缩（默认 60000）。',
                        trailing: SpinField(
                          min: 4000,
                          max: 200000,
                          value: (s['context_compress_threshold'] as num? ?? 60000).toDouble(),
                          step: 2000,
                          onChanged: (v) {
                            state.settings['context_compress_threshold'] = v.toInt();
                            state.saveSettings();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Card(
                    key: _keys[1],
                    title: '网络',
                    children: [
                      _Row(
                        label: '连接超时（秒）',
                        desc: '连不上时快速失败并重试，避免一直等待。',
                        trailing: SpinField(
                          min: 3,
                          max: 120,
                          value: (s['connect_timeout'] as num? ?? 15).toDouble(),
                          step: 1,
                          onChanged: (v) {
                            state.settings['connect_timeout'] = v.toInt();
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: 'API 失败重试次数',
                        desc: '流式请求失败后的额外重试次数（0 ~ 5）。',
                        trailing: SpinField(
                          min: 0,
                          max: 5,
                          value: (s['api_retries'] as num? ?? 1).toDouble(),
                          step: 1,
                          onChanged: (v) {
                            state.settings['api_retries'] = v.toInt();
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '使用系统代理',
                        desc: '默认直连，避免残留代理导致连不上服务器。需要走代理时再开启。',
                        trailing: Switch(
                          value: s['use_proxy'] == true,
                          onChanged: (v) {
                            state.settings['use_proxy'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: 'SSE 断线重连次数',
                        desc: '流式断开后自动重连次数（0 ~ 10）。',
                        trailing: SpinField(
                          min: 0,
                          max: 10,
                          value: (s['sse_reconnects'] as num? ?? 3).toDouble(),
                          step: 1,
                          decimals: 0,
                          onChanged: (v) {
                            state.settings['sse_reconnects'] = v.toInt();
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '请求间隔（毫秒）',
                        desc: '连续请求之间的等待，避免触发限流。',
                        trailing: SpinField(
                          min: 0,
                          max: 5000,
                          value: (s['request_delay_ms'] as num? ?? 0).toDouble(),
                          step: 100,
                          onChanged: (v) {
                            state.settings['request_delay_ms'] = v.toInt();
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '自定义 CA 证书',
                        desc: '企业代理环境下的自定义根证书（留空用系统证书）。',
                        trailing: OutlinedButton(
                          onPressed: () async {
                            // TODO: file picker
                          },
                          child: const Text('选择…'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Card(
                    key: _keys[2],
                    title: '访问权限',
                    children: [
                      _Row(
                        label: 'AI 访问模式',
                        desc: '完全访问：命令自动执行；按需访问：每次执行前询问。',
                        trailing: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'full', label: Text('完全访问')),
                            ButtonSegment(value: 'on_demand', label: Text('按需访问')),
                          ],
                          selected: {s['access_mode'] ?? 'on_demand'},
                          onSelectionChanged: (sel) {
                            state.settings['access_mode'] = sel.first;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '默认工作区',
                        desc: 'AI 执行命令、读写文件的目录。',
                        trailing: OutlinedButton(
                          onPressed: () => _pickWorkspace(context),
                          child: const Text('选择目录…'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Card(
                    key: _keys[3],
                    title: '高级功能',
                    children: [
                      _Row(
                        label: 'MCP 客户端',
                        desc: '连接外部 MCP server（stdio JSON-RPC）。开启后才加载。',
                        trailing: Switch(
                          value: s['mcp_enabled'] == true,
                          onChanged: (v) {
                            state.settings['mcp_enabled'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '长期记忆',
                        desc: '跨会话 SQLite 记忆，对话结束自动沉淀。',
                        trailing: Switch(
                          value: s['memory_enabled'] == true,
                          onChanged: (v) {
                            state.settings['memory_enabled'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '任务模式',
                        desc: 'AI 多步自动执行（连续调用工具直到完成）。',
                        trailing: Switch(
                          value: s['task_mode'] == true,
                          onChanged: (v) {
                            state.settings['task_mode'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '文件 / Git 工具',
                        desc: 'AI 可读写文件、执行 git 命令。',
                        trailing: Switch(
                          value: s['file_git_enabled'] == true,
                          onChanged: (v) {
                            state.settings['file_git_enabled'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '内置浏览器',
                        desc: 'AI 可打开网页、提取内容。开启后加载 WebView。',
                        trailing: Switch(
                          value: s['browser_enabled'] == true,
                          onChanged: (v) {
                            state.settings['browser_enabled'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '多模态图片输入',
                        desc: '对话中可粘贴/选择图片发送给支持视觉的模型。',
                        trailing: Switch(
                          value: s['image_input_enabled'] == true,
                          onChanged: (v) {
                            state.settings['image_input_enabled'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '对话导出',
                        desc: '对话界面出现导出按钮，可保存为 Markdown。',
                        trailing: Switch(
                          value: s['export_enabled'] == true,
                          onChanged: (v) {
                            state.settings['export_enabled'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '容器工作区',
                        desc: 'WSL (Windows) 或 Docker (Linux) 隔离环境，自动配置国内镜像。',
                        trailing: Switch(
                          value: s['container_enabled'] == true,
                          onChanged: (v) {
                            state.settings['container_enabled'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                      if (s['container_enabled'] == true) ...[
                        _Row(
                          label: '容器类型',
                          desc: '自动检测当前系统可用的容器环境。',
                          trailing: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'auto', label: Text('自动')),
                              ButtonSegment(value: 'wsl', label: Text('WSL')),
                              ButtonSegment(value: 'docker', label: Text('Docker')),
                            ],
                            selected: {s['container_type'] ?? 'auto'},
                            onSelectionChanged: (sel) {
                              state.settings['container_type'] = sel.first;
                              state.saveSettings();
                            },
                          ),
                        ),
                        _Row(
                          label: '发行版 / 镜像',
                          desc: '自动检测时留空即可；手动指定如 Ubuntu-22.04 或 ubuntu:22.04。',
                          trailing: SizedBox(
                            width: 220,
                            child: TextField(
                              controller: TextEditingController(text: (s['container_distro'] ?? '').toString()),
                              decoration: const InputDecoration(isDense: true, hintText: '自动检测'),
                              onSubmitted: (v) {
                                state.settings['container_distro'] = v.trim();
                                state.saveSettings();
                              },
                            ),
                          ),
                        ),
                        _Row(
                          label: '自动配置国内镜像',
                          desc: '容器内自动配置 apt/pip 国内源加速。',
                          trailing: Switch(
                            value: s['container_mirror'] != false,
                            onChanged: (v) {
                              state.settings['container_mirror'] = v;
                              state.saveSettings();
                            },
                          ),
                        ),
                      ],
                      if (s['mcp_enabled'] == true) ...[
                        _Row(
                          label: 'MCP Servers',
                          desc: '配置 stdio MCP 服务器命令和参数。',
                          trailing: OutlinedButton(
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('MCP Servers'),
                                content: SizedBox(
                                  width: 400,
                                  child: TextField(
                                    maxLines: 8,
                                    controller: TextEditingController(text: (s['mcp_config'] ?? '').toString()),
                                    decoration: const InputDecoration(hintText: '{"filesystem": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem"]}}'),
                                  ),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                                  FilledButton(onPressed: () { state.saveSettings(); Navigator.pop(context); }, child: const Text('保存')),
                                ],
                              ),
                            ),
                            child: const Text('配置…'),
                          ),
                        ),
                      ],
                      if (s['memory_enabled'] == true) ...[
                        _Row(
                          label: '记忆容量（条）',
                          desc: '长期记忆最多保存条数，超出自动删除最旧的。',
                          trailing: SpinField(
                            min: 10,
                            max: 5000,
                            value: (s['memory_capacity'] as num? ?? 500).toDouble(),
                            step: 50,
                            onChanged: (v) {
                              state.settings['memory_capacity'] = v.toInt();
                              state.saveSettings();
                            },
                          ),
                        ),
                      ],
                      if (s['task_mode'] == true) ...[
                        _Row(
                          label: '最大任务步数',
                          desc: 'AI 一次提问最多连续执行多少步（防止死循环）。',
                          trailing: SpinField(
                            min: 3,
                            max: 50,
                            value: (s['max_agent_steps'] as num? ?? 8).toDouble(),
                            step: 1,
                            decimals: 0,
                            onChanged: (v) {
                              state.settings['max_agent_steps'] = v.toInt();
                              state.saveSettings();
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Card(
                    key: _keys[4],
                    title: '本地推理',
                    children: [
                      _Row(
                        label: 'GPU 加速',
                        desc: '自动检测 / 纯 CPU / Vulkan（兼容 N/A/I 卡）。需要重启后端生效。',
                        trailing: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'cpu', label: Text('CPU')),
                            ButtonSegment(value: 'auto', label: Text('自动')),
                            ButtonSegment(value: 'vulkan', label: Text('Vulkan')),
                          ],
                          selected: {s['local_gpu_mode'] ?? 'cpu'},
                          onSelectionChanged: (sel) {
                            state.settings['local_gpu_mode'] = sel.first;
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: 'GPU offload 层数',
                        desc: '0 = 纯 CPU；35 = 中型模型推荐；999 = 全部层卸载。',
                        trailing: SizedBox(
                          width: 200,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Expanded(
                              child: Slider(
                                value: (s['local_gpu_layers'] as num? ?? 0)
                                    .toDouble()
                                    .clamp(0, 999),
                                min: 0,
                                max: 999,
                                divisions: 999,
                                label: '${s['local_gpu_layers'] ?? 0}',
                                onChanged: (v) {
                                  state.settings['local_gpu_layers'] = v.toInt();
                                  state.saveSettings();
                                },
                              ),
                            ),
                            SizedBox(
                              width: 36,
                              child: Text(
                                  '${s['local_gpu_layers'] ?? 0}',
                                  style: const TextStyle(fontSize: 13)),
                            ),
                          ]),
                        ),
                      ),
                      _Row(
                        label: '上下文长度',
                        desc: '本地模型单次可处理的 token 数，越大越占内存。',
                        trailing: SpinField(
                          min: 512,
                          max: 131072,
                          value: (s['local_n_ctx'] as num? ?? 4096).toDouble(),
                          step: 512,
                          onChanged: (v) {
                            state.settings['local_n_ctx'] = v.toInt();
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '使用 HF 国内镜像',
                        desc: '模型市场下载走 hf-mirror.com（国内推荐开启）。',
                        trailing: Switch(
                          value: s['hf_mirror'] != false,
                          onChanged: (v) {
                            state.settings['hf_mirror'] = v;
                            state.saveSettings();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Card(
                    key: _keys[5],
                    title: '服务监听',
                    children: [
                      _Row(
                        label: '监听地址',
                        desc: '127.0.0.1 = 仅本机；0.0.0.0 = 局域网其他设备可连；或填指定 IP。重启后端生效。',
                        trailing: SizedBox(
                          width: 200,
                          child: TextField(
                            controller: TextEditingController(
                                text: (s['bind_host'] ?? '127.0.0.1').toString()),
                            decoration: const InputDecoration(
                                isDense: true, hintText: '127.0.0.1'),
                            onSubmitted: (v) {
                              state.settings['bind_host'] = v.trim();
                              state.saveSettings();
                            },
                          ),
                        ),
                      ),
                      _Row(
                        label: 'API Key',
                        desc: '开启后，非本机访问必须带 X-API-Key 头。留空则不校验。',
                        trailing: SizedBox(
                          width: 220,
                          child: TextField(
                            controller: TextEditingController(
                                text: (s['api_key'] ?? '').toString()),
                            decoration: const InputDecoration(
                                isDense: true, hintText: '留空=不校验'),
                            onSubmitted: (v) {
                              state.settings['api_key'] = v.trim();
                              state.saveSettings();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Card(
                    key: _keys[6],
                    title: '外观',
                    children: [
                      _Row(
                        label: 'UI 模式',
                        desc: '精简：顶部菜单切换页面；经典：左侧历史对话栏，设置/模型/插件/本地独立窗口打开。',
                        trailing: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'compact', label: Text('精简')),
                            ButtonSegment(value: 'classic', label: Text('经典')),
                          ],
                          selected: {state.uiMode},
                          onSelectionChanged: (sel) {
                            state.setUiMode(sel.first);
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Row(
                        label: '界面主题',
                        desc: '跟随系统，或手动固定深浅色。',
                        trailing: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'system', label: Text('跟随系统')),
                            ButtonSegment(value: 'light', label: Text('浅色')),
                            ButtonSegment(value: 'dark', label: Text('深色')),
                          ],
                          selected: {s['theme_mode'] ?? 'system'},
                          onSelectionChanged: (sel) {
                            state.setThemeMode(sel.first);
                          },
                        ),
                      ),
                      _Row(
                        label: '强调色',
                        desc: '按钮、高亮等强调色。',
                        trailing: SizedBox(
                          width: 200,
                          child: Wrap(
                            spacing: 8,
                            children: [
                              for (final c in [0xFF10A37F, 0xFF6750A4, 0xFFB3261E, 0xFF006A6A, 0xFF7C4D00])
                                GestureDetector(
                                  onTap: () {
                                    state.settings['accent_color'] = c;
                                    state.saveSettings();
                                  },
                                  child: Container(
                                    width: 28, height: 28,
                                    decoration: BoxDecoration(
                                      color: Color(c),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: (s['accent_color'] as int? ?? 0xFF10A37F) == c
                                            ? Colors.black : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      _Row(
                        label: '圆角大小',
                        desc: '卡片和按钮的圆角半径（0 ~ 24）。',
                        trailing: SpinField(
                          min: 0,
                          max: 24,
                          value: (s['corner_radius'] as num? ?? 12).toDouble(),
                          step: 2,
                          decimals: 0,
                          onChanged: (v) {
                            state.settings['corner_radius'] = v.toInt();
                            state.saveSettings();
                          },
                        ),
                      ),
                      _Row(
                        label: '背景透明度',
                        desc: '设置了背景图片时的不透明度（0.1 ~ 1.0）。',
                        trailing: SizedBox(
                          width: 200,
                          child: Slider(
                            value: (s['bg_opacity'] as num? ?? 0.9).toDouble().clamp(0.1, 1.0),
                            min: 0.1, max: 1.0,
                            divisions: 9,
                            label: '${((s['bg_opacity'] as num? ?? 0.9) * 100).round()}%',
                            onChanged: (v) {
                              state.settings['bg_opacity'] = v;
                              state.saveSettings();
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 120,
                              child: Text('背景图片', style: TextStyle(fontSize: 13)),
                            ),
                            Expanded(
                              child: TextFormField(
                                initialValue: s['bg_image'] ?? '',
                                decoration: const InputDecoration(
                                  hintText: '留空 = 纯色背景',
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                  state.settings['bg_image'] = v.trim();
                                  state.saveSettings();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () async {
                                // 用 PowerShell 弹文件选择框
                                final result = await Process.run(
                                  'powershell',
                                  [
                                    '-NoProfile',
                                    '-Command',
                                    "Add-Type -AssemblyName System.Windows.Forms; "
                                        "\$d = New-Object System.Windows.Forms.OpenFileDialog; "
                                        "\$d.Filter = '图片|*.jpg;*.jpeg;*.png;*.bmp'; "
                                        "if (\$d.ShowDialog() -eq 'OK') { \$d.FileName }"
                                  ],
                                );
                                final path = (result.stdout as String).trim();
                                if (path.isNotEmpty &&
                                    (path.toLowerCase().endsWith('.jpg') ||
                                     path.toLowerCase().endsWith('.jpeg') ||
                                     path.toLowerCase().endsWith('.png') ||
                                     path.toLowerCase().endsWith('.bmp'))) {
                                  state.settings['bg_image'] = path;
                                  state.saveSettings();
                                }
                              },
                              child: const Text('浏览'),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 120,
                              child: Text('背景不透明度', style: TextStyle(fontSize: 13)),
                            ),
                            Expanded(
                              child: Slider(
                                value: (s['bg_opacity'] ?? 0.85).toDouble(),
                                min: 0.3,
                                max: 1.0,
                                divisions: 7,
                                label: ((s['bg_opacity'] ?? 0.85)).toStringAsFixed(2),
                                onChanged: (v) {
                                  state.settings['bg_opacity'] = v;
                                  state.saveSettings();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Card(
                    title: '数据',
                    children: [
                      _Row(
                        label: '清除对话历史',
                        desc: '清空所有对话与保存的历史。',
                        trailing: OutlinedButton(
                          onPressed: () => _clearHistory(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error,
                            side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .error
                                    .withValues(alpha: 0.4)),
                          ),
                          child: const Text('清除历史'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickWorkspace(BuildContext context) async {
    final ctl = TextEditingController(
        text: (widget.state.settings['workspace'] ?? '').toString());
    final val = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置工作区'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '工作区目录路径',
            hintText: r'例如 D:\workspace 或 /home/user/workspace',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('确定')),
        ],
      ),
    );
    if (val != null && val.trim().isNotEmpty) {
      widget.state.settings['workspace'] = val.trim();
      await widget.state.saveSettings();
    }
  }

  Future<void> _clearHistory(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除对话历史'),
        content: const Text('确定清空所有对话与保存的历史？此操作不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.state.api.postJson('/api/config', {
        'histories': <String, dynamic>{},
        'conversations': <dynamic>[],
        'active_conv': null,
      });
      await widget.state.reload();
    }
  }
}

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? cs.onSecondaryContainer : cs.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Card({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                const SizedBox(height: 2),
                Text(desc,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          trailing,
        ],
      ),
    );
  }
}

class _TempSlider extends StatelessWidget {
  final AppState state;
  const _TempSlider({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = (state.settings['temperature'] as num? ?? 0.7).toDouble();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 170,
          child: Slider(
            value: v.clamp(0, 2),
            min: 0,
            max: 2,
            divisions: 20,
            onChanged: (nv) {
              state.settings['temperature'] = (nv * 10).round() / 10.0;
              state.saveSettings();
            },
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(v.toStringAsFixed(1),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
        ),
      ],
    );
  }
}

class _EffortMenu extends StatelessWidget {
  final AppState state;
  const _EffortMenu({required this.state});

  @override
  Widget build(BuildContext context) {
    final eff = (state.settings['reasoning_effort'] ?? 'off').toString();
    const options = [
      ('off', '不发送'),
      ('low', '低 low'),
      ('medium', '中 medium'),
      ('high', '高 high'),
    ];
    return DropdownMenu<String>(
      initialSelection: eff,
      width: 140,
      label: const Text('思考强度'),
      dropdownMenuEntries: [
        for (final (k, v) in options) DropdownMenuEntry(value: k, label: v),
      ],
      onSelected: (v) {
        if (v != null) {
          state.settings['reasoning_effort'] = v;
          state.saveSettings();
        }
      },
    );
  }
}
