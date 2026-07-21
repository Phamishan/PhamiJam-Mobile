class Channel {
  final String id;
  final String name;
  final String thumbnailUrl;
  final String subscriberCount;
  final String description;

  const Channel({
    required this.id,
    required this.name,
    required this.thumbnailUrl,
    this.subscriberCount = '',
    this.description = '',
  });
}
