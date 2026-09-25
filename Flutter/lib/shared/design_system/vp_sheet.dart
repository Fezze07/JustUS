import 'package:flutter/material.dart';

import 'package:justus/all_imports.dart';

/// Shared bottom-sheet container: frosted card, drag handle, optional title.
///
/// Children are flattened into the sheet's own column on purpose: flexible
/// children (e.g. Expanded) must stay direct children of the fixed-height
/// container column so modal-route intrinsic measurements don't hit an
/// unbounded-height flex (see todo 6.2 / F-DS15).
class VPSheet extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final double? maxHeightFactor;

  const VPSheet({
    super.key,
    this.title,
    required this.children,
    this.maxHeightFactor,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: AppColors.neonPurple,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      // The sheet owns its own `Material` so that Material-based children
      // (ListTile, InkWell) paint their ink on the sheet surface. Without it
      // they would paint on the modal route's Material hidden behind the
      // sheet's background, and in debug mode ListTile asserts with
      // "ListTile background color or ink splashes may be invisible".
      child: Material(
        color: AppColors.cardDark,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            bottomInset + AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: AppDims.circleButton,
                height: AppSpacing.xs,
                decoration: BoxDecoration(
                  color: AppColors.surfaceTrack,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              ),
              if (title != null) ...[
                Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: VpWidgets.googleFont(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.contentPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
