import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/services/drive_folder_service.dart';
import 'package:phamijam/services/google_drive_auth_service.dart';
import 'package:phamijam/services/google_drive_service.dart';
import 'package:url_launcher/url_launcher.dart';

enum _ConnectMode { chooser, pastedLink, oauth }

class ConnectDriveFolderPage extends StatefulWidget {
  const ConnectDriveFolderPage({super.key});

  @override
  State<ConnectDriveFolderPage> createState() => _ConnectDriveFolderPageState();
}

class _ConnectDriveFolderPageState extends State<ConnectDriveFolderPage> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  _ConnectMode _mode = _ConnectMode.chooser;
  String? _error;
  bool _exchangingCode = false;
  bool _settingUpFolder = false;

  final TextEditingController _linkController = TextEditingController();
  bool _connectingByLink = false;
  String? _linkError;

  @override
  void initState() {
    super.initState();
    _linkSub = _appLinks.uriLinkStream.listen(_handleIncomingLink);
  }

  void _handleIncomingLink(Uri uri) {
    if (!uri.toString().startsWith(GoogleDriveAuthService.redirectUri)) return;
    _handleRedirect(uri);
  }

  void _startOAuthFlow() {
    setState(() {
      _mode = _ConnectMode.oauth;
      _error = null;
    });
    _openConsentScreen();
  }

  Future<void> _openConsentScreen() async {
    final url = GoogleDriveAuthService.buildAuthorizationUrl();
    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      setState(() => _error = "Couldn't open the browser to sign in.");
    }
  }

  Future<void> _handleRedirect(Uri redirectedUri) async {
    final code = redirectedUri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      final error = redirectedUri.queryParameters['error'];
      if (!mounted) return;
      setState(
        () => _error =
            'Google sign-in was cancelled${error != null ? ': $error' : '.'}',
      );
      return;
    }

    setState(() => _exchangingCode = true);
    final ok = await GoogleDriveAuthService.exchangeCodeForTokens(code);
    final token = GoogleDriveAuthService.accessToken;
    if (!mounted) return;
    if (!ok || token == null || token.isEmpty) {
      setState(() {
        _error = "Couldn't complete Google sign-in.";
        _exchangingCode = false;
      });
      return;
    }

    setState(() {
      _exchangingCode = false;
      _settingUpFolder = true;
    });

    try {
      final folderId = await GoogleDriveService.findOrCreatePhamiJamFolder(
        token,
      );
      await DriveFolderService.setFolderId(folderId, requiresAuth: true);
      if (!mounted) return;
      AppFlushbar.success(context, 'Google Drive folder connected.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _settingUpFolder = false;
        _error = "Couldn't set up your PhamiJam Drive folder: $error";
      });
    }
  }

  Future<void> _connectByLink() async {
    final folderId = DriveFolderService.extractFolderId(_linkController.text);
    if (folderId == null) {
      const message = "That doesn't look like a Drive folder link.";
      setState(() => _linkError = message);
      AppFlushbar.error(context, message);
      return;
    }

    setState(() {
      _connectingByLink = true;
      _linkError = null;
    });

    final accessible = await GoogleDriveService.canAccessFolder(folderId);
    if (!mounted) return;
    if (!accessible) {
      const message =
          'Couldn\'t access that folder. Make sure it\'s shared as '
          '"Anyone with the link".';
      setState(() {
        _connectingByLink = false;
        _linkError = message;
      });
      AppFlushbar.error(context, message);
      return;
    }

    await DriveFolderService.setFolderId(folderId);
    if (!mounted) return;
    AppFlushbar.success(context, 'Google Drive folder connected.');
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _linkController.dispose();
    super.dispose();
  }

  Widget _buildChooser() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_shared_rounded,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Connect a Google Drive folder',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startOAuthFlow,
                icon: const Icon(Icons.add_to_drive_rounded),
                label: const Text('Create a folder for me'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: Text(
                'Let PhamiJam create a folder in your Drive for you, that '
                'you can use to store and play music.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    setState(() => _mode = _ConnectMode.pastedLink),
                icon: const Icon(Icons.link_rounded),
                label: const Text('Insert a share link'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Insert a share link from Google Drive, which lets the app '
                'see the contents of that folder.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPastedLink() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Paste the share link for a folder you've already connected "
            'to PhamiJam, or its folder ID.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _linkController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Drive folder link',
              border: const OutlineInputBorder(),
              errorText: _linkError,
            ),
            onSubmitted: (_) {
              if (!_connectingByLink) _connectByLink();
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _connectingByLink ? null : _connectByLink,
            child: _connectingByLink
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Connect'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _connectingByLink
                ? null
                : () => setState(() {
                    _mode = _ConnectMode.chooser;
                    _linkError = null;
                  }),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildOAuthFlow() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.error),
          ),
        ),
      );
    }

    final message = _settingUpFolder
        ? 'Setting up your PhamiJam folder…'
        : _exchangingCode
        ? 'Finishing sign-in…'
        : 'Continue in your browser, then come back here.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (_mode) {
      _ConnectMode.chooser => _buildChooser(),
      _ConnectMode.pastedLink => _buildPastedLink(),
      _ConnectMode.oauth => _buildOAuthFlow(),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Connect Google Drive folder')),
      body: body,
    );
  }
}
