import 'package:flutter/material.dart';

/// Short tool strokes with a pause. The body never rocks or floats.
double maintenanceWorkAngle(double phase) {
  double ease(double x) => Curves.easeInOutSine.transform(x.clamp(0.0, 1.0));
  if (phase < .18) return 0;
  if (phase < .42) return -.13 * ease((phase - .18) / .24);
  if (phase < .50) return -.13;
  if (phase < .70) return -.13 + .13 * ease((phase - .50) / .20);
  if (phase < .82) return -.055 * ease((phase - .70) / .12);
  if (phase < .94) return -.055 + .055 * ease((phase - .82) / .12);
  return 0;
}

class MaintenanceMascot extends StatelessWidget {
  const MaintenanceMascot({required this.phase, super.key});
  final double phase;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 144,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Image.asset(
          'assets/branding/jungbion-worker-body.png',
          key: const ValueKey('maintenance-static-body'),
          width: 144,
          height: 144,
          cacheWidth: 432,
          excludeFromSemantics: true,
        ),
        Transform.rotate(
          key: const ValueKey('maintenance-mascot-tilt'),
          angle: maintenanceWorkAngle(phase),
          // Forearm cuff attachment in the full aligned source canvas.
          alignment: const Alignment(-.44, .75),
          child: Image.asset(
            'assets/branding/jungbion-worker-arm.png',
            width: 144,
            height: 144,
            cacheWidth: 432,
            excludeFromSemantics: true,
          ),
        ),
      ],
    ),
  );
}
