import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'components.dart';

class MaintenanceBreakdown extends StatelessWidget {
  const MaintenanceBreakdown(this.values, {super.key});

  final Map<String, num> values;

  static const colors = [
    green,
    Color(0xFF437CC8),
    Color(0xFFD48A37),
    Color(0xFF8A68BC),
    Color(0xFF2B98A8),
    Color(0xFFC35D76),
    Color(0xFF789A49),
    Color(0xFF78899F),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<num>(0, (sum, entry) => sum + entry.value);
    if (total == 0) return empty('해당 기간의 기록이 없습니다.');
    return Column(
      children: [
        SizedBox.square(
          dimension: 148,
          child: CustomPaint(
            painter: _BreakdownPainter([
              for (final entry in entries) entry.value / total,
            ]),
            child: Center(
              child: Text(
                '${number(total)}건',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final (index, entry) in entries.indexed)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '● ',
                      style: TextStyle(color: colors[index % colors.length]),
                    ),
                    TextSpan(text: '${entry.key} ${number(entry.value)}건'),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BreakdownPainter extends CustomPainter {
  const _BreakdownPainter(this.shares);

  final List<double> shares;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(13);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20;
    var start = -math.pi / 2;
    for (final (index, share) in shares.indexed) {
      final sweep = share * math.pi * 2;
      final gap = shares.length == 1 ? 0.0 : math.min(sweep * .35, .055);
      stroke.color = MaintenanceBreakdown
          .colors[index % MaintenanceBreakdown.colors.length];
      canvas.drawArc(bounds, start + gap / 2, sweep - gap, false, stroke);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_BreakdownPainter oldDelegate) =>
      !listEquals(shares, oldDelegate.shares);
}

class MaintenanceTrend extends StatelessWidget {
  const MaintenanceTrend(this.values, {super.key});

  final Map<String, num> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return empty('해당 기간의 기록이 없습니다.');
    final entries = values.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = math.max(
          MediaQuery.textScalerOf(context).scale(12) > 16 ? 92.0 : 74.0,
          constraints.maxWidth / entries.length,
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: columnWidth * entries.length,
            child: Column(
              children: [
                SizedBox(
                  height: 148,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _TrendPainter(
                      entries.map((entry) => entry.value).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final entry in entries)
                      SizedBox(
                        width: columnWidth,
                        child: Column(
                          children: [
                            Text(
                              '${number(entry.value)}건',
                              style: const TextStyle(
                                color: green,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              entry.key,
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.counts);

  final List<num> counts;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 12.0;
    final bottom = size.height - 8;
    final maxCount = counts.fold<num>(1, math.max);
    final step = size.width / counts.length;
    final points = [
      for (final (index, count) in counts.indexed)
        Offset(step * (index + .5), bottom - (bottom - top) * count / maxCount),
    ];
    final grid = Paint()..color = line;
    for (var i = 0; i <= 4; i++) {
      final y = top + (bottom - top) * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final trace = Path()..addPolygon(points, false);
    if (points.length > 1) {
      final fill = Path.from(trace)
        ..lineTo(points.last.dx, bottom)
        ..lineTo(points.first.dx, bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              green.withValues(alpha: .22),
              green.withValues(alpha: .02),
            ],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        trace,
        Paint()
          ..color = green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round,
      );
    }
    for (final point in points) {
      canvas.drawCircle(point, 5.5, Paint()..color = green);
      canvas.drawCircle(point, 2.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      !listEquals(counts, oldDelegate.counts);
}
