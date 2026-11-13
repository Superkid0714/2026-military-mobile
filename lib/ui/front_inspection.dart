import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/front_inspection.dart';
import '../data/store.dart';
import '../data/local_vision.dart';
import 'components.dart';
import 'inspection_audio.dart';
import 'inspection_display.dart';
import 'inspection_part_card.dart';

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
    this.marks = const [],
    this.onRemoveMark,
    this.vehicleDetection,
    this.proposals = const {},
    super.key,
  });

  final String path;
  final List<PhotoMark> marks;
  final ValueChanged<int>? onRemoveMark;
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
          // Keep Image's own error widget visible when loading fails.
          if (frame == null) return image;
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
                        for (final (index, mark) in marks.indexed)
                          Positioned(
                            left: (mark.x * size.maxWidth - 20).clamp(
                              0.0,
                              (size.maxWidth - 40).clamp(0.0, double.infinity),
                            ),
                            top: (mark.y * size.maxHeight - 20).clamp(
                              0.0,
                              (size.maxHeight - 40).clamp(0.0, double.infinity),
                            ),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: IconButton.filled(
                                key: ValueKey('photo-mark-$index'),
                                tooltip: onRemoveMark == null
                                    ? '마크 ${index + 1}'
                                    : '마크 ${index + 1} 삭제',
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFC56D),
                                  foregroundColor: Colors.black,
                                  disabledBackgroundColor: const Color(
                                    0xFFFFC56D,
                                  ),
                                  disabledForegroundColor: Colors.black,
                                  side: const BorderSide(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                onPressed: onRemoveMark == null
                                    ? null
                                    : () => onRemoveMark!(index),
                                icon: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
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
  late FrontPart selectedPart = area.parts.first;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final vehicles = [
      ...store.activeVehicles,
      for (final v in store.vehicles)
        if (v.id == (vehicleId ?? widget.vehicleId) &&
            !store.activeVehicles.any((active) => active.id == v.id))
          v,
    ];
    final vehicle =
        vehicles
            .where((v) => v.id == (vehicleId ?? widget.vehicleId))
            .firstOrNull ??
        store.dashboardVehicles.firstOrNull ??
        vehicles.firstOrNull;
    if (vehicle == null) return empty('차량을 등록한 뒤 사진 점검을 시작해 주세요.');

    final history =
        store.inspections
            .where(
              (i) =>
                  i.vehicleId == vehicle.id &&
                  (i.area == area.recordArea ||
                      i.front.keys.any(area.parts.contains)),
            )
            .toList()
          ..sort((a, b) => b.created.compareTo(a.created));

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
                      child: Text(vehiclePickerLabel(v)),
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
                        selectedPart = item.parts.first;
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
                'AI 점검',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ResponsiveColumns(
                breakpoint: 690,
                children: [
                  InspectionDiagram(
                    area: area,
                    observations: latestInspectionParts(history),
                    selected: selectedPart,
                    onSave: (observations, memo) async {
                      final asset = area == FrontInspectionArea.engineBay
                          ? 'assets/branding/military-engine-bay.png'
                          : 'assets/branding/military-front-reference.png';
                      final bytes = await rootBundle.load(asset);
                      final directory =
                          await getApplicationDocumentsDirectory();
                      final folder = Directory(
                        '${directory.path}/inspection_images',
                      );
                      await folder.create(recursive: true);
                      final id = store.newId('VS');
                      final photo = File('${folder.path}/$id.png');
                      await photo.writeAsBytes(
                        bytes.buffer.asUint8List(
                          bytes.offsetInBytes,
                          bytes.lengthInBytes,
                        ),
                        flush: true,
                      );
                      try {
                        await store.saveInspection(
                          Inspection(
                            id: id,
                            vehicleId: vehicle.id,
                            area: area.recordArea,
                            mode: '디지털 트윈 시연',
                            created: store.clock().toIso8601String(),
                            imagePath: photo.path,
                            note: memo,
                            front: observations,
                          ),
                        );
                      } catch (_) {
                        if (await photo.exists()) await photo.delete();
                        rethrow;
                      }
                    },
                    onCapture: () {
                      Navigator.of(context, rootNavigator: true).pop();
                      context.push(
                        Uri(
                          path: '/vision',
                          queryParameters: {
                            'vehicle': vehicle.id,
                            'front': '1',
                            'area': area.name,
                          },
                        ).toString(),
                      );
                    },
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final part in area.parts)
                        InspectionPartCard(
                          part: part,
                          status:
                              latestInspectionParts(
                                history,
                              )[part]?.status.label ??
                              '미점검',
                          selected: selectedPart == part,
                          onTap: () => setState(() => selectedPart = part),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: '점검 기록',
          child: history.isEmpty
              ? empty('점검 기록이 없습니다.')
              : ResponsiveColumns(
                  children: [
                    for (final (index, inspection) in history.take(2).indexed)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${index == 0 ? '최근 점검' : '이전 점검'} · 마크 ${inspection.displayMarks.length}개',
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
                            observations: const {},
                            marks: inspection.displayMarks,
                          ),
                          if (inspection.note.isNotEmpty) Text(inspection.note),
                          if (inspection.audioPath case final path?)
                            InspectionAudioPlayback(path, key: ValueKey(path)),
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
