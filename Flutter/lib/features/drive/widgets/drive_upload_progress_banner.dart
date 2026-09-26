import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:justus/all_imports.dart';

class DriveUploadProgressBanner extends StatelessWidget {
  const DriveUploadProgressBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<DriveState, bool>(
      selector: (_, s) => s.isUploading,
      builder: (context, isUploading, child) {
        if (!isUploading) return const SizedBox.shrink();

        return Positioned(
          bottom: 100,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.palette.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                  color: context.palette.accentPurple.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: context.palette.shadowStrong,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.palette.accentPurple,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  context.loc.drive_uploading,
                  style: GoogleFonts.plusJakartaSans(
                    color: context.palette.contentPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
