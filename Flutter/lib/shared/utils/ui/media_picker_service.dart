import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:justus/all_imports.dart';

class MediaPickerService {
  static final _picker = ImagePicker();

  static Future<XFile?> pickImageFromSource(ImageSource source) async {
    return await _picker.pickImage(source: source);
  }

  static Future<XFile?> pickFileWith(FileType type,
      {List<String>? allowedExtensions}) async {
    try {
      final file = await FilePicker.pickFile(
        type: type,
        allowedExtensions: allowedExtensions,
      );

      if (file == null || file.path == null) return null;

      return XFile(file.path!, mimeType: _mimeFromName(file.name));
    } catch (e) {
      return null;
    }
  }

  static String _mimeFromName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    const map = {
      'pdf': 'application/pdf',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'ogg': 'audio/ogg',
      'wav': 'audio/wav',
      'aac': 'audio/aac',
      'flac': 'audio/flac',
    };

    return map[ext] ?? 'application/octet-stream';
  }

  static Future<XFile?> showPickerSheet(
    BuildContext context, {
    double? maxWidth,
    double? maxHeight,
  }) async {
    XFile? pickedFile;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.deepViolet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.neonPurple),
              title: Text(context.loc.drive_takePhoto, style: GoogleFonts.plusJakartaSans(color: Colors.white)),
              onTap: () async {
                pickedFile = await _picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: maxWidth,
                  maxHeight: maxHeight,
                );
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.accentAqua),
              title: Text(context.loc.drive_fromGallery, style: GoogleFonts.plusJakartaSans(color: Colors.white)),
              onTap: () async {
                pickedFile = await _picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: maxWidth,
                  maxHeight: maxHeight,
                );
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.library_music, color: AppColors.neonPurple),
              title: Text(context.loc.drive_fromAudio, style: GoogleFonts.plusJakartaSans(color: Colors.white)),
              onTap: () async {
                pickedFile = await pickFileWith(FileType.audio);
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.description, color: AppColors.accentAqua),
              title: Text(context.loc.drive_fromDocuments, style: GoogleFonts.plusJakartaSans(color: Colors.white)),
              onTap: () async {
                pickedFile =
                    await pickFileWith(FileType.custom, allowedExtensions: ['pdf']);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );

    return pickedFile;
  }
}
