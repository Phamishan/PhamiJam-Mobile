import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/changelog_dialog.dart';
import 'package:phamijam/pages/connect_drive_folder_page.dart';
import 'package:phamijam/pages/downloads_page.dart';
import 'package:phamijam/pages/edited_songs_page.dart';
import 'package:phamijam/pages/manage_playlist_visibility_page.dart';
import 'package:phamijam/pages/jamstats_page.dart';
import 'package:phamijam/providers/edited_songs_provider.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/providers/theme_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/drive_folder_service.dart';
import 'package:phamijam/services/google_auth_service.dart';
import 'package:phamijam/services/google_drive_auth_service.dart';
import 'package:phamijam/theme/app_theme.dart';
import 'package:provider/provider.dart';

const List<Color> _accentColorPresets = [
  Color(0xFFE53935),
  Color(0xFFF4511E),
  Color(0xFF43A047),
  Color(0xFF00897B),
  Color(0xFF1E88E5),
  Color(0xFF5E35B1),
  Color(0xFF8E24AA),
  Color(0xFFD81B60),
];

Color? _parseHexColor(String input) {
  var hex = input.trim().replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return Color(value);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _signingOut = false;

  Widget _buildAccentColorSwatch({
    required Color displayColor,
    required bool selected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: displayColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colorScheme.onSurface : Colors.transparent,
            width: 2,
          ),
        ),
        child: icon != null
            ? Icon(icon, size: 16, color: Colors.white)
            : (selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.white,
                    )
                  : null),
      ),
    );
  }

  Widget _buildAccentColorPicker(ColorScheme colorScheme) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final current = themeProvider.accentColor;
        final isCustom =
            current != null && !_accentColorPresets.contains(current);
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildAccentColorSwatch(
              displayColor: kBrandGold,
              selected: current == null,
              onTap: () => themeProvider.setAccentColor(null),
              colorScheme: colorScheme,
            ),
            for (final preset in _accentColorPresets)
              _buildAccentColorSwatch(
                displayColor: preset,
                selected: current == preset,
                onTap: () => themeProvider.setAccentColor(preset),
                colorScheme: colorScheme,
              ),
            _buildAccentColorSwatch(
              displayColor: isCustom
                  ? current
                  : colorScheme.onSurface.withValues(alpha: 0.12),
              selected: isCustom,
              icon: isCustom ? null : Icons.colorize_rounded,
              onTap: () => _showCustomColorDialog(
                themeProvider,
                isCustom ? current : null,
              ),
              colorScheme: colorScheme,
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCustomColorDialog(
    ThemeProvider themeProvider,
    Color? initial,
  ) async {
    final controller = TextEditingController(
      text: initial != null
          ? '#${initial.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
          : '',
    );
    Color? preview = initial;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colorScheme = Theme.of(context).colorScheme;
            return AlertDialog(
              title: const Text('Custom accent color'),
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: preview ?? colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Hex color',
                        hintText: '#DBA43A',
                      ),
                      onChanged: (value) {
                        setDialogState(() => preview = _parseHexColor(value));
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: preview == null
                      ? null
                      : () {
                          themeProvider.setAccentColor(preview);
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDriveInfo() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Google Drive folder'),
        content: const Text(
          'Connect a folder in your Google Drive to play your own music in '
          "PhamiJam. Drop audio files into that folder using Drive's own "
          'apps, and PhamiJam reads them to build your library.\n\n'
          'There are two ways to connect:\n\n'
          '• Create a folder for me - PhamiJam finds or creates a folder '
          'named "PhamiJam" in your Drive automatically.\n\n'
          '• Insert a share link - paste a link to a folder you already '
          'have, shared as "Anyone with the link".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _connectDriveFolder() async {
    final library = context.read<LibraryProvider>();
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ConnectDriveFolderPage()),
    );
    if (connected == true) {
      await library.refreshLocalFiles();
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await GoogleAuthService.signOut();
      await GoogleDriveAuthService.signOut();
      await DriveFolderService.clearFolderId();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      context.read<LibraryProvider>().clearDriveConnection();
      Navigator.of(context).popUntil((route) => route.isFirst);
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 16),
            Text('Accent color', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 10),
            _buildAccentColorPicker(colorScheme),
            const SizedBox(height: 28),
            Text(
              'Search & Artists',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Choose search results from YouTube Music or YouTube',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Consumer<SettingsProvider>(
              builder: (context, settings, _) {
                return Center(
                  child: SegmentedButton<SearchEngine>(
                    segments: const [
                      ButtonSegment(
                        value: SearchEngine.youtubeMusic,
                        label: Text('YouTube Music'),
                        icon: Icon(Icons.music_note_rounded),
                      ),
                      ButtonSegment(
                        value: SearchEngine.youtube,
                        label: Text('YouTube'),
                        icon: Icon(Icons.smart_display_rounded),
                      ),
                    ],
                    selected: {settings.searchEngine},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        settings.setSearchEngine(selection.first),
                    style: SegmentedButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainer,
                      foregroundColor: colorScheme.onSurfaceVariant,
                      selectedBackgroundColor: colorScheme.primary,
                      selectedForegroundColor: colorScheme.onPrimary,
                    ),
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
            const SizedBox(height: 10),
            Consumer<SettingsProvider>(
              builder: (context, settings, _) {
                return _SettingsSwitchTile(
                  icon: Icons.autorenew_rounded,
                  title: 'Autoplay',
                  subtitle: 'Keep playing similar songs when your queue ends',
                  value: settings.autoplayEnabled,
                  onChanged: settings.setAutoplayEnabled,
                );
              },
            ),
            const SizedBox(height: 28),
            Text('Library', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _SettingsTile(
              icon: Icons.playlist_play_rounded,
              title: 'Playlist Visibility',
              subtitle: 'Choose which playlists show on Home and Library',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ManagePlaylistVisibilityPage(),
                ),
              ),
              color: colorScheme.onSurface,
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
            const SizedBox(height: 10),
            Consumer<EditedSongsProvider>(
              builder: (context, editedSongs, _) {
                return _SettingsTile(
                  icon: Icons.content_cut_rounded,
                  title: 'Edited Songs',
                  subtitle: '${editedSongs.all.length} songs trimmed',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EditedSongsPage()),
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
              title: 'Jamstats ✨',
              subtitle: 'Your year in PhamiJam, wrapped',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const JamstatsPage())),
              color: colorScheme.onSurface,
            ),
            const SizedBox(height: 10),
            Consumer<LibraryProvider>(
              builder: (context, library, _) {
                return _SettingsTile(
                  icon: Icons.add_to_drive_rounded,
                  title: 'Google Drive folder',
                  subtitle: library.hasConnectedDriveFolder
                      ? 'Connected · ${library.localFiles.length} songs'
                      : 'Play songs from a "PhamiJam" folder in your Drive',
                  onTap: _connectDriveFolder,
                  onInfoTap: _showDriveInfo,
                  color: colorScheme.onSurface,
                );
              },
            ),
            const SizedBox(height: 10),
            _SettingsTile(
              icon: Icons.info_rounded,
              title: 'About PhamiJam',
              subtitle: 'Version 1.1.3',
              onTap: () => showChangelogDialog(context),
              color: colorScheme.onSurface,
            ),
            const SizedBox(height: 10),
            _SettingsTile(
              icon: Icons.logout_rounded,
              title: _signingOut ? 'Signing out...' : 'Sign out',
              subtitle: 'Sign out of PhamiJam on this device',
              onTap: _signingOut ? null : _signOut,
              color: colorScheme.error,
            ),
          ],
        ),
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
  final VoidCallback? onInfoTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
    this.onInfoTap,
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
              if (onInfoTap != null)
                IconButton(
                  onPressed: onInfoTap,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.help_outline_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
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
