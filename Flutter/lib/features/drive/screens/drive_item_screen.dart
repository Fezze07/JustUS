// =============================================================================
// DriveItemScreen - Full screen view of a drive item
// =============================================================================

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'package:justus/all_imports.dart';

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
    unawaited(_initMedia());
  }

  Future<void> _initMedia() async {
    final driveState = context.read<DriveState>();
    final item = driveState.singleItem;
    
    if (item == null) {
      return;
    }

    final resolvedUrl = ApiService.resolveProtectedMediaUrl(item.content);
    if (resolvedUrl == null) {
      setState(() {
        _hasError = true;
        _errorMessage = context.loc.drive_invalidMediaUrl;
      });

      return;
    }

    if (item.type == 'video') {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(resolvedUrl),
        httpHeaders: ApiService.authHeaders,
      );
      unawaited(() async {
        try {
          await _videoController!.initialize();
          if (mounted) {
            setState(() => _hasError = false);
          }
        } catch (error) {
          debugPrint("Video Init Error: $error");
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = error.toString();
            });
          }
        }
      }());
      _videoController!.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
    } else if (item.type == 'audio') {
      _setupAudio(resolvedUrl);
    }
  }

  void _setupAudio(String url) {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isAudioPlaying = state == PlayerState.playing);
      }
    });

    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) {
        setState(() => _audioMsgDuration = d);
      }
    });

    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) {
        setState(() => _audioMsgPosition = p);
      }
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
    unawaited(() async {
      try {
        await _audioPlayer.setSourceUrl(url);
      } catch (e) {
        debugPrint("Audio Source Error: $e");
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = e.toString();
          });
        }
      }
    }());
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
    unawaited(_videoController?.dispose());
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  void _showReactionPicker() {
    const emojis = ['❤️', '😍', '🔥', '😂', '😮', '👏', '💯', '🥰'];
    
    unawaited(showModalBottomSheet(
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
                  unawaited(context.read<DriveState>().addReaction(widget.itemId, emoji));
                  Navigator.pop(context);
                },
                child: Text(emoji, style: const TextStyle(fontSize: 40)),
              );
            }).toList(),
          ),
        ),
      ),
    ));
  }

  void _confirmDelete() {
    unawaited(showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc.drive_deleteTitle),
        content: Text(context.loc.drive_deleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.loc.common_cancel),
          ),
          FilledButton(
            onPressed: () {
              unawaited(this.context.read<DriveState>().deleteItem(widget.itemId));
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back
            },
            child: Text(context.loc.common_delete),
          ),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12091D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12091D),
        foregroundColor: Colors.white,
        actions: [
          Selector<DriveState, bool>(
            selector: (_, s) => s.singleItem?.isFavorite == 1,
            builder: (context, isFav, _) {
              final driveState = context.read<DriveState>();
              return Row(
                children: [
                  IconButton(
                    icon: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? Colors.red : Colors.white,
                    ),
                    onPressed: () => unawaited(driveState.toggleFavorite(widget.itemId)),
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
      body: Selector<DriveState, DriveItem?>(
        selector: (_, s) => s.singleItem,
        builder: (context, item, _) {
          if (item == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              Expanded(
                child: Center(
                  child: _buildContent(item),
                ),
              ),
              
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
          child: ProtectedNetworkImage(
            url: item.content,
            fit: BoxFit.contain,
          ),
        );
      
      case 'video':
        if (_hasError) {
          return _buildErrorWidget(context.loc.drive_videoError);
        }
        if (_videoController != null && _videoController!.value.isInitialized) {
          return GestureDetector(
            onTap: () {
              if (_videoController!.value.isPlaying) {
                unawaited(_videoController!.pause());
              } else {
                unawaited(_videoController!.play());
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
          return _buildErrorWidget(context.loc.drive_audioError);
        }
        
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.audiotrack, size: 80, color: Colors.white),
            const SizedBox(height: 24),
            Text(
              item.metadata?['filename'] ?? context.loc.common_audio,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 32),
            IconButton(
              iconSize: 64,
              icon: Icon(
                _isAudioPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                color: Colors.white,
              ),
              onPressed: () => _toggleAudio(
                ApiService.resolveProtectedMediaUrl(item.content) ?? item.content,
              ),
            ),
            if (_audioMsgDuration.inSeconds > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    Slider(
                      value: _audioMsgPosition.inSeconds.toDouble().clamp(0, _audioMsgDuration.inSeconds.toDouble()),
                      max: _audioMsgDuration.inSeconds.toDouble(),
                      onChanged: (v) => unawaited(_audioPlayer.seek(Duration(seconds: v.toInt()))),
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
              item.metadata?['filename'] ?? context.loc.common_file,
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
