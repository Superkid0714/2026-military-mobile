import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/store.dart';
import '../data/clock.dart';
import 'analysis_charts.dart';
import 'components.dart';
import 'front_inspection.dart';
import 'maintenance_calendar.dart';
import 'schedule_editor.dart';
import 'support.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<DashboardScreen> {
  int monthsShown = 6;
  DateTime? inspectionMonth;
  int? inspectionDay;
  String? inspectionVehicle;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(storeProvider);
    final vehicles = s.dashboardVehicles;
    final ids = vehicles.map((v) => v.id).toSet();
    final predicted = [...vehicles]
      ..sort((a, b) {
        final first = s.predictions[a.id]?['probability'] as num?;
        final second = s.predictions[b.id]?['probability'] as num?;
        return (second ?? -1).compareTo(first ?? -1);
      });
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
    final vehicleColors = {
      for (final (index, vehicle) in vehicles.indexed)
        vehicle.id: trendColor(index),
    };
    final filter = vehicles.where((v) => v.id == inspectionVehicle).firstOrNull;
    final calendarUpcoming = upcoming
        .where(
          (item) =>
              ids.contains(item.$1.vehicleId) &&
              (filter == null || item.$1.vehicleId == filter.id),
        )
        .toList();
    final due = upcoming
        .where(
          (item) => ids.contains(item.$1.vehicleId) && item.$2.remainingKm == 0,
        )
        .length;
    final now = ref.watch(currentTimeProvider);
    final month = inspectionMonth ?? DateTime(now.year, now.month);
    final scheduledDays = <int, List<MaintenanceSchedule>>{};
    final nextMonth = DateTime(month.year, month.month + 1);
    for (final schedule in s.schedules) {
      if (!ids.contains(schedule.vehicleId) ||
          (filter != null && schedule.vehicleId != filter.id)) {
        continue;
      }
      final date = DateTime.parse(schedule.date);
      if (!date.isBefore(month) && date.isBefore(nextMonth)) {
        (scheduledDays[date.day] ??= []).add(schedule);
      }
    }
    final selectedSchedules =
        scheduledDays[inspectionDay] ?? const <MaintenanceSchedule>[];
    Future<void> editSchedule(int day, [MaintenanceSchedule? item]) async {
      final saved = await showDialog<DateTime>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ScheduleEditor(
          store: s,
          date: DateTime(month.year, month.month, day),
          vehicleId: filter?.id,
          vehicles: filter == null ? vehicles : [filter],
          schedule: item,
        ),
      );
      if (saved == null || !mounted) return;
      setState(() {
        inspectionMonth = DateTime(saved.year, saved.month);
        inspectionDay = saved.day;
      });
    }

    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final monthStart = DateTime(now.year, now.month);
    final periodStart = DateTime(now.year, now.month - monthsShown + 1);
    final records = s.records
        .where(
          (record) =>
              ids.contains(record.vehicleId) &&
              DateTime.parse(record.date).isBefore(tomorrow),
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
    final periodRecords = <Maintenance>[];
    for (final record in records) {
      final month = record.date.substring(0, 7);
      if (!months.containsKey(month)) continue;
      months[month] = months[month]! + 1;
      kinds.update(record.system, (count) => count + 1, ifAbsent: () => 1);
      periodRecords.add(record);
    }

    final scale = MediaQuery.textScalerOf(context);
    final shelfHeight = 20 + scale.scale(14);
    final cardHeight = 6 * (scale.scale(16) + 24) + 112 + shelfHeight;
    return ListView(
      children: [
        PageTitle(
          '종합 현황',
          '',
          action: FilledButton.icon(
            onPressed: () => context.push('/setup'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('차량 등록'),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final largeText = MediaQuery.textScalerOf(context).scale(16) > 20;
            final columns = constraints.maxWidth >= 880 && !largeText
                ? 4
                : constraints.maxWidth >= 480
                ? 2
                : 1;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            final metrics = [
              _OverviewMetric(
                title: '관리 차량',
                description: '운용 중인 차량 현황',
                value: '${vehicles.length}대',
                icon: Icons.local_shipping_outlined,
                accent: green,
                tint: const Color(0xFFE5F4EC),
                onTap: () => context.push('/vehicles?scope=home'),
              ),
              _OverviewMetric(
                title: '점검 필요',
                description: '정비 주기가 도래한 부품',
                value: '$due건',
                icon: Icons.fact_check_outlined,
                accent: const Color(0xFF8C4B11),
                tint: const Color(0xFFFFEBD6),
                onTap: () => context.push('/inspection-due'),
              ),
              _OverviewMetric(
                title: '이달 정비 기록',
                description: '이번 달에 저장한 작업 내역',
                value: '${currentRecords.length}건',
                icon: Icons.build_outlined,
                accent: const Color(0xFF245889),
                tint: const Color(0xFFE6F0FC),
                onTap: () => context.push('/records?period=month&view=history'),
              ),
              _OverviewMetric(
                title: '이번 달 비용',
                description: '저장한 정비 기록의 비용 합계',
                value:
                    '${number(currentRecords.fold<int>(0, (sum, r) => sum + r.cost))}원',
                icon: Icons.payments_outlined,
                accent: const Color(0xFF5C458A),
                tint: const Color(0xFFEFE9FB),
                onTap: () => context.push('/records?period=month&view=cost'),
              ),
            ];
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final metric in metrics)
                  SizedBox(width: width, child: metric),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'AI 정비 예측',
          subtitle: '고장수리 위험도',
          action: TextButton(
            onPressed: () => context.push('/ai-history'),
            child: const Text('분석 이력'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (predicted.isEmpty)
                const Text('차량을 등록하면 위험도 현황을 볼 수 있습니다.')
              else
                _FleetRiskChart(vehicles: predicted, store: s),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _QuickActions(hasVehicles: vehicles.isNotEmpty),
        const SizedBox(height: 16),
        ResponsiveColumns(
          breakpoint: MediaQuery.textScalerOf(context).scale(16) > 20
              ? 1120
              : 900,
          children: [
            if (vehicles.isNotEmpty)
              Panel(
                title: '정비 일정',
                subtitle: '날짜별 점검·교환 일정',
                action: PopupMenuButton<String>(
                  tooltip: '점검 차량 선택',
                  position: PopupMenuPosition.under,
                  borderRadius: BorderRadius.circular(24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onSelected: (value) => setState(() {
                    inspectionVehicle = value.isEmpty ? null : value;
                  }),
                  itemBuilder: (context) => [
                    CheckedPopupMenuItem(
                      value: '',
                      checked: filter == null,
                      child: const Text('전체 차량'),
                    ),
                    for (final vehicle in vehicles)
                      CheckedPopupMenuItem(
                        value: vehicle.id,
                        checked: filter?.id == vehicle.id,
                        child: Text(vehicleLabel(vehicle.id)),
                      ),
                  ],
                  child: _VehicleScopeChip(
                    label: filter == null ? '전체 차량' : vehicleLabel(filter.id),
                  ),
                ),
                child: SizedBox(
                  height: cardHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MaintenanceCalendar(
                        compact: true,
                        month: month,
                        counts: {
                          for (final entry in scheduledDays.entries)
                            entry.key: entry.value.length,
                        },
                        pinColors: {
                          for (final entry in scheduledDays.entries)
                            entry.key: entry.value
                                .map((item) => vehicleColors[item.vehicleId]!)
                                .toSet()
                                .toList(),
                        },
                        selected: inspectionDay,
                        onMonthChanged: (value) => setState(() {
                          inspectionMonth = value;
                          inspectionDay = null;
                        }),
                        onSelected: (day) =>
                            setState(() => inspectionDay = day),
                      ),
                      const Spacer(),
                      const Divider(height: 10),
                      SizedBox(
                        height: shelfHeight,
                        child: ListView(
                          primary: false,
                          scrollDirection: Axis.horizontal,
                          children: [
                            if (inspectionDay case final day?) ...[
                              OutlinedButton.icon(
                                onPressed: () => editSchedule(day),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('일정 추가'),
                              ),
                              for (final item in selectedSchedules)
                                _DashboardShelfTile(
                                  icon: Icons.place,
                                  color: vehicleColors[item.vehicleId]!,
                                  title: item.title,
                                  subtitle: vehicleLabel(item.vehicleId),
                                  onTap: () => editSchedule(day, item),
                                ),
                            ],
                            for (final (rule, assessment) in calendarUpcoming)
                              _DashboardShelfTile(
                                icon: Icons.place,
                                color: vehicleColors[rule.vehicleId]!,
                                title:
                                    '${vehicleLabel(rule.vehicleId)} · ${standardPart(rule.part)}',
                                subtitle: switch (assessment.remainingKm) {
                                  null => '거리 기준 · 기준 확인 필요',
                                  0 => '거리 기준 · 지금 점검',
                                  final km => '거리 기준 · ${number(km)} km 남음',
                                },
                                onTap: () => context.push(
                                  supportUrl(rule.vehicleId, rule.part),
                                ),
                              ),
                            for (final (rule, assessment) in calendarUpcoming)
                              if (assessment.blockingRecordIds.firstOrNull
                                  case final id?)
                                _DashboardShelfTile(
                                  key: ValueKey('resolve-maintenance-$id'),
                                  icon: Icons.fact_check_outlined,
                                  color: green,
                                  title: standardPart(rule.part),
                                  subtitle: '교환 여부 확인하기',
                                  onTap: () => context.go(
                                    Uri(
                                      path: '/entry',
                                      queryParameters: {'record': id},
                                    ).toString(),
                                  ),
                                ),
                            if (inspectionDay == null &&
                                calendarUpcoming.isEmpty)
                              const Center(child: Text('날짜를 눌러 일정을 추가하세요.')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Panel(
              title: '정비 추이',
              subtitle: '월별 정비 건수',
              child: SizedBox(
                height: cardHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '최근 $monthsShown개월',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextButton(
                          onPressed: () => context.push('/analysis'),
                          child: const Text('정비 분석 보기'),
                        ),
                      ],
                    ),
                    Slider(
                      min: 1,
                      max: 12,
                      divisions: 11,
                      value: monthsShown.toDouble(),
                      label: '$monthsShown개월',
                      semanticFormatterCallback: (value) =>
                          '최근 ${value.round()}개월',
                      onChanged: (value) =>
                          setState(() => monthsShown = value.round()),
                    ),
                    if (periodRecords.isEmpty)
                      Expanded(child: empty('선택한 기간에 정비 기록이 없습니다.'))
                    else
                      MaintenanceTrend(
                        months,
                        plotHeight: 182 + (scale.scale(16) - 16) * 2,
                      ),
                    if (periodRecords.isNotEmpty) const Spacer(),
                    const Divider(height: 10),
                    Text(
                      '조회 기간 총 ${periodRecords.length}건',
                      style: const TextStyle(
                        color: green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Panel(title: '정비 종류', child: MaintenanceBreakdown(kinds)),
        const SizedBox(height: 16),
        Panel(
          title: '최근 정비 기록',
          padding: 10,
          action: TextButton(
            onPressed: () => context.push('/records'),
            child: const Text('전체 보기'),
          ),
          child: periodRecords.isEmpty
              ? const Text('선택한 기간에 정비 기록이 없습니다.')
              : Column(
                  children: [
                    for (final (index, record)
                        in periodRecords.take(5).indexed) ...[
                      if (index > 0) const Divider(height: 1, color: line),
                      _RecentMaintenanceRow(record: record),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _FleetRiskChart extends StatelessWidget {
  const _FleetRiskChart({required this.vehicles, required this.store});

  final List<Vehicle> vehicles;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    const states = [
      VehicleStatus.normal,
      VehicleStatus.caution,
      VehicleStatus.danger,
      VehicleStatus.unavailable,
    ];
    const labels = ['낮음', '관찰', '높음', '미분석'];
    final groups = {
      for (final state in states)
        state: vehicles.where((vehicle) => vehicle.status == state).toList(),
    };
    final maximum = groups.values.fold<int>(
      1,
      (largest, group) => group.length > largest ? group.length : largest,
    );
    final scale = MediaQuery.textScalerOf(context);

    Future<void> openGroup(VehicleStatus state, String label) async {
      final selected = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text(
                    '$label · ${groups[state]!.length}대',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final vehicle in groups[state]!)
                        ListTile(
                          leading: Icon(
                            Icons.circle,
                            color: statusColor(state),
                            size: 12,
                          ),
                          title: Text(vehicleLabel(vehicle.id)),
                          subtitle: Text(
                            '${modelLabel(vehicle.model)} · ${vehicle.year}년식'
                            '${state == VehicleStatus.unavailable ? '\n${store.predictionUnavailableReason(vehicle.id)}' : ''}',
                          ),
                          trailing: state == VehicleStatus.unavailable
                              ? const Icon(Icons.chevron_right)
                              : Text(
                                  '${((store.predictions[vehicle.id]!['probability'] as num) * 100).toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                          onTap: () => Navigator.pop(context, vehicle.id),
                        ),
                      if (groups[state]!.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('해당 상태의 차량이 없습니다.'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (selected != null && context.mounted) {
        context.push('/ai-history?vehicle=${Uri.encodeComponent(selected)}');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '분석 완료 ${vehicles.where((vehicle) => vehicle.predictionReady).length}대 · 미분석 ${vehicles.where((vehicle) => !vehicle.predictionReady).length}대 · 전체 ${vehicles.length}대',
          style: const TextStyle(fontSize: 13, color: muted),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (index, state) in states.indexed)
              Expanded(
                child: Semantics(
                  button: true,
                  label: '${labels[index]} ${groups[state]!.length}대, 차량 보기',
                  child: InkWell(
                    key: ValueKey('fleet-risk-${state.name}'),
                    onTap: () => openGroup(state, labels[index]),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 64 + scale.scale(18),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  '${groups[state]!.length}대',
                                  style: TextStyle(
                                    color: statusColor(state),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                FractionallySizedBox(
                                  widthFactor: .6,
                                  child: Container(
                                    height: groups[state]!.isEmpty
                                        ? 3
                                        : 36 * groups[state]!.length / maximum,
                                    decoration: BoxDecoration(
                                      color: groups[state]!.isEmpty
                                          ? line
                                          : statusColor(state),
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(6),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: line),
                          const SizedBox(height: 8),
                          Text(
                            labels[index],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _RecentMaintenanceRow extends StatelessWidget {
  const _RecentMaintenanceRow({required this.record});

  final Maintenance record;

  @override
  Widget build(BuildContext context) {
    final description = maintenanceDescriptionLabel(record).trim();
    final part = standardPart(record.part);
    return ListTile(
      dense: true,
      minTileHeight: 48,
      minVerticalPadding: 4,
      horizontalTitleGap: 8,
      minLeadingWidth: 28,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: brandTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.build_outlined, color: green, size: 16),
      ),
      title: Text(
        description.isEmpty ? part : description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '${vehicleLabel(record.vehicleId)} · ${record.date.replaceAll('-', '.')}',
          style: const TextStyle(fontSize: 12, color: muted),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: muted, size: 20),
      onTap: () => context.push('/records/${Uri.encodeComponent(record.id)}'),
    );
  }
}

class _DashboardShelfTile extends StatelessWidget {
  const _DashboardShelfTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$title · $subtitle',
    child: Padding(
      padding: const EdgeInsets.only(right: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 192),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _VehicleScopeChip extends StatelessWidget {
  const _VehicleScopeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    final chip = Ink(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(color: brandTint, borderRadius: radius),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_shipping_outlined, size: 16, color: green),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 86),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: green,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.expand_more, size: 16, color: green),
        ],
      ),
    );
    return chip;
  }
}

class DueInspectionsScreen extends ConsumerWidget {
  const DueInspectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final vehicles = store.dashboardVehicles;
    final vehicleIds = vehicles.map((vehicle) => vehicle.id).toSet();
    final due = store.supportLibrary.rules
        .where(
          (rule) =>
              vehicleIds.contains(rule.vehicleId) &&
              store.serviceDistance(rule).remainingKm == 0,
        )
        .toList();

    return ListView(
      children: [
        PageTitle(
          '지금 점검',
          '정비 주기에 도달한 부품입니다.',
          scopeVehicles: vehicles,
          action: TextButton(
            onPressed: () => context.push('/plans'),
            child: const Text('전체 일정'),
          ),
        ),
        Panel(
          title: '점검 대상 ${due.length}건',
          child: due.isEmpty
              ? const Text('정비 주기에 도달한 부품이 없습니다.')
              : Column(
                  children: [
                    for (final rule in due)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${vehicleLabel(rule.vehicleId)} · ${standardPart(rule.part)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.push(supportUrl(rule.vehicleId, rule.part)),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.title,
    required this.description,
    required this.value,
    required this.icon,
    required this.onTap,
    required this.accent,
    required this.tint,
  });

  final String title, value, description;
  final IconData icon;
  final VoidCallback onTap;
  final Color accent, tint;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: line),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Icon(icon, size: 22, color: accent),
                  ),
                ),
                Icon(Icons.arrow_outward, size: 17, color: accent),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: muted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: ink,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
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
        title: '차량 사진 점검',
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
        ('차량 등록', '새 차량 추가와 등록 정보 확인', '/setup', Icons.add_circle_outline),
        ('사용 안내', '정비온 사용 방법 보기', '/welcome', Icons.help_outline),
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
