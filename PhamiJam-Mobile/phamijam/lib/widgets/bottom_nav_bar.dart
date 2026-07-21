import 'package:flutter/material.dart';

class BottomNavItem {
  final IconData icon;
  const BottomNavItem(this.icon);
}

const List<BottomNavItem> kBottomNavItems = [
  BottomNavItem(Icons.home_rounded),
  BottomNavItem(Icons.search_rounded),
  BottomNavItem(Icons.library_music_rounded),
  BottomNavItem(Icons.person_rounded),
];

class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool searchMode;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClose;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.searchMode,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onSearchClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: colorScheme.surfaceContainerHighest, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              _NavIcon(
                icon: kBottomNavItems[0].icon,
                selected: !searchMode && currentIndex == 0,
                onTap: () => onTap(0),
              ),
              Expanded(
                flex: 3,
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        sizeFactor: animation,
                        axis: Axis.horizontal,
                        alignment: const Alignment(-1, -1),
                        child: child,
                      ),
                    ),
                    child: searchMode
                        ? _SearchField(
                            key: const ValueKey('search-field'),
                            controller: searchController,
                            focusNode: searchFocusNode,
                            onChanged: onSearchChanged,
                            onClose: onSearchClose,
                          )
                        : Row(
                            key: const ValueKey('nav-icons'),
                            children: [
                              for (var i = 1; i < kBottomNavItems.length; i++)
                                _NavIcon(
                                  icon: kBottomNavItems[i].icon,
                                  selected: currentIndex == i,
                                  onTap: () => onTap(i),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(icon, size: 32, color: color)],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const _SearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              Icons.search_rounded,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlignVertical: TextAlignVertical.center,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search',
                ),
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              splashRadius: 16,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: onClose,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
