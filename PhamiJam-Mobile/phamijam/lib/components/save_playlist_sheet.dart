import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/providers/saved_playlists_provider.dart';
import 'package:provider/provider.dart';

Future<void> showSavePlaylistSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => const _SavePlaylistSheet(),
  );
}

class _SavePlaylistSheet extends StatefulWidget {
  const _SavePlaylistSheet();

  @override
  State<_SavePlaylistSheet> createState() => _SavePlaylistSheetState();
}

class _SavePlaylistSheetState extends State<_SavePlaylistSheet> {
  final _linkController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final input = _linkController.text.trim();
    if (input.isEmpty) return;

    setState(() => _saving = true);
    final saved = context.read<SavedPlaylistsProvider>();
    final error = await saved.saveFromInput(input);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      AppFlushbar.success(context, 'Playlist saved');
    } else {
      setState(() => _saving = false);
      AppFlushbar.error(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canSave = !_saving && _linkController.text.trim().isNotEmpty;

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
              'Save a playlist',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _linkController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Playlist link',
                hintText: 'https://www.youtube.com/playlist?list=...',
                filled: true,
                fillColor: colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
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
