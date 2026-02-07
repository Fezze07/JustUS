// =============================================================================
// DriveItemScreen - Full screen view of a drive item
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import '../state/drive_state.dart';
import '../models/models.dart';

class DriveItemScreen extends StatefulWidget {
  final int itemId;

  const DriveItemScreen({super.key, required this.itemId});

  @override
  State<DriveItemScreen> createState() => _DriveItemScreenState();
}

class _DriveItemScreenState extends State<DriveItemScreen> {
  // Video handles
  VideoPlayerController? _videoController;
  
  // Audio handles
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioPlaying = false;
  Duration _audioMsgDuration = Duration.zero;
  Duration _audioMsgPosition = Duration.zero;

  // General state
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initMedia();
  }

  void _initMedia() {
    final driveState = context.read<DriveState>();
    final item = driveState.singleItem;
    
    if (item == null) return;

    final String encodedUrl = Uri.encodeFull(item.content);

    if (item.type == 'video') {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(encodedUrl));
      _videoController!.initialize().then((_) {
        if (mounted) setState(() => _hasError = false);
      }).catchError((error) {
        debugPrint("Video Init Error: $error");
        if (mounted) setState(() {
          _hasError = true;
          _errorMessage = error.toString();
        });
      });
      _videoController!.addListener(() {
        if (mounted) setState(() {});
      });
    } else if (item.type == 'audio') {
      _setupAudio(encodedUrl);
    }
  }

  void _setupAudio(String url) {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isAudioPlaying = state == PlayerState.playing);
      }
    });

    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _audioMsgDuration = d);
    });

    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _audioMsgPosition = p);
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isAudioPlaying = false;
          _audioMsgPosition = Duration.zero;
        });
      }
    });

    // Attempt to set source immediately
    _audioPlayer.setSourceUrl(url).catchError((e) {
      debugPrint("Audio Source Error: $e");
      if (mounted) setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    });
  }

  Future<void> _toggleAudio(String url) async {
    try {
      if (_isAudioPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_audioPlayer.state == PlayerState.paused || _audioPlayer.state == PlayerState.completed) {
          await _audioPlayer.resume();
        } else {
          await _audioPlayer.play(UrlSource(url));
        }
      }
    } catch (e) {
      debugPrint("Audio Player Error: $e");
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _showReactionPicker() {
    const emojis = ['❤️', '😍', '🔥', '😂', '😮', '👏', '💯', '🥰'];
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: emojis.map((emoji) {
              return InkWell(
                onTap: () {
                  context.read<DriveState>().addReaction(widget.itemId, emoji);
                  Navigator.pop(context);
                },
                child: Text(emoji, style: const TextStyle(fontSize: 40)),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina'),
        content: const Text('Vuoi eliminare questo elemento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              this.context.read<DriveState>().deleteItem(widget.itemId);
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back
            },
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          Consumer<DriveState>(
            builder: (context, state, _) {
              final item = state.singleItem;
              if (item == null) return const SizedBox();
              
              return Row(
                children: [
                  IconButton(
                    icon: Icon(
                      item.isFavorite == 1 ? Icons.favorite : Icons.favorite_border,
                      color: item.isFavorite == 1 ? Colors.red : Colors.white,
                    ),
                    onPressed: () => state.toggleFavorite(widget.itemId),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_reaction_outlined),
                    onPressed: _showReactionPicker,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _confirmDelete,
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<DriveState>(
        builder: (context, state, _) {
          final item = state.singleItem;
          
          if (item == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              // Content
              Expanded(
                child: Center(
                  child: _buildContent(item),
                ),
              ),
              
              // Reactions
              if (item.reactions.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    children: item.reactions.map((emoji) {
                      return Chip(label: Text(emoji));
                    }).toList(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(DriveItem item) {
    switch (item.type) {
      case 'image':
        return InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: item.content,
            fit: BoxFit.contain,
            placeholder: (_, __) => const CircularProgressIndicator(),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 64),
          ),
        );
      
      case 'video':
        if (_hasError) {
          return _buildErrorWidget("Errore video");
        }
        if (_videoController != null && _videoController!.value.isInitialized) {
          return GestureDetector(
            onTap: () {
              if (_videoController!.value.isPlaying) {
                _videoController!.pause();
              } else {
                _videoController!.play();
              }
              setState(() {});
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
                if (!_videoController!.value.isPlaying)
                  const Icon(Icons.play_circle, size: 80, color: Colors.white70),
              ],
            ),
          );
        }
        return const CircularProgressIndicator();
      
      case 'audio':
        if (_hasError) {
          return _buildErrorWidget("Errore audio");
        }
        
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.audiotrack, size: 80, color: Colors.white),
            const SizedBox(height: 24),
            Text(
              item.metadata?['filename'] ?? 'Audio',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 32),
            IconButton(
              iconSize: 64,
              icon: Icon(
                _isAudioPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                color: Colors.white,
              ),
              onPressed: () => _toggleAudio(Uri.encodeFull(item.content)),
            ),
            if (_audioMsgDuration.inSeconds > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    Slider(
                      value: _audioMsgPosition.inSeconds.toDouble().clamp(0, _audioMsgDuration.inSeconds.toDouble()),
                      max: _audioMsgDuration.inSeconds.toDouble(),
                      onChanged: (v) => _audioPlayer.seek(Duration(seconds: v.toInt())),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_audioMsgPosition), style: const TextStyle(color: Colors.grey)),
                        Text(_formatDuration(_audioMsgDuration), style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      
      default:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.insert_drive_file, size: 100, color: Colors.white),
            const SizedBox(height: 16),
            Text(
              item.metadata?['filename'] ?? 'File',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        );
    }
  }

  Widget _buildErrorWidget(String title) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 80, color: Colors.red),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(color: Colors.white)),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(_errorMessage!, style: const TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
          ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
