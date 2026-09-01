import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phamijam/pages/friend_profile_page.dart';
import 'package:phamijam/services/profile_service.dart';

class SearchProfilesPage extends StatefulWidget {
  const SearchProfilesPage({super.key});

  @override
  State<SearchProfilesPage> createState() => _SearchProfilesPageState();
}

class _SearchProfilesPageState extends State<SearchProfilesPage> {
  final _controller = TextEditingController();
  List<ProfileSearchResult> _results = const [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(value),
    );
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ProfileService.searchByUsername(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      debugPrint('SearchProfilesPage: search failed: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't search right now: $error";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Search by username',
            border: InputBorder.none,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error ??
                      (_controller.text.trim().isEmpty
                          ? 'Search for a username to find people'
                          : 'No one found'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _error != null
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final result = _results[index];
                final profile = result.profile;
                final displayName =
                    (profile.displayNameOverride?.trim().isNotEmpty ?? false)
                    ? profile.displayNameOverride!.trim()
                    : 'PhamiJam User';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.primary,
                    backgroundImage:
                        (profile.avatarUrl != null &&
                            profile.avatarUrl!.isNotEmpty)
                        ? NetworkImage(profile.avatarUrl!)
                        : null,
                    child:
                        (profile.avatarUrl == null ||
                            profile.avatarUrl!.isEmpty)
                        ? Icon(Icons.person_rounded, color: colorScheme.onPrimary)
                        : null,
                  ),
                  title: Text(displayName),
                  subtitle: (profile.username ?? '').isNotEmpty
                      ? Text('@${profile.username}')
                      : null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FriendProfilePage(uid: result.uid),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
