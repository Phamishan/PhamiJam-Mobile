import 'package:app_links/app_links.dart';
import 'package:phamijam/services/log_service.dart';
import 'package:phamijam/services/share_link_service.dart';

enum DeepLinkType { song, playlist, profile, listenAlong }

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
    if (segments[0] == 'la') {
      return DeepLinkTarget(DeepLinkType.listenAlong, id);
    }
    return null;
  }

  static Future<void> init(void Function(DeepLinkTarget target) onLink) async {
    try {
      final initial = await _appLinks.getInitialLink();
      final target = initial == null ? null : parse(initial);
      if (initial != null) {
        Log.i(
          'deeplink',
          'launched from link (${initial.host}/${initial.pathSegments.firstOrNull ?? ''}) -> '
              '${target?.type.name ?? 'not recognised'}',
        );
      }
      if (target != null) onLink(target);
    } catch (error) {
      Log.e('deeplink', 'reading launch link failed', error);
    }

    _appLinks.uriLinkStream.listen(
      (uri) {
        final target = parse(uri);
        Log.i(
          'deeplink',
          'link received (${uri.host}/${uri.pathSegments.firstOrNull ?? ''}) -> '
              '${target?.type.name ?? 'not recognised'}',
        );
        if (target != null) onLink(target);
      },
      onError: (Object error) {
        Log.e('deeplink', 'link stream error', error);
      },
    );
  }
}
