import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/pages/downloads_page.dart';
import 'package:phamijam/pages/wrapphamied_page.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/providers/theme_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/google_auth_service.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _signingOut = false;

  void _showComingSoon(String feature) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Coming soon'),
        content: Text('$feature isn\'t available yet, but it\'s on the way.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await GoogleAuthService.signOut();
      await FirebaseAuth.instance.signOut();
    } catch (error) {
      if (mounted) {
        AppFlushbar.error(context, 'Failed to sign out: $error');
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: colorScheme.primary,
                      backgroundImage: user?.photoURL != null
                          ? NetworkImage(user!.photoURL!)
                          : null,
                      child: user?.photoURL == null
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
                            user?.displayName ?? 'PhamiJam User',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.email ?? 'Signed in with Google',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _signingOut ? null : _signOut,
                    icon: _signingOut
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          )
                        : const Icon(Icons.logout_rounded, size: 18),
                    label: Text(_signingOut ? 'Signing out...' : 'Sign out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.onSurface,
                      side: BorderSide(
                        color: colorScheme.surfaceContainerHighest,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              return SegmentedButton<AppThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: AppThemeMode.auto,
                    label: Text('Auto'),
                    icon: Icon(Icons.brightness_auto_rounded),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_rounded),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_rounded),
                  ),
                ],
                selected: {themeProvider.mode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    themeProvider.setMode(selection.first),
                style: SegmentedButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainer,
                  foregroundColor: colorScheme.onSurfaceVariant,
                  selectedBackgroundColor: colorScheme.primary,
                  selectedForegroundColor: colorScheme.onPrimary,
                ),
              );
            },
          ),
          const SizedBox(height: 28),
          Text('Player', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              return _SettingsSwitchTile(
                icon: Icons.swipe_rounded,
                title: 'Swipe to dismiss mini player',
                subtitle: 'Swipe the mini player away to stop playback',
                value: settings.miniPlayerSwipeToDismiss,
                onChanged: settings.setMiniPlayerSwipeToDismiss,
              );
            },
          ),
          const SizedBox(height: 10),
          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              return _SettingsSwitchTile(
                icon: Icons.playlist_remove_rounded,
                title: 'Suggest removing skipped songs',
                subtitle:
                    "Get asked to remove a playlist song you've skipped early "
                    'several times',
                value: settings.suggestRemovingSkippedSongs,
                onChanged: settings.setSuggestRemovingSkippedSongs,
              );
            },
          ),
          const SizedBox(height: 28),
          Text('Storage', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Consumer<DownloadsProvider>(
            builder: (context, downloads, _) {
              return _SettingsTile(
                icon: Icons.download_done_rounded,
                title: 'Downloaded Songs',
                subtitle:
                    '${downloads.totalTracks} songs · '
                    '${formatDownloadSize(downloads.totalSizeBytes)}',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DownloadsPage()),
                ),
                color: colorScheme.onSurface,
              );
            },
          ),
          const SizedBox(height: 28),
          Text('App', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _SettingsTile(
            icon: Icons.auto_awesome_rounded,
            title: 'Wrapphamied',
            subtitle: 'Your year in PhamiJam, wrapped',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const WrapphamiedPage())),
            color: colorScheme.onSurface,
          ),
          const SizedBox(height: 10),
          _SettingsTile(
            icon: Icons.folder_rounded,
            title: 'Local Files',
            subtitle: 'Manage folders scanned for local music',
            onTap: () => _showComingSoon('Local Files'),
            color: colorScheme.onSurface,
          ),
          const SizedBox(height: 10),
          _SettingsTile(
            icon: Icons.info_rounded,
            title: 'About PhamiJam',
            subtitle: 'Version 1.0.3',
            color: colorScheme.onSurface,
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.bodyLarge),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.onSurface, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.bodyLarge),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: colorScheme.onPrimary,
                inactiveThumbColor: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
