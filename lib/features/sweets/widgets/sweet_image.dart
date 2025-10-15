import 'dart:math' as math;
import 'package:flutter/material.dart';

class SweetImage extends StatelessWidget {
  final String imageAsset;
  final bool isActive;
  final bool isDetailOpen; // when true (and active), slide so exactly 50% is hidden
  final VoidCallback onTap;
  final Key? hostKey;

  const SweetImage({
    super.key,
    required this.imageAsset,
    required this.isActive,
    required this.isDetailOpen,
    required this.onTap,
    this.hostKey,
  });

  @override
  Widget build(BuildContext context) {
    final goHalfLeft = isDetailOpen && isActive;

    // Always center; we'll handle the left slide in pixels:
    final child = _buildAligned(Alignment.center, goHalfLeft);
    return isActive ? KeyedSubtree(key: hostKey, child: child) : child;
  }

  Widget _buildAligned(Alignment alignment, bool halfOffLeft) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Square hero size (your breathing room preserved)
        final side = math.min(constraints.maxWidth * 0.88, constraints.maxHeight * 0.88);

        final img = RepaintBoundary(
          child: Image.asset(
            imageAsset,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              width: side,
              height: side,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.pink.withOpacity(0.06),
              ),
              child: const Icon(Icons.image_not_supported_outlined, size: 48),
            ),
          ),
        );

        final square = SizedBox.square(dimension: side, child: img);

        // Slide by HALF OF THE IMAGE WIDTH so exactly 50% of the image becomes hidden.
        final targetDx = halfOffLeft ? -(side / 2) : 0.0;

        return SizedBox.expand(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: targetDx),
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            builder: (context, dx, _) {
              return Transform.translate(
                offset: Offset(dx, 0),
                child: Align(
                  alignment: alignment,
                  child: GestureDetector(onTap: onTap, child: square),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
