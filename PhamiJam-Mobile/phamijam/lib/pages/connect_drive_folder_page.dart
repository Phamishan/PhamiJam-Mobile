import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:phamijam/services/drive_folder_service.dart';
import 'package:phamijam/services/google_drive_auth_service.dart';
import 'package:phamijam/services/google_drive_service.dart';
import 'package:url_launcher/url_launcher.dart';

const String _pickerUrl =
    'https://phamijam-share.phamijam.workers.dev/drive-picker';

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
  String? _accessTokenForPicker;

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
      _accessTokenForPicker = token;
    });
  }

  Future<void> _handleFolderPicked(String folderId) async {
    await DriveFolderService.setFolderId(folderId);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _connectByLink() async {
    final folderId = DriveFolderService.extractFolderId(_linkController.text);
    if (folderId == null) {
      setState(
        () => _linkError = "That doesn't look like a Drive folder link.",
      );
      return;
    }

    setState(() {
      _connectingByLink = true;
      _linkError = null;
    });

    final accessible = await GoogleDriveService.canAccessFolder(folderId);
    if (!mounted) return;
    if (!accessible) {
      setState(() {
        _connectingByLink = false;
        _linkError =
            'Couldn\'t access that folder. Make sure it\'s shared as '
            '"Anyone with the link".';
      });
      return;
    }

    await DriveFolderService.setFolderId(folderId);
    if (!mounted) return;
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
            const SizedBox(height: 8),
            Text(
              'Pick a folder from your Drive, or paste a share link if '
              "you've already connected one on another device.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startOAuthFlow,
                icon: const Icon(Icons.add_to_drive_rounded),
                label: const Text('Choose a folder'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    setState(() => _mode = _ConnectMode.pastedLink),
                icon: const Icon(Icons.link_rounded),
                label: const Text('I already have a share link'),
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

    if (_accessTokenForPicker == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _exchangingCode
                    ? 'Finishing sign-in…'
                    : 'Continue in your browser, then come back here.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(
          '$_pickerUrl#token=${Uri.encodeComponent(_accessTokenForPicker!)}',
        ),
      ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'folderPicked',
          callback: (args) {
            final folderId = args.isNotEmpty ? args.first : null;
            if (folderId is String && folderId.isNotEmpty) {
              _handleFolderPicked(folderId);
            }
            return null;
          },
        );
      },
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
