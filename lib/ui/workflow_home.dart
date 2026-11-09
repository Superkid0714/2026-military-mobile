import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/store.dart';
import 'components.dart';
import 'front_inspection.dart';
import 'support.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    return ListView(
      children: [
        const PageTitle('종합 현황', ''),
        if (s.presentationVehicles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text('운용 예시 ${s.presentationVehicles.length}대'),
                  selected: s.dashboardExampleView,
                  onSelected: (_) => s.setDashboardExampleView(true),
                ),
                ChoiceChip(
                  label: Text('등록 차량 ${s.registeredVehicles.length}대'),
                  selected: !s.dashboardExampleView,
                  onSelected: (_) => s.setDashboardExampleView(false),
                ),
              ],
            ),
          ),
        if (s.presentationVehicles.isEmpty) ...[
          Text('차량 ${vehicles.length}대', style: const TextStyle(color: muted)),
          const SizedBox(height: 12),
        ],
        _QuickActions(hasVehicles: vehicles.isNotEmpty),
        const SizedBox(height: 16),
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
                      for (final (rule, assessment) in upcoming.take(3)) ...[
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
                          onTap: () =>
                              context.go(supportUrl(rule.vehicleId, rule.part)),
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

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.hasVehicles});

  final bool hasVehicles;

  @override
  Widget build(BuildContext context) {
    final stackButtons = MediaQuery.textScalerOf(context).scale(14) > 18;
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      alignment: Alignment.centerLeft,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveColumns(
          breakpoint: stackButtons ? double.infinity : 700,
          children: [
            FilledButton.icon(
              style: buttonStyle,
              onPressed: () {
                if (hasVehicles) {
                  context.push(frontMapUrl());
                } else {
                  context.go('/setup');
                }
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(hasVehicles ? '차량 사진 점검' : '차량 등록'),
            ),
            OutlinedButton.icon(
              style: buttonStyle,
              onPressed: hasVehicles ? () => context.go('/entry') : null,
              icon: const Icon(Icons.edit_note),
              label: const Text('정비 결과 입력'),
            ),
            OutlinedButton.icon(
              style: buttonStyle,
              onPressed: () => context.go('/chat'),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('정비 질문하기'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => context.go('/support'),
              child: const Text('부품별 정비'),
            ),
            if (hasVehicles)
              TextButton(
                onPressed: () => context.go('/setup'),
                child: const Text('초기 설정·차량 등록'),
              ),
          ],
        ),
      ],
    );
  }
}
