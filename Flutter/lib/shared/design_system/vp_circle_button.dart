import 'package:flutter/material.dart';

class VPCircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isFill;
  final double size;
  final bool hasShadow;

  const VPCircleButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isFill = false,
    this.size = 24,
    this.hasShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: color,
            size: size,
            fill: isFill ? 1.0 : 0.0,
            shadows: hasShadow ? [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ] : null,
          ),
        ),
      ),
    );
  }
}
