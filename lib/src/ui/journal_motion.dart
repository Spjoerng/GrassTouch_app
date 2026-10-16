import 'package:flutter/material.dart';

Duration journalMotionDuration(BuildContext context, [int milliseconds = 220]) {
  final media = MediaQuery.maybeOf(context);
  return media?.disableAnimations == true || media?.accessibleNavigation == true
      ? Duration.zero
      : Duration(milliseconds: milliseconds);
}

/// A finite entrance for content, without changing its layout or scroll offset.
class JournalReveal extends StatefulWidget {
  const JournalReveal({super.key, required this.child});
  final Widget child;

  @override
  State<JournalReveal> createState() => _JournalRevealState();
}

class _JournalRevealState extends State<JournalReveal>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(vsync: this);
  late final progress = CurvedAnimation(
    parent: controller,
    curve: Curves.easeOutCubic,
  );
  bool started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = journalMotionDuration(context);
    controller.duration = duration;
    if (duration == Duration.zero) {
      controller.value = 1;
    } else if (!started) {
      controller.forward();
    }
    started = true;
  }

  @override
  void dispose() {
    progress.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: progress,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, .025),
        end: Offset.zero,
      ).animate(progress),
      child: widget.child,
    ),
  );
}

class JournalEmptyIcon extends StatelessWidget {
  const JournalEmptyIcon(this.icon, {super.key});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 80,
    height: 80,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
  );
}
