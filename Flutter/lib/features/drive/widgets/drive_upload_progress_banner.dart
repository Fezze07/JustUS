import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:justus/all_imports.dart';

class DriveUploadProgressBanner extends StatelessWidget {
  const DriveUploadProgressBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DriveState>(
      builder: (context, state, child) {
        if (!state.isUploading) return const SizedBox.shrink();

        return Positioned(
          bottom: 100,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E0B36),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.neonPurple.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.neonPurple,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  context.loc.drive_uploading,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
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
