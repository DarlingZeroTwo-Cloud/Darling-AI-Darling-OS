import 'package:flutter/material.dart';

import '../main.dart';

/// MD3 风格步进输入（替代 Qt SpinField 的上下键）
class SpinField extends StatelessWidget {
  final double min, max, step, value;
  final int decimals;
  final ValueChanged<double> onChanged;

  const SpinField({
    super.key,
    required this.min,
    required this.max,
    required this.value,
    required this.step,
    required this.onChanged,
    this.decimals = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fmt = value.toStringAsFixed(decimals);
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF21252D) : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: dark ? kOutlineDark : kOutlineLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 36,
            child: IconButton(
              onPressed: () =>
                  onChanged(_clamp(value - step)),
              padding: EdgeInsets.zero,
              icon: Icon(Icons.remove, size: 17, color: cs.onSurfaceVariant),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 46),
            child: Text(
              fmt,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 34,
            height: 36,
            child: IconButton(
              onPressed: () =>
                  onChanged(_clamp(value + step)),
              padding: EdgeInsets.zero,
              icon: Icon(Icons.add, size: 17, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  double _clamp(double v) => v.clamp(min, max).toDouble();
}
