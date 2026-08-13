import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:provider/provider.dart';

Future<Playlist?> showEditPlaylistSheet(
  BuildContext context,
  Playlist playlist,
) {
  return showModalBottomSheet<Playlist?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _EditPlaylistSheet(playlist: playlist),
  );
}

class _EditPlaylistSheet extends StatefulWidget {
  final Playlist playlist;

  const _EditPlaylistSheet({required this.playlist});

  @override
  State<_EditPlaylistSheet> createState() => _EditPlaylistSheetState();
}

class _EditPlaylistSheetState extends State<_EditPlaylistSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _privacy;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.playlist.title);
    final subtitle = widget.playlist.subtitle;
    final looksLikePlaceholder = RegExp(r'^\d+ videos?$').hasMatch(subtitle);
    _descriptionController = TextEditingController(
      text: looksLikePlaceholder ? '' : subtitle,
    );
    _privacy = widget.playlist.privacyStatus;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _saving = true);
    final library = context.read<LibraryProvider>();
    try {
      final updated = await library.updatePlaylist(
        widget.playlist,
        title: title,
        description: _descriptionController.text.trim(),
        privacyStatus: _privacy == widget.playlist.privacyStatus
            ? null
            : _privacy,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
      AppFlushbar.success(context, 'Playlist updated');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFlushbar.error(context, "Couldn't update playlist: $error");
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canSave = !_saving && _titleController.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit playlist',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Changes are saved to your YouTube account.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Title',
                filled: true,
                fillColor: colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                filled: true,
                fillColor: colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'private',
                  label: Text('Private'),
                  icon: Icon(Icons.lock_rounded),
                ),
                ButtonSegment(
                  value: 'unlisted',
                  label: Text('Unlisted'),
                  icon: Icon(Icons.link_rounded),
                ),
                ButtonSegment(
                  value: 'public',
                  label: Text('Public'),
                  icon: Icon(Icons.public_rounded),
                ),
              ],
              selected: {_privacy},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _privacy = selection.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: colorScheme.surfaceContainerHigh,
                foregroundColor: colorScheme.onSurfaceVariant,
                selectedBackgroundColor: colorScheme.primary,
                selectedForegroundColor: colorScheme.onPrimary,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canSave ? _save : null,
                child: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
