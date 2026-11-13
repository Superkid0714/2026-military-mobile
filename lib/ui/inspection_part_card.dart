import 'package:flutter/material.dart';

import '../data/front_inspection.dart';

class InspectionPartCard extends StatelessWidget {
  const InspectionPartCard({
    required this.part,
    required this.status,
    required this.onTap,
    this.selected = false,
    this.progress,
    super.key,
  });

  final FrontPart part;
  final String status;
  final VoidCallback onTap;
  final bool selected;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final attention = ['이상 의심', '확인 요청됨', '추가 확인'].contains(status);
    final done = status == '점검 완료';
    final running = status == '점검 중';
    final color = attention
        ? const Color(0xFF925200)
        : done
        ? const Color(0xFF16734D)
        : running
        ? const Color(0xFF126F80)
        : const Color(0xFF63716B);
    final icon = switch (part) {
      FrontPart.battery => Icons.battery_charging_full,
      FrontPart.coolantTank => Icons.water_drop_outlined,
      FrontPart.airCleaner => Icons.air,
      FrontPart.oilDipstick => Icons.oil_barrel_outlined,
      FrontPart.leftLamp || FrontPart.rightLamp => Icons.lightbulb_outline,
      _ => Icons.car_repair,
    };
    final description = switch (part) {
      FrontPart.battery => '단자 · 체결부 · 부식 흔적',
      FrontPart.coolantTank => '탱크 외관 · 연결 호스',
      FrontPart.airCleaner => '하우징 · 흡기 연결부',
      FrontPart.oilDipstick => '게이지 위치 · 주변 오염',
      FrontPart.leftLamp || FrontPart.rightLamp => '렌즈 · 외관 상태',
      FrontPart.hood => '패널 · 체결부',
      FrontPart.grille => '흡기부 · 외관 상태',
      FrontPart.bumper => '범퍼 · 체결부',
    };
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: attention
              ? const Color(0xFFFFF6E7)
              : selected
              ? const Color(0xFFF0F7F3)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected || running || attention
                ? color
                : const Color(0xFFDFE7E2),
            width: selected || running ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          part.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF63716B),
                    ),
                  ),
                  if (running) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      color: color,
                      backgroundColor: const Color(0xFFDDEAE7),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
