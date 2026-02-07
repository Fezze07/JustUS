// =============================================================================
// ProfileScreen - User and partner profile display
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../state/profile_state.dart';
import '../state/auth_state.dart';
import 'change_password_screen.dart';
import 'login_screen.dart';

import '../models/models.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _imagePicker = ImagePicker();
  final _bioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<ProfileState>().loadProfile();
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }
  
  String? _resolveUrl(String? url) {
    if (url == null) return null;
    if (url.startsWith('http')) return url;
    return '${ApiService.baseUrl}$url';
  }

  Future<void> _pickProfilePhoto() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );

    if (image != null) {
      final bytes = await image.readAsBytes();
      if (!mounted) return;

      context.read<ProfileState>().uploadProfilePhoto(
            bytes,
            image.name,
            image.mimeType ?? 'image/jpeg',
          );
    }
  }

  void _showEditBioDialog() {
    final profileState = context.read<ProfileState>();
    _bioController.text = profileState.userProfile?.bio ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifica bio'),
        content: TextField(
          controller: _bioController,
          decoration: const InputDecoration(
            hintText: 'Scrivi qualcosa su di te...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              profileState.updateBio(_bioController.text);
              Navigator.pop(context);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Vuoi uscire dall\'account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () async {
              await this.context.read<AuthState>().logout();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                this.context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Esci'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilo'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Consumer<ProfileState>(
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

          if (state.isLoading && state.userProfile == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final user = state.userProfile;
          final partner = state.partnerProfile;
          final userPicUrl = _resolveUrl(user?.profilePicUrl);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // User profile section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Avatar
                        GestureDetector(
                          onTap: _pickProfilePhoto,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundImage: userPicUrl != null
                                    ? CachedNetworkImageProvider(userPicUrl)
                                    : null,
                                child: user?.profilePicUrl == null
                                    ? const Icon(Icons.person, size: 50)
                                    : null,
                              ),
                              if (state.isUploading)
                                const Positioned.fill(
                                  child: CircleAvatar(
                                    radius: 50,
                                    backgroundColor: Colors.black45,
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundColor:
                                      Theme.of(context).primaryColor,
                                  child: const Icon(Icons.camera_alt,
                                      size: 16, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Name and code
                        Text(
                          user?.username ?? 'Username',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          '#${user?.code ?? '0000'}',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Colors.grey,
                                  ),
                        ),
                        if (user?.email != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            user!.email!,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Colors.grey,
                                ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Bio
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                user?.bio ?? 'Nessuna bio',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontStyle: user?.bio == null
                                          ? FontStyle.italic
                                          : null,
                                      color: user?.bio == null
                                          ? Colors.grey
                                          : null,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: _showEditBioDialog,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Partner section
                if (partner != null)
                 _buildPartnerSection(context, partner),

                const SizedBox(height: 24),

                // Actions
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Cambia password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ChangePasswordScreen()),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPartnerSection(BuildContext context, User partner) {
    final partnerPicUrl = _resolveUrl(partner.profilePicUrl);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Il tuo partner 💕',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: partnerPicUrl != null
                      ? CachedNetworkImageProvider(partnerPicUrl)
                      : null,
                  child: partner.profilePicUrl == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.username,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '#${partner.code}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
