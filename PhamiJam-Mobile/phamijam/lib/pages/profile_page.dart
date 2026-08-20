import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/pages/friends_page.dart';
import 'package:phamijam/pages/settings_page.dart';
import 'package:phamijam/providers/friends_provider.dart';
import 'package:phamijam/providers/profile_grid_provider.dart';
import 'package:phamijam/providers/profile_provider.dart';
import 'package:phamijam/services/profile_service.dart';
import 'package:phamijam/services/share_link_service.dart';
import 'package:phamijam/widgets/profile_grid/profile_grid_view.dart';
import 'package:provider/provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  ProfileGridProvider? _gridProvider;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    context.read<ProfileProvider>().refresh();
  }

  @override
  void dispose() {
    _gridProvider?.dispose();
    super.dispose();
  }

  void _startEdit(ProfileProvider profileProvider) {
    setState(() {
      _gridProvider = ProfileGridProvider(profileProvider.profile.gridLayout);
    });
  }

  void _handleTileLongPress(ProfileProvider profileProvider) {
    if (_gridProvider != null) return;
    HapticFeedback.mediumImpact();
    _startEdit(profileProvider);
  }

  void _cancelEdit() {
    _gridProvider?.dispose();
    setState(() => _gridProvider = null);
  }

  Future<void> _saveEdit() async {
    final gridProvider = _gridProvider;
    if (gridProvider == null) return;
    setState(() => _saving = true);
    try {
      await context.read<ProfileProvider>().saveGridLayout(gridProvider.tiles);
      if (!mounted) return;
      gridProvider.dispose();
      setState(() {
        _gridProvider = null;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFlushbar.error(context, "Couldn't save your layout: $error");
    }
  }

  Future<void> _editInfo(ProfileProvider profileProvider) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditProfileSheet(profileProvider: profileProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final profileProvider = context.watch<ProfileProvider>();
    if (uid == null) return const SizedBox.shrink();

    final gridProvider = _gridProvider;
    final editing = gridProvider != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: editing
            ? [
                TextButton(onPressed: _cancelEdit, child: const Text('Cancel')),
                TextButton(
                  onPressed: _saving ? null : _saveEdit,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Done'),
                ),
              ]
            : [
                _FriendsIconButton(),
                IconButton(
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () => ShareLinkService.shareProfile(
                    context,
                    uid,
                    username: profileProvider.profile.username,
                    subject:
                        '${profileProvider.effectiveDisplayName} on PhamiJam',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_rounded),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                ),
              ],
      ),
      body: RefreshIndicator(
        onRefresh: profileProvider.refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!editing) ...[
                _ProfileHeader(
                  profileProvider: profileProvider,
                  onEdit: () => _editInfo(profileProvider),
                ),
                const SizedBox(height: 20),
              ],
              Text(
                'Your profile',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (!editing && profileProvider.profile.gridLayout.isNotEmpty)
                Text(
                  'Long-press a widget to rearrange',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 8),
              if (!editing && !profileProvider.hasLoadedOnce)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (!editing && profileProvider.profile.gridLayout.isEmpty)
                _EmptyGridHint(onEdit: () => _startEdit(profileProvider))
              else
                ProfileGridView(
                  profileUid: uid,
                  editable: editing,
                  tiles: editing ? null : profileProvider.profile.gridLayout,
                  gridProvider: gridProvider,
                  onTileLongPress: editing
                      ? null
                      : (_) => _handleTileLongPress(profileProvider),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profileProvider, required this.onEdit});

  final ProfileProvider profileProvider;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final profile = profileProvider.profile;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: colorScheme.primary,
            backgroundImage: profileProvider.effectivePhotoUrl != null
                ? NetworkImage(profileProvider.effectivePhotoUrl!)
                : null,
            child: profileProvider.effectivePhotoUrl == null
                ? Icon(
                    Icons.person_rounded,
                    color: colorScheme.onPrimary,
                    size: 30,
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profileProvider.effectiveDisplayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if ((profile.username ?? '').trim().isNotEmpty)
                  Text(
                    '@${profile.username}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                if ((profile.bio ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.bio!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.edit_rounded), onPressed: onEdit),
        ],
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.profileProvider});

  final ProfileProvider profileProvider;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  String? _usernameError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.profileProvider.profile;
    _nameController = TextEditingController(
      text: profile.displayNameOverride ?? '',
    );
    _usernameController = TextEditingController(text: profile.username ?? '');
    _bioController = TextEditingController(text: profile.bio ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _usernameError = null;
    });

    final newUsername = _usernameController.text.trim().toLowerCase();
    final currentUsername = widget.profileProvider.profile.username ?? '';
    if (newUsername.isNotEmpty && newUsername != currentUsername) {
      if (!ProfileService.usernamePattern.hasMatch(newUsername)) {
        setState(() {
          _saving = false;
          _usernameError =
              '3-20 characters: lowercase letters, numbers, underscore. '
              'Must start with a letter.';
        });
        return;
      }
      try {
        await widget.profileProvider.setUsername(newUsername);
      } on UsernameTakenException {
        setState(() {
          _saving = false;
          _usernameError = 'That username is already taken.';
        });
        return;
      } catch (error) {
        setState(() {
          _saving = false;
          _usernameError = "Couldn't save username: $error";
        });
        return;
      }
    }

    try {
      await widget.profileProvider.updateProfile(
        displayNameOverride: _nameController.text.trim(),
        bio: _bioController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        AppFlushbar.error(context, "Couldn't save profile info: $error");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit profile', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Display name'),
            maxLength: 40,
          ),
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: 'Username',
              prefixText: '@',
              helperText:
                  'Optional - gives you a shareable link like '
                  'phamijam-share.workers.dev/u/yourname',
              helperMaxLines: 2,
              errorText: _usernameError,
              errorMaxLines: 2,
            ),
            maxLength: 20,
          ),
          TextField(
            controller: _bioController,
            decoration: const InputDecoration(labelText: 'Bio'),
            maxLength: 120,
            maxLines: 3,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendsIconButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hasPending = context.select<FriendsProvider, bool>(
      (provider) => provider.received.isNotEmpty,
    );
    return IconButton(
      icon: hasPending
          ? const Badge(child: Icon(Icons.people_alt_rounded))
          : const Icon(Icons.people_alt_rounded),
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const FriendsPage())),
    );
  }
}

class _EmptyGridHint extends StatelessWidget {
  const _EmptyGridHint({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your profile is empty',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Tap "Edit layout" to add your bio, featured playlists, and more.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onEdit,
            child: const Text('Edit layout'),
          ),
        ],
      ),
    );
  }
}
