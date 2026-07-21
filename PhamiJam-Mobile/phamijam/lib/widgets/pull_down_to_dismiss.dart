import 'package:flutter/material.dart';

class PullDownToDismiss extends StatefulWidget {
  final Widget child;

  const PullDownToDismiss({super.key, required this.child});

  @override
  State<PullDownToDismiss> createState() => _PullDownToDismissState();
}

class _PullDownToDismissState extends State<PullDownToDismiss>
    with SingleTickerProviderStateMixin {
  static const double _dismissDistance = 140;
  static const double _dismissVelocity = 700;

  late final AnimationController _snapBackController;
  double _dragExtent = 0;

  @override
  void initState() {
    super.initState();
    _snapBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _snapBackController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_snapBackController.isAnimating) return;
    setState(() {
      _dragExtent = (_dragExtent + details.delta.dy).clamp(
        0.0,
        double.infinity,
      );
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragExtent > _dismissDistance || velocity > _dismissVelocity) {
      Navigator.of(context).maybePop();
      return;
    }
    _snapBack();
  }

  void _onDragCancel() {
    if (!_snapBackController.isAnimating) _snapBack();
  }

  void _snapBack() {
    final animation = Tween<double>(begin: _dragExtent, end: 0).animate(
      CurvedAnimation(parent: _snapBackController, curve: Curves.easeOut),
    );
    void listener() => setState(() => _dragExtent = animation.value);
    animation.addListener(listener);
    _snapBackController.forward(from: 0).whenComplete(() {
      animation.removeListener(listener);
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragExtent / _dismissDistance).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      onVerticalDragCancel: _onDragCancel,
      child: Transform.translate(
        offset: Offset(0, _dragExtent),
        child: Opacity(opacity: 1 - progress * 0.35, child: widget.child),
      ),
    );
  }
}
