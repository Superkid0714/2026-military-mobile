import 'dart:async';

import 'package:flutter/material.dart';

import 'components.dart';
import 'maintenance_mascot.dart';

/// Real pending work only. No artificial percentage or minimum waiting time.
class MaintenanceLoading extends StatefulWidget {
  const MaintenanceLoading({
    required this.detail,
    this.immediate = false,
    super.key,
  });
  final String detail;
  final bool immediate;
  @override
  State<MaintenanceLoading> createState() => _MaintenanceLoadingState();
}

class _MaintenanceLoadingState extends State<MaintenanceLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  Timer? revealTimer;
  bool revealed = false;
  @override
  void initState() {
    super.initState();
    revealed = widget.immediate;
    if (!revealed) {
      revealTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted) setState(() => revealed = true);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.stop();
      motion.value = 0;
    } else if (!motion.isAnimating) {
      motion.repeat();
    }
  }

  @override
  void dispose() {
    revealTimer?.cancel();
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: motion,
    builder: (context, _) {
      final visible = revealed || MediaQuery.disableAnimationsOf(context);
      return Opacity(
        opacity: visible ? 1 : 0,
        child: Semantics(
          liveRegion: true,
          label: '정비 중. ${widget.detail}',
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mascot = MaintenanceMascot(phase: motion.value);
                  final words = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '정비 중…',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(widget.detail, style: const TextStyle(color: muted)),
                      const SizedBox(height: 12),
                      const Text(
                        '완료되면 바로 보여드릴게요.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  );
                  return constraints.maxWidth < 340
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [mascot, const SizedBox(height: 12), words],
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            mascot,
                            const SizedBox(width: 20),
                            Flexible(child: words),
                          ],
                        );
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}
