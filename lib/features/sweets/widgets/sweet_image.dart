import 'dart:math' as math;
import 'package:flutter/material.dart';

class SweetImage extends StatelessWidget {
  final String imageAsset;
  final bool isActive;
  final bool isDetailOpen; // when true (and active), show ~50% by sliding left
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
    final alignment = goHalfLeft ? Alignment.centerLeft : Alignment.center;

    final child = _buildAligned(alignment, goHalfLeft);
    return isActive ? KeyedSubtree(key: hostKey, child: child) : child;
  }

  Widget _buildAligned(Alignment alignment, bool halfOffLeft) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Square image, sized to ~88% of page for breathing room
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

        return SizedBox.expand(
          child: AnimatedAlign(
            alignment: alignment,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: GestureDetector(
              onTap: onTap,
              // In detail mode, shift left by 50% of the square width so only half remains visible.
              child: halfOffLeft
                  ? FractionalTranslation(
                      translation: const Offset(-0.5, 0),
                      child: square,
                    )
                  : square,
            ),
          ),
        );
      },
    );
  }
}
