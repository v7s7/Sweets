// lib/features/sweets/widgets/nutrition_panel.dart
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
    final onSurface = Theme.of(context).colorScheme.onSurface;

    // Collect only provided values (handle nulls safely)
    final entries = <_Entry>[];
    final int calories = sweet.calories ?? 0;
    if (calories > 0) entries.add(_Entry('Energy', '$calories kcal'));

    final double? protein = sweet.protein;
    if (protein != null && protein > 0) {
      entries.add(_Entry('Protein', _g(protein)));
    }

    final double? carbs = sweet.carbs;
    if (carbs != null && carbs > 0) {
      entries.add(_Entry('Carbs', _g(carbs)));
    }

    final double? fat = sweet.fat;
    if (fat != null && fat > 0) {
      entries.add(_Entry('Fat', _g(fat)));
    }

    final double? sugar = sweet.sugar;
    if (sugar != null && sugar > 0) {
      entries.add(_Entry('Sugar', _g(sugar)));
    }

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: visible ? 1 : 0,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          offset: visible ? Offset.zero : const Offset(0.15, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.80), // 0.2 background
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: onSurface.withOpacity(0.18)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Nutrition',
                          style: TextStyle(
                            color: onSurface, // secondary color
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: onClose,
                          icon: Icon(Icons.close_rounded, color: onSurface),
                          splashRadius: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    if (entries.isEmpty)
                      Text(
                        'No nutrition info',
                        style: TextStyle(color: onSurface.withOpacity(0.7)),
                      )
                    else
                      Wrap(
                        runSpacing: 10,
                        spacing: 16,
                        children: entries
                            .map((e) =>
                                _Tile(label: e.label, value: e.value, onSurface: onSurface))
                            .toList(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _g(double v) {
    final isWhole = v == v.truncateToDouble();
    return '${isWhole ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} g';
  }
}

class _Entry {
  final String label;
  final String value;
  _Entry(this.label, this.value);
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final Color onSurface;
  const _Tile({required this.label, required this.value, required this.onSurface});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: onSurface.withOpacity(0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: onSurface, // secondary color
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
