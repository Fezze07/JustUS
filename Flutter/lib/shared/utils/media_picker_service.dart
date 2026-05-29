import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:justus/all_imports.dart';

class MediaPickerService {
  static final _picker = ImagePicker();

  static Future<XFile?> pickImageFromSource(ImageSource source) async {
    return await _picker.pickImage(source: source);
  }

  static Future<XFile?> showPickerSheet(BuildContext context) async {
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
              title: Text('Take Photo', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
              onTap: () async {
                pickedFile = await _picker.pickImage(source: ImageSource.camera);
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.accentAqua),
              title: Text('From Gallery', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
              onTap: () async {
                pickedFile = await _picker.pickImage(source: ImageSource.gallery);
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
