import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/front_inspection.dart';
import '../data/store.dart';
import 'inspection_demo.dart';

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
    this.onSave,
    this.onCapture,
    super.key,
  });

  final Future<void> Function(Map<FrontPart, FrontObservation>, String)? onSave;
  final VoidCallback? onCapture;
  final FrontInspectionArea area;
  final Map<FrontPart, FrontObservation> observations;
  final FrontPart? selected;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '${area.label} 부위 안내도',
    child: AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: area == FrontInspectionArea.exterior
            ? _MilitaryFrontPreview(
                selected: selected,
                observations: observations,
                onSave: onSave,
                onCapture: onCapture,
              )
            : GestureDetector(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => InspectionDemo(
                    area: area,
                    onSave: onSave,
                    onCapture: onCapture,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/branding/military-engine-bay.png',
                      fit: BoxFit.cover,
                    ),
                    CustomPaint(
                      painter: _InspectionDiagramPainter(
                        area,
                        observations,
                        selected,
                      ),
                    ),
                    const Positioned(
                      right: 8,
                      bottom: 6,
                      child: Text(
                        '▶ 눌러서 엔진룸 점검 시작',
                        style: TextStyle(
                          color: Colors.white,
                          backgroundColor: scanBackground,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );
}

class _MilitaryFrontPreview extends StatefulWidget {
  const _MilitaryFrontPreview({
    required this.selected,
    required this.observations,
    this.onSave,
    this.onCapture,
  });
  final Future<void> Function(Map<FrontPart, FrontObservation>, String)? onSave;
  final VoidCallback? onCapture;
  final FrontPart? selected;
  final Map<FrontPart, FrontObservation> observations;

  @override
  State<_MilitaryFrontPreview> createState() => _MilitaryFrontPreviewState();
}

class _MilitaryFrontPreviewState extends State<_MilitaryFrontPreview>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) => Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => InspectionDemo(
              onSave: widget.onSave,
              onCapture: widget.onCapture,
            ),
          ),
          child: Image.asset(
            'assets/branding/military-front-reference.png',
            fit: BoxFit.cover,
          ),
        ),
        if (animation.isAnimating)
          Align(
            alignment: Alignment(0, animation.value * 2 - 1),
            child: Container(height: 2, color: scanAccent),
          ),
        Positioned(
          right: 8,
          top: 8,
          child: IconButton.filledTonal(
            tooltip: '전면 점검 시작',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => InspectionDemo(
                onSave: widget.onSave,
                onCapture: widget.onCapture,
              ),
            ),
            icon: const Icon(Icons.play_arrow),
          ),
        ),
        if (animation.isAnimating)
          Positioned(
            left: 8,
            top: 8,
            right: 64,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: const Color(0xD916342E),
              child: Text(
                animation.value < .33
                    ? '차량 전면 전체를 화면에 맞추세요.'
                    : animation.value < .66
                    ? '번호가 표시된 부위를 확인하세요.'
                    : '전면 사진 찍기를 눌러 실제 점검을 시작하세요.',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        for (final entry in const {
          FrontPart.hood: Alignment(0, -.18),
          FrontPart.rightLamp: Alignment(-.52, .05),
          FrontPart.grille: Alignment(0, .12),
          FrontPart.leftLamp: Alignment(.52, .05),
          FrontPart.bumper: Alignment(0, .37),
        }.entries)
          Align(
            alignment: entry.value,
            child: Container(
              width: entry.key == widget.selected ? 30 : 22,
              height: entry.key == widget.selected ? 30 : 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: entry.key == widget.selected
                    ? scanAccent
                    : const Color(0xD922342B),
                border: Border.all(color: Colors.white, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                '${entry.key.number}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: entry.key == widget.selected
                      ? const Color(0xFF16342E)
                      : Colors.white,
                ),
              ),
            ),
          ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xC916342E),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Text(
              '눌러서 전면 점검 시작',
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ),
      ],
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
    final points = {
      FrontPart.battery: Offset(size.width * .14, size.height * .35),
      FrontPart.coolantTank: Offset(size.width * .76, size.height * .32),
      FrontPart.airCleaner: Offset(size.width * .83, size.height * .57),
      FrontPart.oilDipstick: Offset(size.width * .45, size.height * .57),
    };
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
