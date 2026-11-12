import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'components.dart';

enum OnboardingAction { examples, register, home }

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.onComplete, super.key});

  final Future<void> Function(OnboardingAction) onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool saving = false;
  String? error;

  Future<void> finish(OnboardingAction action) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onComplete(action);
    } catch (_) {
      if (mounted) {
        setState(() => error = '화면을 준비하지 못했어요. 다시 눌러 주세요.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                color: Colors.white,
                elevation: 0,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: line),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '정비온',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: green,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Center(child: _GuideVehicle(size: 152)),
                      const SizedBox(height: 16),
                      const Text(
                        '어서 오세요!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '점검할 곳을 찾고, 사진을 찍고, 정비 기록을 남기는 방법을 알려드려요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: muted,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                        onPressed: saving
                            ? null
                            : () => finish(OnboardingAction.examples),
                        icon: const Icon(Icons.directions_car_outlined),
                        label: const Text('사용 안내 시작'),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          '운용 차량으로 화면을 따라가요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                        onPressed: saving
                            ? null
                            : () => finish(OnboardingAction.register),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('내 차량 등록하기'),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(error!, textAlign: TextAlign.center),
                        ),
                      TextButton(
                        onPressed: saving
                            ? null
                            : () => finish(OnboardingAction.home),
                        child: Text(saving ? '준비 중…' : '건너뛰기'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ExampleGuide extends StatelessWidget {
  const ExampleGuide({required this.step, required this.vehicleId, super.key});

  final int step;
  final String vehicleId;

  static const _steps = [
    ('/', '오늘 할 점검 찾기', '아래 ‘다음 점검’에서 먼저 확인할 차량과 부품을 살펴보세요.'),
    ('/front-map', '사진으로 상태 남기기', '‘전면 외관’이나 ‘엔진룸’을 선택하고 촬영할 부위를 찾아보세요.'),
    ('/entry', '정비 결과 기록하기', '정비한 부품과 작업 내용을 어디에 입력하는지 살펴보세요.'),
    ('/chat', '정비 질문하기', '추천 질문을 골라 차량 기록과 책자에서 답을 찾아보세요.'),
    ('/more', '필요한 기능 찾기', '차량 목록, 정비 일정과 분석, 책자와 설정을 여기에서 열어요.'),
    ('/vehicles', '차량별 상태 보기', '차량을 선택하면 주행거리와 정비 기록을 함께 볼 수 있어요.'),
    ('/plans', '달력으로 일정 보기', '월을 바꾸고 날짜를 눌러 그날의 일정을 확인하세요.'),
    ('/analysis', '정비 흐름 살펴보기', '정비 건수와 비용, 월별 추이를 확인하세요.'),
    ('/manual-search', '책자에서 찾기', '궁금한 내용을 입력하면 관련 문장과 원본 그림을 찾아요.'),
    ('/setup', '내 차량 준비하기', '차량과 점검 기준을 등록하고 사용 안내를 다시 열 수 있어요.'),
    ('/data-tools', '기록 보관하기', '기록을 백업하거나 책자 자료를 가져올 수 있어요.'),
  ];

  static int? stepFor(Uri uri) {
    final index = int.tryParse(uri.queryParameters['guide'] ?? '');
    if (index == null || index < 0 || index >= _steps.length) return null;
    return uri.path == _steps[index].$1 ? index : null;
  }

  static String location(int step, String vehicleId) => Uri(
    path: _steps[step].$1,
    queryParameters: {
      'guide': '$step',
      if (step > 0 && vehicleId.isNotEmpty) 'vehicle': vehicleId,
    },
  ).toString();

  @override
  Widget build(BuildContext context) {
    final (_, title, instruction) = _steps[step];
    final last = step == _steps.length - 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: brandTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _GuideVehicle(size: 48),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '사용 안내 · ${step + 1}/${_steps.length}  $title',
                        style: const TextStyle(
                          color: green,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(instruction),
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                if (!last)
                  TextButton(
                    onPressed: () => context.go('/'),
                    child: const Text('안내 끝내기'),
                  ),
                if (step > 0)
                  TextButton(
                    onPressed: () => context.go(location(step - 1, vehicleId)),
                    child: const Text('이전'),
                  ),
                FilledButton(
                  onPressed: () =>
                      context.go(last ? '/' : location(step + 1, vehicleId)),
                  child: Text(last ? '안내 마치기' : '다음'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideVehicle extends StatefulWidget {
  const _GuideVehicle({required this.size});

  final double size;

  @override
  State<_GuideVehicle> createState() => _GuideVehicleState();
}

class _GuideVehicleState extends State<_GuideVehicle>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.reset();
    } else if (!motion.isAnimating) {
      motion.repeat();
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox.square(
      dimension: widget.size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: motion,
            child: ClipOval(
              child: Image.asset(
                'assets/branding/jungbion-vehicle-logo.png',
                fit: BoxFit.cover,
                cacheWidth: 384,
                excludeFromSemantics: true,
              ),
            ),
            builder: (context, child) {
              final phase = motion.value * 2 * math.pi;
              return Transform.translate(
                offset: Offset(
                  -widget.size * .02 * math.sin(phase),
                  -widget.size * (.028 + .012 * math.sin(phase * 2)),
                ),
                child: Transform.rotate(
                  angle: .018 * math.sin(phase),
                  child: child,
                ),
              );
            },
          ),
          IgnorePointer(child: CustomPaint(painter: _GuideRoad(motion))),
        ],
      ),
    ),
  );
}

class _GuideRoad extends CustomPainter {
  _GuideRoad(this.motion) : super(repaint: motion);

  final Animation<double> motion;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final road = RRect.fromLTRBR(
      width * .04,
      size.height * .79,
      width * .96,
      size.height * .94,
      Radius.circular(width * .045),
    );
    canvas.drawRRect(road, Paint()..color = const Color(0xFF334740));
    canvas.save();
    canvas.clipRRect(road);
    final marking = Paint()
      ..color = const Color(0xFFE2F5EA)
      ..strokeWidth = width * .018
      ..strokeCap = StrokeCap.round;
    final y = size.height * .875;
    final spacing = width * .24;
    // The vehicle points left, so the road moves toward the right edge.
    for (var i = -1; i <= 4; i++) {
      final x = spacing * (i + motion.value);
      canvas.drawLine(Offset(x, y), Offset(x + width * .12, y), marking);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GuideRoad oldDelegate) => oldDelegate.motion != motion;
}
