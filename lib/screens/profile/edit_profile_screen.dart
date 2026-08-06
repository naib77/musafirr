import 'package:flutter/material.dart';

import '../../services/image_upload_service.dart';
import '../../state/auth_state.dart';
import '../../widgets/modern_banner.dart';

/// Lets a signed-in user edit their personal information: display name, bio, and
/// profile photo. Phone (the verified login identity) is shown read-only.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.authState});

  final AuthStateNotifier authState;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _phoneController;
  String? _avatarUrl;
  bool _uploadingAvatar = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.authState.currentUser;
    _nameController = TextEditingController(text: user?.name ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
    _phoneController = TextEditingController(
      text: (user?.phone?.trim().isNotEmpty ?? false) ? user!.phone! : '—',
    );
    _avatarUrl = user?.avatarUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _changePhoto() async {
    final user = widget.authState.currentUser;
    if (user == null) return;
    final picked = await ImageUploadService.instance.pickImageFromGallery();
    if (picked == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    final result = await ImageUploadService.instance.uploadAvatar(
      image: picked,
      userId: user.id,
    );
    if (!mounted) return;
    setState(() => _uploadingAvatar = false);
    if (!result.success || result.publicUrl == null) {
      ModernBanner.showError(context, 'Could not upload photo. Please try again.');
      return;
    }
    // Cache-bust so the CDN doesn't keep serving the previous image (same path).
    final busted =
        '${result.publicUrl!}?v=${DateTime.now().millisecondsSinceEpoch}';
    setState(() => _avatarUrl = busted);
  }

  Future<void> _save() async {
    final user = widget.authState.currentUser;
    if (user == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ModernBanner.showError(context, 'Please enter your name.');
      return;
    }

    setState(() => _saving = true);
    widget.authState.updateUser(user.copyWith(
      name: name,
      bio: _bioController.text.trim(),
      avatarUrl: _avatarUrl,
    ));
    // updateUser is fire-and-forget on the state; give it a beat, then close.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    setState(() => _saving = false);
    ModernBanner.showSuccess(context, 'Profile updated');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal information'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundImage:
                      _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                  child: _avatarUrl == null
                      ? const Icon(Icons.person, size: 48)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.primary,
                    child: _uploadingAvatar
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            icon: const Icon(Icons.camera_alt,
                                color: Colors.white),
                            onPressed: _changePhoto,
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bioController,
            maxLines: 4,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Bio',
              hintText: 'Tell hosts/guests a little about yourself',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Phone',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your phone number is your login and can\'t be changed here.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
