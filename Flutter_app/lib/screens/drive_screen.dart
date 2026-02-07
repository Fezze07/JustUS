// =============================================================================
// DriveScreen - Photo/video gallery with upload
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../state/drive_state.dart';
import 'drive_item_screen.dart';
import '../widgets/drive_grid_item.dart';

class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DriveState>().initialLoad();
    });
  }

  Future<void> _pickFile() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Scatta foto'),
              onTap: () {
                Navigator.pop(context);
                _takePhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Dalla galleria'),
              onTap: () {
                Navigator.pop(context);
                _pickFromGallery();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    final XFile? photo =
        await _imagePicker.pickImage(source: ImageSource.camera);
    if (photo != null) {
      await _uploadFile(photo);
    }
  }

  Future<void> _pickFromGallery() async {
    final XFile? image =
        await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      await _uploadFile(image);
    }
  }

  Future<void> _uploadFile(XFile file) async {
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    context.read<DriveState>().addFileItem(
          bytes,
          file.name,
          bytes.length,
          file.mimeType ?? _getMimeType(file.name),
        );
  }

  String _getMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      _ => 'application/octet-stream',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drive 📂'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickFile,
        child: const Icon(Icons.add),
      ),
      body: Consumer<DriveState>(
        builder: (context, state, _) {
          // Show messages
          if (state.message != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message!)),
              );
              state.clearMessage();
            });
          }

          if (state.isLoading && state.driveItems.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.driveItems.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '📷',
                    style: TextStyle(fontSize: 64),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nessun ricordo ancora',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Aggiungi foto e video!',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                ],
              ),
            );
          }

          return Stack(
            children: [
              RefreshIndicator(
                onRefresh: () => state.initialLoad(),
                child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: state.driveItems.length,
                  itemBuilder: (context, index) {
                    final item = state.driveItems[index];
                    return DriveGridItem(
                      item: item,
                      onTap: () {
                        state.loadSingleItem(item.id);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DriveItemScreen(itemId: item.id),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Upload progress indicator
              if (state.isUploading)
                const Positioned(
                  bottom: 80,
                  left: 16,
                  right: 16,
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Text('Caricamento in corso...'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
