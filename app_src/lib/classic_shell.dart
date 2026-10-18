import 'dart:io';

import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';
import 'pages/models_page.dart';
import 'pages/plugins_page.dart';
import 'pages/settings_page.dart';
import 'pages/chat_page.dart';

/// 经典模式（VSCode 风格）：左侧历史对话栏 + 右侧对话/设置区域
class ClassicShell extends StatefulWidget {
  final AppState state;
  const ClassicShell({super.key, required this.state});

  @override
  State<ClassicShell> createState() => _ClassicShellState();
}

class _ClassicShellState extends State<ClassicShell> {
  // 侧边栏折叠状态从设置恢复（记忆上次选择）
  bool get _sidebarCollapsed =>
      widget.state.settings['sidebar_collapsed'] == true;
  String _rightPage = 'chat'; // chat / settings / models / plugins / local

  void _toggleSidebar() {
    widget.state.settings['sidebar_collapsed'] = !_sidebarCollapsed;
    widget.state.saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.state.settings;
    final bgImage = (s['bg_image'] ?? '').toString();
    final bgOpacity = (s['bg_opacity'] ?? 0.85).toDouble();
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF15171C) : const Color(0xFFF4F5F7),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (bgImage.isNotEmpty && File(bgImage).existsSync())
            Opacity(opacity: bgOpacity, child: Image.file(File(bgImage), fit: BoxFit.cover)),
          Column(
            children: [
              _ClassicTopBar(state: widget.state),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ClassicSidebar(
                      state: widget.state,
                      collapsed: _sidebarCollapsed,
                      onToggle: () { setState(() {}); _toggleSidebar(); },
                      onSelectPage: (p) => setState(() => _rightPage = p),
                      onSelectChat: () => setState(() => _rightPage = 'chat'),
                    ),
                    Expanded(child: _buildRight()),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRight() {
    if (_rightPage == 'chat') {
      return ChatPage(state: widget.state);
    }
    // 非对话页：顶部返回栏，可一键回到对话
    final pageTitle = switch (_rightPage) {
      'settings' => '设置',
      'models' => '模型',
      'plugins' => '插件',
      _ => '',
    };
    final Widget page = switch (_rightPage) {
      'settings' => SettingsPage(state: widget.state),
      'models' => ModelsPage(state: widget.state),
      'plugins' => PluginsPage(state: widget.state),
      _ => const SizedBox.shrink(),
    };
    return Column(
      children: [
        // 返回栏
        SizedBox(
          height: 40,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 18),
                tooltip: '返回对话',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _rightPage = 'chat'),
              ),
              Text(pageTitle,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const Spacer(),
            ],
          ),
        ),
        Expanded(child: page),
      ],
    );
  }
}

// ==================== 顶栏 ====================
class _ClassicTopBar extends StatelessWidget {
  final AppState state;
  const _ClassicTopBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: dark ? const Color(0xB31D2027) : const Color(0xB3FFFFFF),
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(Icons.auto_awesome, size: 17, color: cs.primary),
          const SizedBox(width: 8),
          Text('DARLING-AI',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(width: 8),
          Text('v3.4.5',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          const Spacer(),
          // 清空当前对话（二次确认防误触）
          if (state.messages.isNotEmpty)
            Tooltip(
              message: '清空当前对话',
              child: InkWell(
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('清空当前对话'),
                      content: const Text('确定清空当前对话的所有消息？此操作不可恢复。'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('清空')),
                      ],
                    ),
                  );
                  if (ok == true) state.clearActiveConversation();
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.delete_sweep_outlined,
                      size: 17, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          // 新对话
          Tooltip(
            message: '新对话',
            child: InkWell(
              onTap: () => state.newConversation(),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.add, size: 17, color: cs.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

// ==================== 侧边栏（抽屉式） ====================
class _ClassicSidebar extends StatelessWidget {
  final AppState state;
  final bool collapsed;
  final VoidCallback onToggle;
  final void Function(String) onSelectPage;
  final VoidCallback onSelectChat;
  const _ClassicSidebar({
    required this.state,
    required this.collapsed,
    required this.onToggle,
    required this.onSelectPage,
    required this.onSelectChat,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xB31D2027) : const Color(0xB3FAFBFC);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: collapsed ? 30 : 230,
      decoration: BoxDecoration(
        color: bg,
        border: Border(right: BorderSide(color: cs.outlineVariant)),
      ),
      child: collapsed
          ? _CollapsedBar(onToggle: onToggle)
          : _SidebarContent(
              state: state,
              onToggle: onToggle,
              onSelectPage: onSelectPage,
              onSelectChat: onSelectChat,
            ),
    );
  }
}

// 收起态：只留一条窄把手
class _CollapsedBar extends StatelessWidget {
  final VoidCallback onToggle;
  const _CollapsedBar({required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
          onPressed: onToggle,
          tooltip: '展开侧边栏',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _SidebarContent extends StatefulWidget {
  final AppState state;
  final VoidCallback onToggle;
  final void Function(String) onSelectPage;
  final VoidCallback onSelectChat;
  const _SidebarContent({
    required this.state,
    required this.onToggle,
    required this.onSelectPage,
    required this.onSelectChat,
  });

  @override
  State<_SidebarContent> createState() => _SidebarContentState();
}

class _SidebarContentState extends State<_SidebarContent> {
  // 历史对话搜索关键词（按标题/摘要过滤）
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 对话标签
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 12, 6),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left, size: 18, color: cs.onSurfaceVariant),
                onPressed: widget.onToggle,
                tooltip: '收起侧边栏',
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 2),
              Text('对话',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant)),
              const Spacer(),
            ],
          ),
        ),
        // 历史对话搜索框
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
          child: TextField(
            controller: _searchCtrl,
            style: TextStyle(fontSize: 12.5, color: cs.onSurface),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索历史对话…',
              hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              prefixIcon: Icon(Icons.search, size: 15, color: cs.onSurfaceVariant),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 14, color: cs.onSurfaceVariant),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.outlineVariant)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        // 历史对话列表
        Expanded(
          child: ListenableBuilder(
            listenable: state,
            builder: (context, _) {
              final q = _query.toLowerCase();
              final all = state.conversations;
              final convs = q.isEmpty
                  ? all
                  : all.where((c) {
                      final title = (c['title'] ?? '').toString().toLowerCase();
                      final first = (c['first'] ?? '').toString().toLowerCase();
                      final model = (c['model_id'] ?? '').toString().toLowerCase();
                      return title.contains(q) || first.contains(q) || model.contains(q);
                    }).toList();
              if (convs.isEmpty) {
                return const Center(
                    child: Text('暂无历史对话',
                        style: TextStyle(fontSize: 12, color: Color(0xFF9AA1AC))));
              }
              // 排序：置顶优先，其余按最后活跃时间降序（无时间戳的排最后）
              final sorted = List<Map<String, dynamic>>.from(convs)
                ..sort((a, b) {
                  final ap = a['pinned'] == true, bp = b['pinned'] == true;
                  if (ap != bp) return ap ? -1 : 1;
                  final at = (a['ts'] as num?)?.toDouble() ?? 0.0;
                  final bt = (b['ts'] as num?)?.toDouble() ?? 0.0;
                  return bt.compareTo(at);
                });
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: sorted.length,
                itemBuilder: (context, i) {
                  final c = sorted[i] as Map<String, dynamic>;
                  final id = c['id'] as String?;
                  final active = id == state.activeConvId;
                  return _ClassicConvItem(
                    id: id,
                    title: (c['title'] ?? '新对话').toString(),
                    model: (c['model_id'] ?? '').toString(),
                    pinned: c['pinned'] == true,
                    active: active,
                    onTap: () { state.loadConversation(id!); widget.onSelectChat(); },
                    onRename: () => state.renameActiveConversationFor(
                        context, id!, (c['title'] ?? '新对话').toString()),
                    onDelete: () => state.confirmDeleteConversation(
                        context, id!, (c['title'] ?? '新对话').toString()),
                    onPin: () => state.togglePinConversation(id!),
                  );
                },
              );
            },
          ),
        ),
        // 底部入口：设置/模型/插件/本地（页内切换）
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SidebarEntry(
                icon: Icons.settings_outlined,
                label: '设置',
                onTap: () => widget.onSelectPage('settings'),
              ),
              _SidebarEntry(
                icon: Icons.model_training_outlined,
                label: '模型供应商',
                onTap: () => widget.onSelectPage('models'),
              ),
              _SidebarEntry(
                icon: Icons.extension_outlined,
                label: '插件',
                onTap: () => widget.onSelectPage('plugins'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarEntry extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SidebarEntry({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(fontSize: 13, color: cs.onSurface)),
          ],
        ),
      ),
    );
  }
}

// 经典模式对话项（hover 显示重命名/删除）
class _ClassicConvItem extends StatefulWidget {
  final String? id;
  final String title;
  final String model;
  final bool pinned;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  const _ClassicConvItem({
    required this.id,
    required this.title,
    required this.model,
    required this.pinned,
    required this.active,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onPin,
  });

  @override
  State<_ClassicConvItem> createState() => _ClassicConvItemState();
}

class _ClassicConvItemState extends State<_ClassicConvItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
            decoration: BoxDecoration(
              color: widget.active
                  ? (dark ? const Color(0xFF163A36) : const Color(0xFFE2F3F1))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.forum_outlined,
                    size: 15,
                    color: widget.active ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.active ? cs.primary : cs.onSurface,
                            fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.model.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: dark ? const Color(0x26FFFFFF) : const Color(0x11000000),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.model,
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // 操作按钮常驻显示（hover 显示容易点不到）
                if (widget.active || _hover) ...[
                  IconButton(
                    onPressed: widget.onPin,
                    icon: Icon(
                      widget.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 13,
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: widget.pinned ? '取消置顶' : '置顶',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(22, 22),
                      padding: EdgeInsets.zero,
                      foregroundColor:
                          widget.pinned ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onRename,
                    icon: const Icon(Icons.edit_outlined, size: 13),
                    visualDensity: VisualDensity.compact,
                    tooltip: '重命名',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(22, 22),
                      padding: EdgeInsets.zero,
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.close, size: 13),
                    visualDensity: VisualDensity.compact,
                    tooltip: '删除对话',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(22, 22),
                      padding: EdgeInsets.zero,
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
