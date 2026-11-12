import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/front_inspection.dart';
import '../data/store.dart';

const scanAccent = Color(0xFF78F0B2);
const scanBackground = Color(0xFF16342E);

Map<FrontPart, FrontObservation> latestInspectionParts(
  Iterable<Inspection> sessions,
) {
  final sorted = sessions.toList()
    ..sort((a, b) => b.created.compareTo(a.created));
  final latest = <FrontPart, FrontObservation>{};
  for (final session in sorted) {
    for (final entry in session.front.entries) {
      latest.putIfAbsent(entry.key, () => entry.value);
    }
  }
  return latest;
}

class InspectionDiagram extends StatelessWidget {
  const InspectionDiagram({
    required this.area,
    required this.observations,
    this.selected,
    super.key,
  });

  final FrontInspectionArea area;
  final Map<FrontPart, FrontObservation> observations;
  final FrontPart? selected;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '${area.label} 부위 안내도',
    child: AspectRatio(
      aspectRatio: 320 / 170,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _InspectionDiagramPainter(area, observations, selected),
        ),
      ),
    ),
  );
}

class _InspectionDiagramPainter extends CustomPainter {
  const _InspectionDiagramPainter(this.area, this.observations, this.selected);

  final FrontInspectionArea area;
  final Map<FrontPart, FrontObservation> observations;
  final FrontPart? selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(scanBackground, BlendMode.src);
    canvas.save();
    canvas.scale(size.width / 320, size.height / 170);
    final grid = Paint()..color = const Color(0xFF2D5148);
    for (var x = 0.0; x < 320; x += 16) {
      canvas.drawLine(Offset(x, 0), Offset(x, 170), grid);
    }
    for (var y = 0.0; y < 170; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(320, y), grid);
    }
    final body = Paint()
      ..color = const Color(0xFFA6D8C2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    void box(double x, double y, double w, double h, [double radius = 7]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          Radius.circular(radius),
        ),
        body,
      );
    }

    final Map<FrontPart, Offset> points;
    if (area == FrontInspectionArea.engineBay) {
      box(62, 19, 196, 132, 23);
      box(76, 29, 168, 106, 15);
      box(86, 45, 38, 31);
      box(188, 44, 42, 33);
      box(130, 42, 54, 62, 10);
      box(86, 94, 32, 28, 12);
      box(196, 95, 25, 24, 12);
      canvas.drawLine(const Offset(85, 138), const Offset(235, 138), body);
      points = const {
        FrontPart.battery: Offset(104, 60),
        FrontPart.coolantTank: Offset(102, 109),
        FrontPart.airCleaner: Offset(209, 60),
        FrontPart.oilDipstick: Offset(208, 107),
      };
    } else {
      final outline = Path()
        ..moveTo(58, 128)
        ..lineTo(58, 81)
        ..quadraticBezierTo(58, 68, 81, 61)
        ..lineTo(101, 28)
        ..quadraticBezierTo(160, 13, 219, 28)
        ..lineTo(239, 61)
        ..quadraticBezierTo(262, 68, 262, 81)
        ..lineTo(262, 128)
        ..quadraticBezierTo(257, 144, 242, 145)
        ..lineTo(78, 145)
        ..quadraticBezierTo(63, 144, 58, 128)
        ..close();
      canvas.drawPath(outline, body);
      canvas.drawLine(const Offset(82, 61), const Offset(238, 61), body);
      box(66, 76, 48, 21);
      box(206, 76, 48, 21);
      box(119, 75, 82, 37, 5);
      box(73, 120, 174, 16, 5);
      points = const {
        FrontPart.hood: Offset(160, 55),
        FrontPart.rightLamp: Offset(90, 86),
        FrontPart.grille: Offset(160, 93),
        FrontPart.leftLamp: Offset(230, 86),
        FrontPart.bumper: Offset(160, 128),
      };
    }
    for (final entry in points.entries) {
      final color = switch (observations[entry.key]?.status) {
        FrontCheck.checked => scanAccent,
        FrontCheck.review => const Color(0xFFFFC475),
        FrontCheck.hidden || null => const Color(0xFFE5F4ED),
      };
      if (entry.key == selected) {
        canvas.drawCircle(
          entry.value,
          14,
          Paint()..color = color.withValues(alpha: .25),
        );
      }
      canvas.drawCircle(entry.value, 9, Paint()..color = color);
      final number = TextPainter(
        text: TextSpan(
          text: '${entry.key.number}',
          style: const TextStyle(
            color: scanBackground,
            fontFamily: 'Pretendard',
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      number.paint(
        canvas,
        entry.value - Offset(number.width / 2, number.height / 2),
      );
      number.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InspectionDiagramPainter oldDelegate) =>
      oldDelegate.area != area ||
      oldDelegate.selected != selected ||
      oldDelegate.observations != observations;
}

class CameraAlignmentFrame extends StatelessWidget {
  const CameraAlignmentFrame({super.key});

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: CustomPaint(painter: _CameraAlignmentPainter()),
  );
}

class _CameraAlignmentPainter extends CustomPainter {
  const _CameraAlignmentPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTRB(
      size.width * .09,
      size.height * .20,
      size.width * .91,
      size.height * .83,
    );
    final guide = Paint()..color = Colors.white.withValues(alpha: .35);
    for (var i = 1; i < 3; i++) {
      final x = frame.left + frame.width * i / 3;
      final y = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), guide);
      canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), guide);
    }
    final edge = Paint()
      ..color = scanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final (corner, dx, dy) in [
      (frame.topLeft, 1, 1),
      (frame.topRight, -1, 1),
      (frame.bottomLeft, 1, -1),
      (frame.bottomRight, -1, -1),
    ]) {
      final path = Path()
        ..moveTo(corner.dx, corner.dy + dy * 18)
        ..lineTo(corner.dx, corner.dy)
        ..lineTo(corner.dx + dx * 18, corner.dy);
      canvas.drawPath(path, edge);
    }
  }

  @override
  bool shouldRepaint(_CameraAlignmentPainter oldDelegate) => false;
}

class DetectedPartsFrame extends StatefulWidget {
  const DetectedPartsFrame({
    required this.bytes,
    required this.proposals,
    required this.onSelected,
    super.key,
  });
  final Uint8List bytes;
  final Map<FrontPart, FrontPartProposal> proposals;
  final ValueChanged<FrontPart> onSelected;
  @override
  State<DetectedPartsFrame> createState() => _DetectedPartsFrameState();
}

class _DetectedPartsFrameState extends State<DetectedPartsFrame> {
  late MemoryImage provider;
  ImageStream? stream;
  ImageStreamListener? listener;
  double? ratio;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant DetectedPartsFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) load();
  }

  void load() {
    if (listener != null) stream?.removeListener(listener!);
    ratio = null;
    failed = false;
    provider = MemoryImage(widget.bytes);
    stream = provider.resolve(ImageConfiguration.empty);
    listener = ImageStreamListener(
      (info, _) {
        final value = info.image.width / info.image.height;
        info.dispose();
        if (mounted) setState(() => ratio = value);
      },
      onError: (Object error, StackTrace? stack) {
        if (mounted) setState(() => failed = true);
      },
    );
    stream!.addListener(listener!);
  }

  @override
  void dispose() {
    if (listener != null) stream?.removeListener(listener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (failed) return const Center(child: Text('분석 장면을 표시하지 못했습니다.'));
    if (ratio == null) return const Center(child: CircularProgressIndicator());
    return Center(
      child: AspectRatio(
        aspectRatio: ratio!,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(image: provider, fit: BoxFit.fill, semanticLabel: '최근 분석 장면'),
            LayoutBuilder(
              builder: (context, size) => Stack(
                children: [
                  for (final entry in widget.proposals.entries)
                    Positioned(
                      left: entry.value.left * size.maxWidth,
                      top: entry.value.top * size.maxHeight,
                      width:
                          (entry.value.right - entry.value.left) *
                          size.maxWidth,
                      height:
                          (entry.value.bottom - entry.value.top) *
                          size.maxHeight,
                      child: Semantics(
                        button: true,
                        label: '${entry.key.label} 위치 후보',
                        value: entry.value.scoreLabel,
                        child: GestureDetector(
                          onTap: () => widget.onSelected(entry.key),
                          child: Container(
                            alignment: Alignment.topLeft,
                            decoration: BoxDecoration(
                              border: Border.all(color: scanAccent, width: 2),
                              color: scanAccent.withValues(alpha: .08),
                            ),
                            child: ColoredBox(
                              color: scanBackground,
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Text(
                                  '${entry.key.number}',
                                  style: const TextStyle(color: scanAccent),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
