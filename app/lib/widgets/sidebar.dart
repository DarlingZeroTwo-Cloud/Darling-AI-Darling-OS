
import 'package:flutter/material.dart';

import '../main.dart';
import '../state.dart';

class Sidebar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

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
              onPressed: () => state.newConversation(),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: Text('对话',
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ),
          // 会话列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              itemCount: state.conversations.length,
              itemBuilder: (context, i) {
                final c = state.conversations[i] as Map<String, dynamic>;
                final id = c['id'] as String? ?? '';
                final sel = id == state.activeConvId;
                final title = (c['title'] as String? ?? '新对话').trim();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: sel
                        ? cs.secondaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => state.loadConversation(id),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sel
                                ? cs.primary.withValues(alpha: 0.45)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.chat_bubble_outline,
                                size: 16,
                                color: sel ? cs.primary : cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title.isEmpty ? '新对话' : title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                                  color: sel ? cs.onSecondaryContainer : cs.onSurface,
                                ),
                              ),
                            ),
                            _DeleteBtn(
                              onDelete: () => state.deleteConversation(id),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
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
              selectedIndex: nav,
              onDestinationSelected: onNav,
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
                          color: nav == 0 ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.model_training_outlined, color: cs.onSurfaceVariant),
                  selectedIcon: Icon(Icons.model_training, color: cs.primary),
                  label: Text('模型',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: nav == 1 ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.extension_outlined, color: cs.onSurfaceVariant),
                  selectedIcon: Icon(Icons.extension, color: cs.primary),
                  label: Text('插件',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: nav == 2 ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined, color: cs.onSurfaceVariant),
                  selectedIcon: Icon(Icons.settings, color: cs.primary),
                  label: Text('设置',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: nav == 3 ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.smart_toy_outlined, color: cs.onSurfaceVariant),
                  selectedIcon: Icon(Icons.smart_toy, color: cs.primary),
                  label: Text('本地',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: nav == 4 ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteBtn extends StatelessWidget {
  final VoidCallback onDelete;
  const _DeleteBtn({required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onDelete,
      icon: const Icon(Icons.close, size: 15),
      visualDensity: VisualDensity.compact,
      tooltip: '删除对话',
      style: IconButton.styleFrom(
        minimumSize: const Size(26, 26),
        padding: EdgeInsets.zero,
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
