import 'dart:io';

import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';
import 'pages/models_page.dart';
import 'pages/plugins_page.dart';
import 'pages/settings_page.dart';
import 'pages/local_models_page.dart';
import 'pages/chat_page.dart';

/// 缁忓吀妯″紡锛圸ed 椋庢牸锛夛細宸︿晶鍘嗗彶瀵硅瘽鏍?+ 鍙充晶瀵硅瘽鍖猴紱
/// 璁剧疆 / 妯″瀷 / 鎻掍欢 / 鏈湴 浠ョ嫭绔嬬獥鍙ｏ紙鍏ㄥ睆娴眰锛夋墦寮€銆?
class ClassicShell extends StatefulWidget {
  final AppState state;
  const ClassicShell({super.key, required this.state});

  @override
  State<ClassicShell> createState() => _ClassicShellState();
}

class _ClassicShellState extends State<ClassicShell> {
  bool _sidebarCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                      onToggle: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                    ),
                    Expanded(child: ChatPage(state: widget.state)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==================== 椤舵爮 ====================
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
        // 鍗婇€忔槑锛氶€忓嚭鑳屾櫙鍥剧墖
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
          Text('v3.1.4',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          const Spacer(),
          // 妯″瀷鍒囨崲 / 鏂板缓瀵硅瘽 宸插苟鍏ヤ晶杈规爮锛屾澶勪笉鐣欓噸澶嶅叆鍙?
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

// ==================== 渚ц竟鏍忥紙鎶藉眽寮忥級 ====================
class _ClassicSidebar extends StatelessWidget {
  final AppState state;
  final bool collapsed;
  final VoidCallback onToggle;
  const _ClassicSidebar(
      {required this.state, required this.collapsed, required this.onToggle});

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
        // 鍗婇€忔槑锛氶€忓嚭鑳屾櫙鍥剧墖
        color: bg,
        border: Border(right: BorderSide(color: cs.outlineVariant)),
      ),
      child: collapsed
          ? _CollapsedBar(onToggle: onToggle)
          : _SidebarContent(state: state, onToggle: onToggle),
    );
  }
}

// 鏀惰捣鎬侊細鍙暀涓€鏉＄獎鎶婃墜
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

class _SidebarContent extends StatelessWidget {
  final AppState state;
  final VoidCallback onToggle;
  const _SidebarContent({required this.state, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 瀵硅瘽鏍囩
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 12, 6),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left, size: 18, color: cs.onSurfaceVariant),
                onPressed: onToggle,
                      tooltip: '收起侧边栏',
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 2),
              Text('瀵硅瘽',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.add, size: 17, color: cs.onSurfaceVariant),
                onPressed: () => state.newConversation(),
                  tooltip: '新对话',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        // 鍘嗗彶瀵硅瘽鍒楄〃
        Expanded(
          child: ListenableBuilder(
            listenable: state,
            builder: (context, _) {
              final convs = state.conversations;
              if (convs.isEmpty) {
                return const Center(
                    child: Text('鏆傛棤鍘嗗彶瀵硅瘽',
                        style: TextStyle(fontSize: 12, color: Color(0xFF9AA1AC))));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: convs.length,
                itemBuilder: (context, i) {
                  final c = convs[i] as Map<String, dynamic>;
                  final id = c['id'] as String?;
                  final active = id == state.activeConvId;
                  return _ClassicConvItem(
                    id: id,
                    title: (c['title'] ?? '新对话').toString(),
                    active: active,
                    onTap: () => state.loadConversation(id!),
                    onRename: () => state.renameActiveConversationFor(
                        context, id!, (c['title'] ?? '新对话').toString()),
                    onDelete: () => state.confirmDeleteConversation(
                        context, id!, (c['title'] ?? '新对话').toString()),
                  );
                },
              );
            },
          ),
        ),
        // 底部入口：设置/ 模型/ 插件/ 本地（独立窗口）
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
                onTap: () => _openWindow(context, '设置', SettingsPage(state: state)),
              ),
              _SidebarEntry(
                icon: Icons.model_training_outlined,
                label: '模型供应商',
                onTap: () => _openWindow(context, '模型供应商', ModelsPage(state: state)),
              ),
              _SidebarEntry(
                icon: Icons.extension_outlined,
                label: '插件',
                onTap: () => _openWindow(context, '插件', PluginsPage(state: state)),
              ),
              _SidebarEntry(
                icon: Icons.smart_toy_outlined,
                label: '本地模型',
                onTap: () => _openWindow(context, '本地模型', LocalModelsPage(state: state)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openWindow(BuildContext context, String title, Widget page) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => _WindowDialog(title: title, child: page, dark: dark),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
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
    final dark = Theme.of(context).brightness == Brightness.dark;
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
            const Spacer(),
            Icon(Icons.open_in_new, size: 13, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

// 缁忓吀妯″紡瀵硅瘽椤癸紙hover 鏄剧ず閲嶅懡鍚?鍒犻櫎锛?
class _ClassicConvItem extends StatefulWidget {
  final String? id;
  final String title;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  const _ClassicConvItem({
    required this.id,
    required this.title,
    required this.active,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
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
                if (widget.active || _hover) ...[
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
                    tooltip: '鍒犻櫎瀵硅瘽',
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

// ==================== 鐙珛绐楀彛锛堝叏灞忔诞灞傦紝浠挎柊绐楀彛锛?====================
class _WindowDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final bool dark;
  const _WindowDialog({required this.title, required this.child, required this.dark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 60, vertical: 48),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF1D2027) : const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // 窗口标题栏
              Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF21252D) : const Color(0xFFF0F2F5),
                  border: Border(bottom: BorderSide(color: cs.outlineVariant)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lens_blur, size: 15, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(title,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cs.onSurface)),
                    const Spacer(),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 17, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: dark ? const Color(0xFF16181D) : const Color(0xFFFFFFFF),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
