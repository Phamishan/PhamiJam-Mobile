import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/models/friend_activity_item.dart';
import 'package:phamijam/pages/friend_profile_page.dart';
import 'package:phamijam/providers/friends_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/services/friend_activity_service.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:provider/provider.dart';

class FriendActivityPage extends StatefulWidget {
  const FriendActivityPage({super.key});

  @override
  State<FriendActivityPage> createState() => _FriendActivityPageState();
}

class _FriendActivityPageState extends State<FriendActivityPage> {
  List<FriendActivityItem>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final friends = context.read<FriendsProvider>().friends;
      final items = await FriendActivityService.fetchFeed(friends);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load activity.";
        _loading = false;
      });
    }
  }

  Future<void> _play(BuildContext context, FriendActivityItem item) async {
    try {
      await context.read<PlayerProvider>().playQueue([item.toTrack()]);
    } catch (error) {
      if (mounted) AppFlushbar.error(context, "Couldn't play this song.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(colorScheme),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_loading && _items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              _error!,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    final items = _items ?? const [];
    if (items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              "No recent activity from friends.\nActivity shows up here when "
              "friends listen to music and haven't turned it off.",
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          _FriendActivityTile(item: items[index], onPlay: _play),
    );
  }
}

class _FriendActivityTile extends StatelessWidget {
  const _FriendActivityTile({required this.item, required this.onPlay});

  final FriendActivityItem item;
  final void Function(BuildContext context, FriendActivityItem item) onPlay;

  String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final friend = item.friend;
    final event = item.event;

    return ListTile(
      leading: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FriendProfilePage(uid: friend.uid)),
        ),
        child: CircleAvatar(
          backgroundColor: colorScheme.primary,
          backgroundImage:
              (friend.photoUrl != null && friend.photoUrl!.isNotEmpty)
              ? NetworkImage(friend.photoUrl!)
              : null,
          child: (friend.photoUrl == null || friend.photoUrl!.isEmpty)
              ? Icon(Icons.person_rounded, color: colorScheme.onPrimary)
              : null,
        ),
      ),
      title: Text(
        '${friend.displayName} listened to',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(
        '${event.title}${event.artist.isEmpty ? '' : ' · ${event.artist}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 36,
              height: 36,
              child: NetworkThumbnail(url: event.thumbnailUrl, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _relativeTime(event.startedAt),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      onTap: () => onPlay(context, item),
    );
  }
}
