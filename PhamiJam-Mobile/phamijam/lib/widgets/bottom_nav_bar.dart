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

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
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
              for (var i = 0; i < kBottomNavItems.length; i++)
                _NavIcon(
                  icon: kBottomNavItems[i].icon,
                  selected: currentIndex == i,
                  onTap: () => onTap(i),
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
