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

    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, bottomInset + 24),
      height: maxHeightFactor != null
          ? MediaQuery.of(context).size.height * maxHeightFactor!
          : null,
      decoration: const BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonPurple,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
            margin: const EdgeInsets.only(bottom: 24),
          ),
          if (title != null) ...[
            Text(
              title!,
              textAlign: TextAlign.center,
              style: VpWidgets.googleFont(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
          ],
          ...children,
        ],
      ),
    );
  }
}