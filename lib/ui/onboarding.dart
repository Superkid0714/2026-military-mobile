import 'package:flutter/material.dart';

import 'components.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.onComplete, super.key});
  final Future<void> Function() onComplete;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int page = 0;
  bool saving = false;
  String? error;
  static const slides = [
    (
      '정비온과 함께 시작해요',
      '차량 기록부터 책자 검색까지,\n현장에서 필요한 정비 정보를 한곳에서 확인하세요.',
      Icons.handyman_outlined,
    ),
    (
      '통신이 없어도 든든하게',
      '기기에 넣어둔 책자를 찾아 쉽게 설명하고,\n관련 원본 그림과 출처도 함께 보여드려요.',
      Icons.wifi_off_rounded,
    ),
    (
      '기록하고, 다음 점검까지',
      '운용·정비 기록을 쌓고 분석 결과와 지난 이력을 확인하세요.\n무엇부터 점검할지 이유와 함께 안내해 드려요.',
      Icons.fact_check_outlined,
    ),
  ];
  Future<void> finish() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onComplete();
    } catch (_) {
      if (mounted) setState(() => error = '안내 설정을 저장하지 못했습니다. 다시 눌러 주세요.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slide = slides[page];
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text(
                        '정비온',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: saving ? null : finish,
                        child: const Text('건너뛰기'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Image.asset(
                    'assets/branding/jungbion-female-guide.png',
                    height: MediaQuery.sizeOf(context).height < 700 ? 170 : 230,
                    cacheWidth: 600,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(height: 24),
                  Icon(slide.$3, color: green, size: 28),
                  const SizedBox(height: 12),
                  Text(
                    slide.$1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    slide.$2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: muted,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    '${page + 1} / ${slides.length}',
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 16),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(error!),
                    ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      if (page > 0)
                        OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => setState(() => page--),
                          child: const Text('이전'),
                        ),
                      FilledButton(
                        onPressed: saving
                            ? null
                            : page < 2
                            ? () => setState(() => page++)
                            : finish,
                        child: Text(
                          saving
                              ? '준비 중…'
                              : page < 2
                              ? '다음'
                              : '정비온 시작하기',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '처음 한 번 안내해 드려요. 초기 설정에서 다시 볼 수 있습니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
