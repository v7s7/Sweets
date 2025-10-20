import 'dart:math' as math;
import 'package:flutter/material.dart';

class SweetImage extends StatelessWidget {
  final String imageAsset;     // Can be a local asset path OR a full http(s)/data URL (even percent-encoded)
  final bool isActive;
  final bool isDetailOpen;     // When true (and active), slide so exactly 50% is hidden
  final VoidCallback onTap;
  final Key? hostKey;          // Used by the fly-to-cart overlay to locate the widget

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

    // Always center; we handle the left slide by pixels:
    final child = _buildAligned(Alignment.center, goHalfLeft);
    return isActive ? KeyedSubtree(key: hostKey, child: child) : child;
  }

  Widget _buildAligned(Alignment alignment, bool halfOffLeft) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Square hero size (keeps your original breathing room).
        final side = math.min(
          constraints.maxWidth * 0.88,
          constraints.maxHeight * 0.88,
        );

        final square = SizedBox.square(
          dimension: side,
          child: RepaintBoundary(
            child: _smartImage(
              imageAsset,
              fit: BoxFit.contain,
              side: side,
            ),
          ),
        );

        // Slide by HALF OF THE IMAGE WIDTH so exactly 50% becomes hidden.
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

  /// Loads either a network image (Cloudinary) or a local asset.
  /// Safely handles percent-encoded URLs and provides a soft placeholder if loading fails or empty.
  Widget _smartImage(
    String src, {
    required BoxFit fit,
    required double side,
  }) {
    final cleaned = _cleanSrc(src);
    if (cleaned.isEmpty) return _placeholder(side);

    if (_looksLikeNetwork(cleaned)) {
      return Image.network(
        cleaned,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(side),
      );
    }
    return Image.asset(
      cleaned,
      fit: fit,
      errorBuilder: (_, __, ___) => _placeholder(side),
    );
  }

  /// Decode percent-encoding a few times (handles 'https%3A' and 'https%253A')
  String _cleanSrc(String? src) {
    var s = (src ?? '').trim();
    for (var i = 0; i < 3; i++) {
      final before = s;
      try {
        s = Uri.decodeFull(s);
      } catch (_) {
        try {
          s = Uri.decodeComponent(s);
        } catch (_) {
          // stop if decoding fails
        }
      }
      if (s == before) break; // stop when no change
    }
    return s;
  }

  bool _looksLikeNetwork(String s) {
    final lower = s.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('//') ||
        lower.startsWith('data:');
  }

  Widget _placeholder(double side) {
    return Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.pink.withOpacity(0.06),
      ),
      child: const Icon(Icons.image_not_supported_outlined, size: 48),
    );
  }
}
