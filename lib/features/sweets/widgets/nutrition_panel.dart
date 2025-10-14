import 'package:flutter/material.dart';
import '../../sweets/data/sweet.dart';

class NutritionPanel extends StatelessWidget {
  final Sweet sweet;
  final bool visible;
  final VoidCallback onClose;

  const NutritionPanel({
    super.key,
    required this.sweet,
    required this.visible,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // Pills appear on the LEFT when detail is open (to match screenshots)
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(-0.3, 0),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _pill(context, title: 'Salt',    value: '${_fmt(sweet.fat)} g',   percent: 3),
                  const SizedBox(height: 12),
                  _pill(context, title: 'Sugar',   value: '${_fmt(sweet.carbs)} g', percent: 12),
                  const SizedBox(height: 12),
                  _pill(context, title: 'Fat',     value: '${_fmt(sweet.fat)} g',   percent: 12),
                  const SizedBox(height: 12),
                  _pill(context, title: 'Energy',  value: '${sweet.calories} cal',  percent: 40),
                  const SizedBox(height: 8),
                  IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(BuildContext context,
      {required String title, required String value, required int percent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x16000000), blurRadius: 14, offset: Offset(0,8))],
        border: Border.all(color: const Color(0x10A0A0A0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$title $value', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 10),
          _percentBadge(percent),
        ],
      ),
    );
  }

  Widget _percentBadge(int p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF111111), borderRadius: BorderRadius.circular(14),
      ),
      child: Text('$p%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);
}
