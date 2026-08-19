import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:phamijam/services/share_link_service.dart';

enum DeepLinkType { song, playlist, profile }

class DeepLinkTarget {
  final DeepLinkType type;
  final String id;

  const DeepLinkTarget(this.type, this.id);
}

class DeepLinkService {
  DeepLinkService._();

  static final AppLinks _appLinks = AppLinks();

  static DeepLinkTarget? parse(Uri uri) {
    if (uri.host != shareBaseHost) return null;
    final segments = uri.pathSegments;
    if (segments.length != 2) return null;
    final id = segments[1];
    if (id.isEmpty) return null;
    if (segments[0] == 's') return DeepLinkTarget(DeepLinkType.song, id);
    if (segments[0] == 'p') return DeepLinkTarget(DeepLinkType.playlist, id);
    if (segments[0] == 'u') return DeepLinkTarget(DeepLinkType.profile, id);
    return null;
  }

  static Future<void> init(void Function(DeepLinkTarget target) onLink) async {
    try {
      final initial = await _appLinks.getInitialLink();
      final target = initial == null ? null : parse(initial);
      if (target != null) onLink(target);
    } catch (error) {
      debugPrint('DeepLinkService: getInitialLink failed: $error');
    }

    _appLinks.uriLinkStream.listen(
      (uri) {
        final target = parse(uri);
        if (target != null) onLink(target);
      },
      onError: (Object error) {
        debugPrint('DeepLinkService: uriLinkStream error: $error');
      },
    );
  }
}
