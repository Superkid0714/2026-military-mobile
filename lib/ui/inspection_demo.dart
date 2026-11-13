import 'package:flutter/material.dart';

import '../data/front_inspection.dart';
import 'inspection_part_card.dart';

/// Scripted inspection flow; saved records retain their source in mode metadata.
class InspectionDemo extends StatefulWidget {
  const InspectionDemo({
    this.area = FrontInspectionArea.exterior,
    this.onSave,
    this.onCapture,
    super.key,
  });
  final Future<void> Function(Map<FrontPart, FrontObservation>, String)? onSave;
  final VoidCallback? onCapture;
  final FrontInspectionArea area;

  @override
  State<InspectionDemo> createState() => _InspectionDemoState();
}

class _InspectionDemoState extends State<InspectionDemo>
    with SingleTickerProviderStateMixin {
  static const mint = Color(0xFF78F0B2);
  static const amber = Color(0xFFFFC56D);
  bool get engine => widget.area == FrontInspectionArea.engineBay;
  List<FrontPart> get parts => engine
      ? const [
          FrontPart.airCleaner,
          FrontPart.coolantTank,
          FrontPart.battery,
          FrontPart.oilDipstick,
        ]
      : const [
          FrontPart.hood,
          FrontPart.grille,
          FrontPart.rightLamp,
          FrontPart.leftLamp,
          FrontPart.bumper,
        ];
  int get issue => parts.length - 2;
  Offset position(int i) => const {
    FrontPart.hood: Offset(.5, .41),
    FrontPart.leftLamp: Offset(.76, .525),
    FrontPart.grille: Offset(.5, .56),
    FrontPart.rightLamp: Offset(.24, .525),
    FrontPart.bumper: Offset(.5, .685),
    FrontPart.battery: Offset(.14, .35),
    FrontPart.coolantTank: Offset(.76, .32),
    FrontPart.airCleaner: Offset(.83, .57),
    FrontPart.oilDipstick: Offset(.45, .57),
  }[parts[i]]!;
  late final scan = AnimationController(
    vsync: this,
    duration: Duration(seconds: engine ? 16 : 15),
  )..addListener(onProgress);
  final memo = TextEditingController();
  bool saving = false, saved = false;
  bool started = false;
  int completed = 0;
  int? selected;
  bool issueOpened = false;
  bool acknowledged = false;

  void onProgress() {
    final next = (scan.value * parts.length).floor();
    if (next > issue && !issueOpened) {
      // Open the issue immediately and let the operator review before continuing.
      issueOpened = true;
      selected = issue;
      scan.stop();
    }
    completed = next;
  }

  String status(int i) => i < completed
      ? i == issue
            ? acknowledged
                  ? '확인 요청됨'
                  : '이상 의심'
            : '점검 완료'
      : started && i == completed && !scan.isCompleted
      ? '점검 중'
      : '미점검';

  String finding(int i) => const {
    FrontPart.hood: '패널과 체결부 확인 완료',
    FrontPart.leftLamp: '렌즈 손상 의심 · 점등 상태 추가 확인',
    FrontPart.grille: '흡기부와 외관 확인 완료',
    FrontPart.rightLamp: '렌즈와 외관 확인 완료',
    FrontPart.bumper: '범퍼와 체결부 확인 완료',
    FrontPart.battery: '단자 부식 의심 · 전원 연결 상태 추가 확인',
    FrontPart.coolantTank: '냉각수통 외관 확인 완료',
    FrontPart.airCleaner: '하우징과 흡기 연결부 확인 완료',
    FrontPart.oilDipstick: '게이지 위치 확인 완료 · 오일량은 직접 확인',
  }[parts[i]]!;

  @override
  void dispose() {
    memo.dispose();
    scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    child: PopScope(
      canPop: !saving,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: AnimatedBuilder(
          animation: scan,
          builder: (context, _) {
            final active =
                selected ?? (completed - 1).clamp(0, parts.length - 1);
            final warning = active == issue && active < completed;
            final visual = ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: LayoutBuilder(
                  builder: (context, bounds) => Stack(
                    fit: StackFit.expand,
                    children: [
                      if (engine)
                        Image.asset(
                          'assets/branding/military-engine-bay.png',
                          fit: BoxFit.cover,
                        )
                      else
                        Image.asset(
                          'assets/branding/military-front-reference.png',
                          fit: BoxFit.cover,
                        ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x5510201D),
                              Colors.transparent,
                              Color(0xCC10201D),
                            ],
                          ),
                        ),
                      ),
                      if (started && !scan.isCompleted)
                        Positioned(
                          top: scan.value * (bounds.maxHeight - 3),
                          left: 0,
                          right: 0,
                          child: Container(height: 3, color: mint),
                        ),
                      if (warning)
                        Positioned(
                          left:
                              (position(active).dx * bounds.maxWidth -
                                      bounds.maxWidth * .13)
                                  .clamp(0, bounds.maxWidth * .74),
                          top:
                              (position(active).dy * bounds.maxHeight -
                                      bounds.maxHeight * .12)
                                  .clamp(0, bounds.maxHeight * .76),
                          width: bounds.maxWidth * .26,
                          height: bounds.maxHeight * .24,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(color: amber, width: 3),
                                borderRadius: BorderRadius.circular(12),
                                color: const Color(0x22FFC56D),
                              ),
                            ),
                          ),
                        ),
                      if (issueOpened)
                        Positioned(
                          left: 12,
                          right: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xEE513B1A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '⚠ ${parts[issue].label} · ${acknowledged ? '정비 확인 필요' : '이상 징후 감지'}',
                              style: const TextStyle(
                                color: amber,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      for (var i = 0; i < parts.length; i++)
                        Positioned(
                          left: (position(i).dx * bounds.maxWidth - 24).clamp(
                            0,
                            bounds.maxWidth - 48,
                          ),
                          top: position(i).dy * bounds.maxHeight - 24,
                          child: IconButton.filled(
                            tooltip: parts[i].label,
                            style: IconButton.styleFrom(
                              backgroundColor: i < completed
                                  ? i == issue
                                        ? amber
                                        : mint
                                  : const Color(0xDD193C34),
                              foregroundColor: Colors.black,
                              side: BorderSide(
                                color: active == i
                                    ? Colors.white
                                    : Colors.white54,
                                width: active == i ? 3 : 1,
                              ),
                            ),
                            onPressed: () => setState(() => selected = i),
                            icon: Icon(
                              i < completed
                                  ? i == issue
                                        ? Icons.priority_high
                                        : Icons.check
                                  : Icons.center_focus_strong,
                            ),
                          ),
                        ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Text(
                          engine
                              ? 'ENGINE BAY · 부위 상태 연결'
                              : 'FRONT VIEW · 부위 상태 연결',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            final checklist = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '실시간 점검 현황',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < parts.length; i++)
                  InspectionPartCard(
                    key: ValueKey('inspection-part-$i'),
                    part: parts[i],
                    status: status(i),
                    selected: active == i,
                    progress: (scan.value * parts.length - completed).clamp(
                      0,
                      1,
                    ),
                    onTap: () => setState(() => selected = i),
                  ),
              ],
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '디지털 트윈 · ${widget.area.label} 점검',
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: saving ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, bounds) => bounds.maxWidth >= 720
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: visual),
                              const SizedBox(width: 20),
                              Expanded(flex: 2, child: checklist),
                            ],
                          )
                        : Column(
                            children: [
                              visual,
                              const SizedBox(height: 16),
                              checklist,
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    key: const ValueKey('inspection-total-progress'),
                    value: scan.value,
                    minHeight: 6,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    !started
                        ? '촬영 영역 연결 완료 · AI 점검을 시작하세요.'
                        : scan.isCompleted
                        ? '전체 점검 종료 · ${parts.length - 1}개 완료 / 이상 의심 1개'
                        : '${parts[completed.clamp(0, parts.length - 1)].label} · ${scan.isAnimating ? '점검 진행 중' : '일시정지'}  ·  $completed / ${parts.length}',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16342E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${parts[active].label} · ${status(active)}',
                          style: TextStyle(
                            color: warning ? amber : mint,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          active < completed
                              ? finding(active)
                              : '점검이 완료되면 결과가 여기에 표시됩니다.',
                          style: const TextStyle(color: Colors.white),
                        ),
                        if (warning) ...[
                          const SizedBox(height: 8),
                          Text(
                            engine
                                ? '확인 순서 · 시동 OFF → 단자 부식·풀림 육안 확인 → 정비 담당자 확인 요청'
                                : '확인 순서 · 렌즈 균열 확인 → 좌우 점등 비교 → 정비 담당자 확인 요청',
                            style: const TextStyle(
                              color: Colors.white,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '추가 확인 필요 · 담당자 확인 후 조치를 결정하세요.',
                            style: TextStyle(color: amber, fontSize: 12),
                          ),
                          TextButton(
                            onPressed: acknowledged
                                ? null
                                : () => setState(() => acknowledged = true),
                            child: Text(
                              acknowledged ? '정비 확인 필요로 분류됨' : '정비 확인 필요',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (scan.isCompleted && widget.onSave != null) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: memo,
                      enabled: !saving && !saved,
                      maxLength: 2000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '점검 메모',
                        hintText: '확인한 상태와 후속 조치를 기록하세요.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: saving || saved
                          ? null
                          : () async {
                              setState(() => saving = true);
                              try {
                                await widget.onSave!({
                                  for (var i = 0; i < parts.length; i++)
                                    parts[i]: FrontObservation(
                                      i == issue
                                          ? FrontCheck.review
                                          : FrontCheck.checked,
                                      x: position(i).dx,
                                      y: position(i).dy,
                                    ),
                                }, memo.text.trim());
                                if (mounted) setState(() => saved = true);
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('저장하지 못했습니다. 다시 시도해 주세요.'),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => saving = false);
                              }
                            },
                      icon: Icon(
                        saved ? Icons.check_circle : Icons.save_outlined,
                      ),
                      label: Text(
                        saved
                            ? '사진·점검 기록 저장 완료'
                            : saving
                            ? '저장 중…'
                            : '사진·점검 기록 저장',
                      ),
                    ),
                  ],
                  if (widget.onCapture != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: saving ? null : widget.onCapture,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('직접 촬영해서 기록'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!started)
                        FilledButton.icon(
                          onPressed: () => setState(() {
                            started = true;
                            scan.forward(from: 0);
                          }),
                          icon: const Icon(Icons.radar),
                          label: const Text('AI 점검 시작'),
                        ),
                      if (started && !scan.isCompleted)
                        FilledButton.icon(
                          onPressed: () => setState(() {
                            if (scan.isAnimating) {
                              scan.stop();
                            } else {
                              scan.forward();
                            }
                          }),
                          icon: Icon(
                            scan.isAnimating ? Icons.pause : Icons.play_arrow,
                          ),
                          label: Text(scan.isAnimating ? '잠시 멈추고 확인' : '점검 계속'),
                        ),
                      OutlinedButton.icon(
                        onPressed: saving
                            ? null
                            : () => setState(() {
                                saved = false;
                                memo.clear();
                                selected = null;
                                started = false;
                                scan.stop();
                                completed = 0;
                                issueOpened = false;
                                acknowledged = false;
                                scan.value = 0;
                              }),
                        icon: const Icon(Icons.replay),
                        label: const Text('다시 점검'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
