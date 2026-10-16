
import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';

class Sidebar extends StatefulWidget {
  final AppState state;
  final int nav;
  final ValueChanged<int> onNav;

  const Sidebar({
    super.key,
    required this.state,
    required this.nav,
    required this.onNav,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  String _q = '';
  List<Map<String, dynamic>> _pinned = [];
  List<Map<String, dynamic>> _normal = [];

  List<Widget> _buildItems(BuildContext context, List<Map<String, dynamic>> list) {
    return [
      for (final c in list)
        _ConvItem(
          title: (c['title'] as String? ?? '新对话').trim(),
          sel: c['id'] == widget.state.activeConvId,
          pinned: c['pinned'] == true,
          onTap: () => widget.state.loadConversation(c['id'] as String),
          onRename: () => widget.state.renameActiveConversationFor(
              context, c['id'] as String, (c['title'] as String? ?? '新对话').trim()),
          onDelete: () => widget.state.confirmDeleteConversation(
              context, c['id'] as String, (c['title'] as String? ?? '新对话').trim()),
          onTogglePin: () => widget.state.togglePinConversation(c['id'] as String),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final all = widget.state.conversations.cast<Map<String, dynamic>>().toList();
    final q = _q.trim().toLowerCase();
    var convs = q.isEmpty
        ? all
        : all.where((c) {
            final title = (c['title'] ?? '').toString().toLowerCase();
            return title.contains(q);
          }).toList();
    // 置顶排前面，同组内按原顺序（最近在前）
    convs.sort((a, b) {
      final pa = a['pinned'] == true ? 0 : 1;
      final pb = b['pinned'] == true ? 0 : 1;
      return pa - pb;
    });
    _pinned = convs.where((c) => c['pinned'] == true).toList();
    _normal = convs.where((c) => c['pinned'] != true).toList();

    return Container(
      width: 248,
      color: dark ? const Color(0xFF1E222A) : const Color(0xFFFFFFFF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 品牌区
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'D',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('darling-ai',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface)),
                      Text('本地 AI 工作台',
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 新建对话
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: FilledButton.icon(
              onPressed: () => widget.state.newConversation(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建对话'),
              style: FilledButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          // 搜索对话
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: '搜索对话',
                prefixIcon: const Icon(Icons.search, size: 17),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: dark ? const Color(0xFF262B34) : const Color(0xFFF0F2F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
            child: Text(q.isEmpty ? '对话' : '搜索结果 (${convs.length})',
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ),
          // 会话列表（置顶 / 普通分组）
          Expanded(
            child: convs.isEmpty
                ? Center(
                    child: Text(q.isEmpty ? '暂无对话' : '没有匹配的对话',
                        style: const TextStyle(color: Color(0xFF9AA1AC), fontSize: 12)))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    children: [
                      if (!q.isEmpty)
                        ..._buildItems(context, convs)
                      else ...[
                        if (_pinned.isNotEmpty) ...[
                          _SectionLabel('置顶'),
                          ..._buildItems(context, _pinned),
                        ],
                        _SectionLabel('对话'),
                        ..._buildItems(context, _normal),
                      ],
                    ],
                  ),
          ),
          // 底部导航（MD3 NavigationRail 竖排）
          Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dark ? const Color(0x6623272F) : const Color(0x66FFFFFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: dark ? const Color(0x33FFFFFF) : const Color(0x22000000)),
            ),
            child: NavigationRail(
              selectedIndex: widget.nav,
              onDestinationSelected: widget.onNav,
              labelType: NavigationRailLabelType.all,
              minWidth: 220,
              backgroundColor: Colors.transparent,
              indicatorColor: cs.secondaryContainer,
              destinations: [
                NavigationRailDestination(
                  icon: Icon(Icons.forum_outlined, color: cs.onSurfaceVariant),
                  selectedIcon: Icon(Icons.forum, color: cs.primary),
                  label: Text('对话',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: widget.nav == 0 ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.model_training_outlined, color: cs.onSurfaceVariant),
                  selectedIcon: Icon(Icons.model_training, color: cs.primary),
                  label: Text('模型',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: widget.nav == 1 ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.extension_outlined, color: cs.onSurfaceVariant),
                  selectedIcon: Icon(Icons.extension, color: cs.primary),
                  label: Text('插件',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: widget.nav == 2 ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined, color: cs.onSurfaceVariant),
                  selectedIcon: Icon(Icons.settings, color: cs.primary),
                  label: Text('设置',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: widget.nav == 3 ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.smart_toy_outlined, color: cs.onSurfaceVariant),
                  selectedIcon: Icon(Icons.smart_toy, color: cs.primary),
                  label: Text('本地',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: widget.nav == 4 ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 3),
      child: Text(text,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: cs.onSurfaceVariant)),
    );
  }
}

class _ConvItem extends StatefulWidget {
  final String title;
  final bool sel;
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
  const _ConvItem({
    required this.title,
    required this.sel,
    required this.pinned,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onTogglePin,
  });

  @override
  State<_ConvItem> createState() => _ConvItemState();
}

class _ConvItemState extends State<_ConvItem> {
  bool _hover = false;

  Future<void> _showCtxMenu() async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = context.findRenderObject() as RenderBox;
    final res = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        box.localToGlobal(Offset.zero) & box.size,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 'pin', child: Row(children: [
          Icon(widget.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 16),
          const SizedBox(width: 10),
          Text(widget.pinned ? '取消置顶' : '置顶'),
        ])),
        PopupMenuItem(value: 'rename', child: Row(children: [
          const Icon(Icons.edit_outlined, size: 16),
          const SizedBox(width: 10),
          const Text('重命名'),
        ])),
        PopupMenuItem(value: 'delete', child: Row(children: [
          const Icon(Icons.delete_outline, size: 16),
          const SizedBox(width: 10),
          const Text('删除'),
        ])),
      ],
    );
    switch (res) {
      case 'pin':
        widget.onTogglePin();
      case 'rename':
        widget.onRename();
      case 'delete':
        widget.onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GestureDetector(
        onSecondaryTap: _showCtxMenu,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Material(
          color: widget.sel ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: widget.onTap,
            onDoubleTap: widget.onRename,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.sel
                      ? cs.primary.withValues(alpha: 0.45)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                      widget.pinned
                          ? Icons.push_pin
                          : Icons.chat_bubble_outline,
                      size: 16,
                      color: widget.sel
                          ? cs.primary
                          : (widget.pinned ? cs.primary : cs.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title.isEmpty ? '新对话' : widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: widget.sel ? FontWeight.w600 : FontWeight.w400,
                        color: widget.sel ? cs.onSecondaryContainer : cs.onSurface,
                      ),
                    ),
                  ),
                  if (widget.sel || _hover) ...[
                    IconButton(
                      onPressed: widget.onTogglePin,
                      icon: Icon(widget.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 14),
                      visualDensity: VisualDensity.compact,
                      tooltip: widget.pinned ? '取消置顶' : '置顶',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(24, 24),
                        padding: EdgeInsets.zero,
                        foregroundColor: cs.onSurfaceVariant,
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onRename,
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      visualDensity: VisualDensity.compact,
                      tooltip: '重命名',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(24, 24),
                        padding: EdgeInsets.zero,
                        foregroundColor: cs.onSurfaceVariant,
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.close, size: 14),
                      visualDensity: VisualDensity.compact,
                      tooltip: '删除对话',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(24, 24),
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
      ),
    );
  }
}
