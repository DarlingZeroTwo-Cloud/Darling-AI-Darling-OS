import 'package:flutter/material.dart';

/// 等待指示：转圈动画 + 状态文字（正在连接服务器 / 正在思考）
class ThinkingRow extends StatelessWidget {
  final String text;
  const ThinkingRow({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = text.trim().isEmpty ? '正在思考…' : text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _OrbitDot(color: cs.primary),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
                fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 圆点左右踱步动画
class _OrbitDot extends StatefulWidget {
  final Color color;
  const _OrbitDot({required this.color});

  @override
  State<_OrbitDot> createState() => _OrbitDotState();
}

class _OrbitDotState extends State<_OrbitDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (context, _) {
          final t = _ctl.value;
          // 左右踱步 + 弧线
          final dx = (t < 0.5 ? t * 2 : (1 - t) * 2) - 1; // -1..1
          final dy = -(dx * dx) * 6; // 中间高点
          return Transform.translate(
            offset: Offset(dx * 5, dy),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          );
        },
      ),
    );
  }
}
