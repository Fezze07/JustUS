import 'package:flutter/material.dart';

import 'package:justus/all_imports.dart';

class VPCircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isFill;
  final double size;
  final bool hasShadow;
  final String? tooltip;

  const VPCircleButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isFill = false,
    this.size = 24,
    this.hasShadow = true,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          width: AppDims.circleButton,
          height: AppDims.circleButton,
          decoration: BoxDecoration(
            color: context.palette.overlay,
            shape: BoxShape.circle,
            border: Border.all(
              color: context.palette.border,
            ),
          ),
          child: Center(
            child: Icon(
              icon,
              color: color,
              size: size,
              fill: isFill ? 1.0 : 0.0,
              shadows: hasShadow
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
