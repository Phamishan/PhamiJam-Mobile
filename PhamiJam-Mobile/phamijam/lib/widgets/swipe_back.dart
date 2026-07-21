import 'package:flutter/material.dart';

class SwipeBack extends StatefulWidget {
  final Widget child;

  const SwipeBack({super.key, required this.child});

  @override
  State<SwipeBack> createState() => _SwipeBackState();
}

class _SwipeBackState extends State<SwipeBack> {
  static const double _maxGlowExtent = 120;
  static const double _edgeWidth = 24;

  double _dragExtent = 0;

  void _onDragUpdate(DragUpdateDetails details) {
    final next = (_dragExtent + details.delta.dx).clamp(0.0, _maxGlowExtent);
    if (next != _dragExtent) setState(() => _dragExtent = next);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    setState(() => _dragExtent = 0);
    if (velocity > 250) {
      Navigator.of(context).maybePop();
    }
  }

  void _onDragCancel() {
    setState(() => _dragExtent = 0);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final progress = _dragExtent / _maxGlowExtent;

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _edgeWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onHorizontalDragCancel: _onDragCancel,
          ),
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: progress,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      primary.withValues(alpha: 0.45),
                      primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
