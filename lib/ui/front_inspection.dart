import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/front_inspection.dart';
import '../data/store.dart';
import '../data/local_vision.dart';
import 'components.dart';
import 'support.dart';

String frontMapUrl([
  String? vehicle,
  FrontInspectionArea area = FrontInspectionArea.exterior,
]) => Uri(
  path: '/front-map',
  queryParameters: {
    'vehicle': ?vehicle,
    if (area != FrontInspectionArea.exterior) 'area': area.name,
  },
).toString();

Color _statusColor(FrontCheck? status) => switch (status) {
  FrontCheck.checked => green,
  FrontCheck.review => const Color(0xFF925200),
  FrontCheck.hidden || null => muted,
};

class FrontPhoto extends StatelessWidget {
  const FrontPhoto({
    required this.path,
    required this.observations,
    this.onMark,
    this.vehicleDetection,
    this.proposals = const {},
    super.key,
  });

  final String path;
  final Map<FrontPart, FrontObservation> observations;
  final ValueChanged<Offset>? onMark;
  final VisionDetection? vehicleDetection;
  final Map<FrontPart, FrontPartProposal> proposals;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Image.file(
        File(path),
        width: double.infinity,
        fit: BoxFit.fitWidth,
        semanticLabel: '점검 사진',
        errorBuilder: (_, _, _) => const Padding(
          padding: EdgeInsets.all(16),
          child: Text('사진을 열 수 없습니다.'),
        ),
        frameBuilder: (context, image, frame, _) {
          if (frame == null) {
            return const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Stack(
            children: [
              image,
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, size) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: onMark == null
                        ? null
                        : (event) => onMark!(
                            Offset(
                              (event.localPosition.dx / size.maxWidth)
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                              (event.localPosition.dy / size.maxHeight)
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                            ),
                          ),
                    child: Stack(
                      children: [
                        if (vehicleDetection case final detection?)
                          Positioned(
                            left: detection.box[1] * size.maxWidth,
                            top: detection.box[0] * size.maxHeight,
                            width:
                                (detection.box[3] - detection.box[1]) *
                                size.maxWidth,
                            height:
                                (detection.box[2] - detection.box[0]) *
                                size.maxHeight,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.lightBlueAccent,
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                        for (final entry in proposals.entries)
                          if (!observations.containsKey(entry.key))
                            Positioned(
                              left: entry.value.left * size.maxWidth,
                              top: entry.value.top * size.maxHeight,
                              width:
                                  (entry.value.right - entry.value.left) *
                                  size.maxWidth,
                              height:
                                  (entry.value.bottom - entry.value.top) *
                                  size.maxHeight,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.amberAccent,
                                      width: 2,
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Text(
                                      '${entry.key.number}',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        backgroundColor: Colors.amberAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        for (final entry in observations.entries)
                          if (entry.value.x != null && entry.value.y != null)
                            Positioned(
                              left: (entry.value.x! * size.maxWidth - 14)
                                  .clamp(
                                    0.0,
                                    (size.maxWidth - 28).clamp(
                                      0.0,
                                      double.infinity,
                                    ),
                                  )
                                  .toDouble(),
                              top: (entry.value.y! * size.maxHeight - 14)
                                  .clamp(
                                    0.0,
                                    (size.maxHeight - 28).clamp(
                                      0.0,
                                      double.infinity,
                                    ),
                                  )
                                  .toDouble(),
                              child: Semantics(
                                label: entry.key.label,
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: _statusColor(
                                    entry.value.status,
                                  ),
                                  foregroundColor: Colors.white,
                                  child: Text('${entry.key.number}'),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class FrontMapScreen extends ConsumerStatefulWidget {
  const FrontMapScreen({
    this.vehicleId,
    this.initialArea = FrontInspectionArea.exterior,
    super.key,
  });

  final String? vehicleId;
  final FrontInspectionArea initialArea;

  @override
  ConsumerState<FrontMapScreen> createState() => _FrontMapState();
}

class _FrontMapState extends ConsumerState<FrontMapScreen> {
  String? vehicleId;
  late FrontInspectionArea area = widget.initialArea;
  late FrontPart part = area.parts.first;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final vehicles = store.vehicles;
    final vehicle =
        vehicles
            .where((v) => v.id == (vehicleId ?? widget.vehicleId))
            .firstOrNull ??
        store.dashboardVehicles.firstOrNull ??
        vehicles.firstOrNull;
    if (vehicle == null) return empty('차량을 등록한 뒤 사진 점검을 시작해 주세요.');

    final sessions =
        store.inspections
            .where((i) => i.vehicleId == vehicle.id && i.front.isNotEmpty)
            .toList()
          ..sort((a, b) => b.created.compareTo(a.created));
    final latest = <FrontPart, FrontObservation>{};
    for (final session in sessions) {
      for (final entry in session.front.entries) {
        latest.putIfAbsent(entry.key, () => entry.value);
      }
    }
    final history = sessions.where((i) => i.front.containsKey(part)).toList();

    Widget partButton(FrontPart target) {
      final status = latest[target]?.status;
      final selected = part == target;
      return Semantics(
        selected: selected,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            foregroundColor: _statusColor(status),
            backgroundColor: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.white,
          ),
          onPressed: () => setState(() => part = target),
          child: Text(
            '${target.label}\n${status?.label ?? '미점검'}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      children: [
        PageTitle('차량 상태 지도', '', scopeVehicles: [vehicle]),
        Panel(
          title: '차량 선택',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(vehicle.id),
                initialValue: vehicle.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '차량'),
                items: [
                  for (final v in vehicles)
                    DropdownMenuItem(
                      value: v.id,
                      child: Text(
                        '${vehicleLabel(v.id)} · ${modelLabel(v.model)}',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => vehicleId = value),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final item in FrontInspectionArea.values)
                    ChoiceChip(
                      label: Text(item.label),
                      selected: area == item,
                      onSelected: (_) => setState(() {
                        area = item;
                        part = item.parts.first;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => context.push(
                    Uri(
                      path: '/vision',
                      queryParameters: {
                        'vehicle': vehicle.id,
                        'front': '1',
                        'area': area.name,
                      },
                    ).toString(),
                  ),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(area.captureLabel),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '부위별 상태',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              if (area == FrontInspectionArea.exterior)
                const Text('좌우는 운전석에서 앞을 볼 때 기준입니다.'),
              const SizedBox(height: 8),
              if (area == FrontInspectionArea.engineBay)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final item in area.parts) partButton(item)],
                )
              else
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      border: Border.all(color: line),
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.directions_car_outlined, size: 36),
                        partButton(FrontPart.hood),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            partButton(FrontPart.rightLamp),
                            partButton(FrontPart.grille),
                            partButton(FrontPart.leftLamp),
                          ],
                        ),
                        partButton(FrontPart.bumper),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                part.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => context.push(
                      Uri(
                        path: '/manual-search',
                        queryParameters: {'query': part.searchTerm},
                      ).toString(),
                    ),
                    child: const Text('관련 책자'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        context.push(supportUrl(vehicle.id, part.searchTerm)),
                    child: const Text('수리 기록'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: '${part.label} 점검 기록',
          child: history.isEmpty
              ? empty('점검 기록이 없습니다.')
              : ResponsiveColumns(
                  children: [
                    for (final (index, inspection) in history.take(2).indexed)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${index == 0 ? '최근 점검' : '이전 점검'} · '
                            '${inspection.front[part]!.status.label}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            inspection.created
                                .replaceFirst('T', ' ')
                                .split('.')
                                .first,
                          ),
                          const SizedBox(height: 8),
                          FrontPhoto(
                            path: inspection.imagePath,
                            observations: {part: inspection.front[part]!},
                          ),
                          if (inspection.note.isNotEmpty) Text(inspection.note),
                          TextButton(
                            onPressed: () => context.push(
                              Uri(
                                path: '/vision',
                                queryParameters: {
                                  'vehicle': vehicle.id,
                                  'session': inspection.id,
                                },
                              ).toString(),
                            ),
                            child: const Text('사진 기록 상세'),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
