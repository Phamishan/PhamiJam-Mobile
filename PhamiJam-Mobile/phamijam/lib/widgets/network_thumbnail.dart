import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class NetworkThumbnail extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final double iconSize;

  const NetworkThumbnail({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: width,
      height: height,
      color: colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        size: iconSize,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );

    Widget image = url.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url,
            width: width,
            height: height,
            fit: fit,
            placeholder: (context, url) => placeholder,
            errorWidget: (context, url, error) => placeholder,
            fadeInDuration: const Duration(milliseconds: 150),
          );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}
