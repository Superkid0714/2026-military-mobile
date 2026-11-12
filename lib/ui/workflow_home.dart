import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/store.dart';
import '../data/clock.dart';
import 'analysis_charts.dart';
import 'components.dart';
import 'front_inspection.dart';
import 'support.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<DashboardScreen> {
  int monthsShown = 6;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(storeProvider);
    final vehicles = s.dashboardVehicles;
    final ids = vehicles.map((v) => v.id).toSet();
    final upcoming =
        [
          for (final rule in s.supportLibrary.rules)
            if (ids.contains(rule.vehicleId)) (rule, s.serviceDistance(rule)),
        ]..sort((a, b) {
          // Due items come first, followed by missing baselines and upcoming work.
          int priority(int? km) => km == 0 ? -2 : km ?? -1;
          return priority(a.$2.remainingKm)
              .compareTo(priority(b.$2.remainingKm));
        });
    final due = upcoming.where((item) => item.$2.remainingKm == 0).length;
    final now = ref.watch(currentTimeProvider);
    final monthStart = DateTime(now.year, now.month);
    final periodStart = DateTime(now.year, now.month - monthsShown + 1);
    final records = s.records
        .where(
          (record) =>
              ids.contains(record.vehicleId) &&
              !DateTime.parse(record.date).isAfter(now),
        )
        .toList();
    final currentRecords = records
        .where((record) => !DateTime.parse(record.date).isBefore(monthStart))
        .toList();
    final months = <String, num>{
      for (var i = 0; i < monthsShown; i++)
        DateTime(
          periodStart.year,
          periodStart.month + i,
        ).toIso8601String().substring(0, 7): 0,
    };
    final kinds = <String, num>{};
    for (final record in records) {
      final month = record.date.substring(0, 7);
      if (months.containsKey(month)) {
        months[month] = months[month]! + 1;
        kinds.update(record.system, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return ListView(
      children: [
        PageTitle(
          '종합 현황',
          '',
          action: TextButton.icon(
            onPressed: () => context.push('/welcome'),
            icon: const Icon(Icons.help_outline, size: 18),
            label: const Text('사용 안내'),
          ),
        ),
        if (s.presentationVehicles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text('앱 제공 차량 ${s.presentationVehicles.length}대'),
                  selected: s.dashboardExampleView,
                  backgroundColor: Colors.white,
                  selectedColor: brandTint,
                  onSelected: (_) => s.setDashboardExampleView(true),
                ),
                ChoiceChip(
                  label: Text('등록 차량 ${s.registeredVehicles.length}대'),
                  selected: !s.dashboardExampleView,
                  backgroundColor: Colors.white,
                  selectedColor: brandTint,
                  onSelected: (_) => s.setDashboardExampleView(false),
                ),
              ],
            ),
          ),
        if (s.presentationVehicles.isEmpty) ...[
          Text('차량 ${vehicles.length}대', style: const TextStyle(color: muted)),
          const SizedBox(height: 12),
        ],
        ResponsiveColumns(
          breakpoint: 680,
          children: [
            _OverviewMetric(
              title: '관리 차량',
              value: '${vehicles.length}대',
              icon: Icons.local_shipping_outlined,
            ),
            _OverviewMetric(
              title: '지금 점검',
              value: '$due건',
              icon: Icons.fact_check_outlined,
            ),
            _OverviewMetric(
              title: '이번 달 정비',
              value: '${currentRecords.length}건',
              icon: Icons.build_outlined,
            ),
            _OverviewMetric(
              title: '이번 달 비용',
              value:
                  '${number(currentRecords.fold<int>(0, (sum, r) => sum + r.cost))}원',
              icon: Icons.payments_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _QuickActions(hasVehicles: vehicles.isNotEmpty),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => context.go('/records?period=month'),
              child: const Text('이번 달 정비와 점검 순서'),
            ),
            TextButton(
              onPressed: () => context.go('/vehicles'),
              child: const Text('관리 차량 목록'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ResponsiveColumns(
          children: [
            if (vehicles.isNotEmpty)
              Panel(
                title: '다음 점검',
                subtitle: due > 0 ? '지금 점검 $due건' : null,
                action: TextButton(
                  onPressed: () => context.go('/plans'),
                  child: const Text('전체 일정'),
                ),
                child: upcoming.isEmpty
                    ? const Text('등록한 점검 일정이 없습니다.')
                    : Column(
                        children: [
                          for (final (rule, assessment) in upcoming.take(
                            3,
                          )) ...[
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${vehicleLabel(rule.vehicleId)} · ${standardPart(rule.part)}',
                              ),
                              subtitle: Text(switch (assessment.remainingKm) {
                                null => '기준 확인 필요',
                                0 => '지금 점검',
                                final km => '${number(km)} km 남음',
                              }),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.go(
                                supportUrl(rule.vehicleId, rule.part),
                              ),
                            ),
                            if (assessment.blockingRecordIds.isNotEmpty)
                              BlockingMaintenanceLinks(
                                rule: rule,
                                store: s,
                                limit: 1,
                              ),
                          ],
                        ],
                      ),
              ),
            Panel(
              title: '최근 $monthsShown개월 정비',
              action: TextButton(
                onPressed: () => context.go('/analysis'),
                child: const Text('자세히'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final period in [3, 6, 12])
                        ChoiceChip(
                          label: Text('$period개월'),
                          selected: period == monthsShown,
                          onSelected: (_) =>
                              setState(() => monthsShown = period),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  MaintenanceTrend(months),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Panel(title: '정비 종류', child: MaintenanceBreakdown(kinds)),
        if (records.any(
          (record) => !DateTime.parse(record.date).isBefore(periodStart),
        )) ...[
          const SizedBox(height: 16),
          Panel(
            title: '최근 정비',
            child: Column(
              children: [
                for (final record
                    in records
                        .where(
                          (record) =>
                              !DateTime.parse(record.date)
                                  .isBefore(periodStart),
                        )
                        .take(3))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.build_circle_outlined,
                      color: green,
                    ),
                    title: Text(
                      '${standardPart(record.part)} · ${vehicleLabel(record.vehicleId)}',
                    ),
                    subtitle: Text(record.date),
                    trailing: Text('${number(record.cost)}원'),
                    onTap: () => context.go('/records'),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton(
              onPressed: () => context.go('/records'),
              child: const Text('정비 기록 보기'),
            ),
            TextButton(
              onPressed: () => context.go('/analysis'),
              child: const Text('정비 분석 보기'),
            ),
          ],
        ),
      ],
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title, value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: line),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: ink),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: ink, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.hasVehicles});

  final bool hasVehicles;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        title: hasVehicles ? '차량 사진 점검' : '차량 등록',
        description: hasVehicles ? '외관·엔진룸 사진 찍기' : '내 차량을 먼저 추가',
        icon: hasVehicles
            ? Icons.photo_camera_outlined
            : Icons.add_circle_outline,
        onTap: () {
          if (hasVehicles) {
            context.push(frontMapUrl());
          } else {
            context.go('/setup');
          }
        },
      ),
      (
        title: '정비 결과 입력',
        description: hasVehicles ? '부품과 작업 내용 기록' : '차량 등록 후 기록',
        icon: Icons.edit_note,
        onTap: () => context.go(hasVehicles ? '/entry' : '/setup'),
      ),
      (
        title: '정비 질문하기',
        description: hasVehicles ? '책자와 차량 기록에서 답 찾기' : '정비 책자에서 답 찾기',
        icon: Icons.chat_bubble_outline,
        onTap: () => context.go(hasVehicles ? '/chat' : '/manual-search'),
      ),
      (
        title: '부품별 정비',
        description: hasVehicles ? '교환 기준과 수리 이력 확인' : '차량 등록 후 부품별 확인',
        icon: Icons.build_outlined,
        onTap: () => context.go(hasVehicles ? '/support' : '/setup'),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '정비 작업',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final largeText = MediaQuery.textScalerOf(context).scale(16) > 20;
            final columns = constraints.maxWidth >= 900 && !largeText
                ? 4
                : constraints.maxWidth >= 520
                ? 2
                : 1;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: width,
                    child: OutlinedButton(
                      onPressed: action.onTap,
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        minimumSize: const Size(0, 88),
                        padding: const EdgeInsets.all(12),
                        backgroundColor: Colors.white,
                        foregroundColor: ink,
                        overlayColor: green,
                        side: const BorderSide(color: line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(action.icon, color: ink, size: 20),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  action.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  action.description,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right,
                            size: 17,
                            color: muted,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (hasVehicles)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.go('/setup'),
              child: const Text('초기 설정·차량 등록'),
            ),
          ),
      ],
    );
  }
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const _groups = [
    (
      '차량과 정비',
      [
        ('차량 목록', '차량별 상태와 기록 확인', '/vehicles', Icons.local_shipping_outlined),
        ('정비 일정', '다음에 할 점검과 교환 확인', '/plans', Icons.calendar_today_outlined),
        ('정비 분석', '정비 건수와 비용 보기', '/analysis', Icons.bar_chart_outlined),
        ('현장 요청', '부속 요청과 인식 오류 확인', '/field-work', Icons.inventory_2_outlined),
      ],
    ),
    (
      '자료와 설정',
      [
        (
          '책자 검색',
          '책자 내용과 원본 그림 찾기',
          '/manual-search',
          Icons.menu_book_outlined,
        ),
        ('차량 등록·설정', '앱 소개·안내와 차량 등록', '/setup', Icons.settings_outlined),
        (
          '백업·자료 가져오기',
          '기록 백업과 책자 가져오기',
          '/data-tools',
          Icons.folder_open_outlined,
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const PageTitle('더 보기', ''),
      for (final (heading, items) in _groups) ...[
        Text(heading, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ResponsiveColumns(
          children: [
            for (final (title, description, route, icon) in items)
              Card(
                margin: EdgeInsets.zero,
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: line),
                ),
                child: ListTile(
                  minTileHeight: 76,
                  leading: Icon(icon, color: green),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(description),
                  onTap: () => context.go(route),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    ],
  );
}
