import 'package:flutter/material.dart';
import '../theme/saree_design_system.dart';

/// Compact reusable Saree brand mark for app bars and account surfaces.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SareeDesignSystem.canary,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(
          color: SareeDesignSystem.cream.withValues(alpha: 0.9),
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.delivery_dining_rounded,
        size: size * 0.72,
        color: SareeDesignSystem.deepGreen,
      ),
    );
  }
}
