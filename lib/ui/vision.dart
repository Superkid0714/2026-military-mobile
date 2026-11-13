import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../data/store.dart';
import '../data/front_inspection.dart';
import '../data/local_vision.dart';
import '../data/model_execution.dart';
import '../data/adaptive_runtime.dart';
import 'components.dart';
import 'front_inspection.dart';
import 'inspection_display.dart';
import 'inspection_audio.dart';
import 'support.dart';
import 'vision_runtime.dart';

class VisionScreen extends ConsumerStatefulWidget {
  const VisionScreen({
    this.vehicleId,
    this.sessionId,
    this.part,
    this.inspectionArea,
    super.key,
  });
  final FrontInspectionArea? inspectionArea;
  bool get front => inspectionArea != null;
  final String? vehicleId;
  final String? sessionId;
  final String? part;
  @override
  ConsumerState<VisionScreen> createState() => _VisionState();
}

class _VisionState extends ConsumerState<VisionScreen>
    with WidgetsBindingObserver {
  int step = 0;
  String mode = '차량 촬영', area = '외관';
  String? vehicle, cameraError, imagePath, selectedSession;
  CameraController? controller;
  String? audioPath, audioPart;
  bool recording = false, audioSaved = false;

  Future<void> recordAudio() async {
    final path = imagePath;
    if (path == null || saving || recording) return;
    final part = widget.front ? '전체 사진' : standardPart(area);
    setState(() => recording = true);
    try {
      final audio = await inspectionAudioChannel.invokeMethod<String>(
        'record',
        {'path': path},
      );
      if (audio == '$path.m4a') {
        if (mounted && imagePath == path) {
          setState(() {
            audioPath = audio;
            audioPart = part;
          });
        } else {
          await _deleteDraftPhoto(audio!);
        }
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.code == 'permission'
                  ? '녹음하려면 마이크 권한을 허용해 주세요.'
                  : '녹음을 저장하지 못했습니다. 다시 시도해 주세요.',
            ),
          ),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('이 기기에서는 녹음할 수 없습니다.')));
      }
    } finally {
      if (mounted) setState(() => recording = false);
    }
  }

  Future<void> audioCommand(String command) async {
    try {
      await inspectionAudioChannel.invokeMethod<void>(command);
    } on PlatformException {
      // The recording request displays its result.
    } on MissingPluginException {
      // There is no native recorder on this platform.
    }
  }

  Widget audioControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        onPressed: saving
            ? null
            : recording
            ? () => audioCommand('finish')
            : recordAudio,
        icon: Icon(recording ? Icons.stop_circle_outlined : Icons.mic_none),
        label: Text(
          recording
              ? '녹음 끝내기'
              : audioPath == null
              ? '점검 소리 녹음 · 최대 15초'
              : '다시 녹음',
        ),
      ),
      if (recording) const Text('녹음 중 · 최대 15초'),
      if (!recording && audioPart != null) Text('녹음 부위 · $audioPart'),
      if (recording)
        TextButton(
          onPressed: () => audioCommand('cancel'),
          child: const Text('녹음 취소'),
        ),
      if (audioPath case final path?)
        if (!recording) InspectionAudioPlayback(path, key: ValueKey(path)),
    ],
  );

  bool initializing = false, capturing = false, saving = false, paused = false;
  int cameraGeneration = 0;
  bool cameraStarting = false, resumeCamera = false;
  final annotation = TextEditingController();
  final frontObservations = <FrontPart, FrontObservation>{};
  final photoMarks = <PhotoMark>[];
  late FrontPart frontPart;
  bool get engineBay => widget.inspectionArea == FrontInspectionArea.engineBay;
  String? draftId;
  VisionDetection? frontVehicleDetection;
  bool findingVehicle = false;
  String? vehicleDetectionMessage;

  Map<FrontPart, FrontPartProposal> frontProposals = const {};
  bool findingParts = false;
  String? frontProposalMessage;
  Timer? liveTimer;
  Future<void>? liveJob;
  bool liveAnalysis = false;
  bool liveStopping = false;
  int liveGeneration = 0;
  Uint8List? liveFrame;
  Map<FrontPart, FrontPartProposal> liveParts = const {};
  String? liveMessage;
  int? liveElapsedMs;

  void haltLiveAnalysis() {
    liveTimer?.cancel();
    liveTimer = null;
    liveAnalysis = false;
    liveGeneration++;
    liveFrame = null;
    liveParts = const {};
  }

  Future<void> stopLiveAnalysis() async {
    liveStopping = true;
    haltLiveAnalysis();
    try {
      await liveJob;
    } finally {
      liveStopping = false;
    }
  }

  void requestLiveAnalysis() {
    final camera = controller;
    if (!mounted ||
        !liveAnalysis ||
        liveJob != null ||
        step != 2 ||
        paused ||
        capturing ||
        camera?.value.isInitialized != true) {
      return;
    }
    final generation = liveGeneration;
    liveJob = analyzeCameraFrame(camera!, generation);
    unawaited(
      liveJob!.whenComplete(() {
        liveJob = null;
        if (mounted && liveAnalysis && generation == liveGeneration) {
          liveTimer = Timer(
            const Duration(milliseconds: 1800),
            requestLiveAnalysis,
          );
        }
      }),
    );
  }

  Future<void> analyzeCameraFrame(
    CameraController camera,
    int generation,
  ) async {
    String? temporaryPath;
    final clock = Stopwatch()..start();
    try {
      final photo = await camera.takePicture();
      final directory = await getTemporaryDirectory();
      final source = File(photo.path);
      if (source.absolute.path.startsWith('${directory.absolute.path}/')) {
        temporaryPath = photo.path;
      }
      if (!mounted || !liveAnalysis || generation != liveGeneration) return;
      final bytes = await photo.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) throw StateError('frame_too_large');
      final run = await ref.read(adaptiveRuntimeProvider).run(
        ModelTask.frontParts,
        {'imagePath': photo.path},
      );
      if (run.mode != 'model' || run.output == null) {
        throw StateError('front_parts_unavailable');
      }
      final parts = FrontPartProposal.decode(run.output!);
      if (!mounted || !liveAnalysis || generation != liveGeneration) return;
      setState(() {
        liveFrame = bytes;
        liveParts = parts;
        liveElapsedMs = clock.elapsedMilliseconds;
        liveMessage = parts.isEmpty
            ? '인식된 부품이 없습니다. 전면 전체가 보이게 맞춰 주세요.'
            : '찾은 부위를 눌러 차량 상태도에서 확인하세요.';
      });
    } catch (_) {
      if (mounted && liveAnalysis && generation == liveGeneration) {
        setState(() {
          haltLiveAnalysis();
          liveElapsedMs = null;
          liveMessage = '화면을 분석하지 못했습니다. 다시 시작해 주세요.';
        });
      }
    } finally {
      if (temporaryPath != null) {
        await _deleteDraftPhoto(temporaryPath);
      }
    }
  }

  Future<void> findFrontParts(String path) async {
    if (!mounted || imagePath != path || findingParts) return;
    final target = ref
        .read(storeProvider)
        .vehicle(vehicle!)
        .model
        .toLowerCase();
    if (!target.contains('렉스턴 스포츠') && !target.contains('rexton sports')) {
      return;
    }
    final runtime = ref.read(adaptiveRuntimeProvider);
    if (!runtime.installedModels.any(
      (model) => model.task == ModelTask.frontParts,
    )) {
      return;
    }
    setState(() => findingParts = true);
    try {
      final result = await runtime.run(ModelTask.frontParts, {
        'imagePath': path,
      });
      if (result.mode != 'model') throw StateError('front_parts_unavailable');
      final proposals = FrontPartProposal.decode(result.output!);
      if (!mounted || imagePath != path || step != 3) return;
      setState(() {
        frontProposals = proposals;
        frontProposalMessage = proposals.isEmpty
            ? '찾은 부위가 없습니다. 사진에서 직접 표시하세요.'
            : '노란 테두리는 후보입니다. 위치를 확인하고 결과를 선택하세요.';
      });
    } catch (_) {
      if (mounted && imagePath == path && step == 3) {
        setState(() => frontProposalMessage = '부위를 직접 표시해 주세요.');
      }
    } finally {
      if (mounted && imagePath == path) setState(() => findingParts = false);
    }
  }

  Future<void> findVehicleInPhoto() async {
    final path = imagePath;
    if (path == null || findingVehicle || findingParts || saving) return;
    setState(() {
      findingVehicle = true;
      frontVehicleDetection = null;
      vehicleDetectionMessage = null;
    });
    try {
      final result = await ref.read(adaptiveRuntimeProvider).run(
        ModelTask.vision,
        {'imagePath': path},
      );
      if (result.mode != 'model') throw StateError('vision_unavailable');
      final analysis = VisionAnalysis.parse(result.output!);
      final vehicles =
          analysis.detections
              .where((d) => d.classId == 3 || d.classId == 8)
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score));
      if (!mounted) return;
      setState(() {
        frontVehicleDetection = vehicles.firstOrNull;
        vehicleDetectionMessage = vehicles.isEmpty
            ? '차량 영역을 찾지 못했습니다. 사진에서 부위를 직접 지정해 주세요.'
            : '파란 테두리는 찾은 차량 영역입니다. 부위는 직접 지정해 주세요.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => vehicleDetectionMessage =
              '차량 영역을 찾을 수 없습니다. 부위를 직접 지정해 계속할 수 있습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => findingVehicle = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.part != null && widget.part!.isNotEmpty) {
      area = standardPart(widget.part!);
      mode = '부품 촬영';
    }
    if (widget.front) {
      step = 1;
      area = widget.inspectionArea!.recordArea;
      mode = engineBay ? '엔진룸 점검' : '전면 점검';
      frontPart =
          widget.inspectionArea!.parts
              .where((item) => item.name == widget.part)
              .firstOrNull ??
          widget.inspectionArea!.parts.first;
    }
    if (widget.sessionId != null) {
      selectedSession = widget.sessionId;
      step = 4;
    }
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _deleteDraftPhoto(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // The file may already have been removed.
    }
  }

  @override
  void dispose() {
    if (recording) unawaited(audioCommand('cancel'));
    if (!saving && !audioSaved && audioPath != null) {
      unawaited(_deleteDraftPhoto(audioPath!));
    }
    if (widget.front && draftId == null && imagePath != null) {
      unawaited(_deleteDraftPhoto(imagePath!));
    }
    WidgetsBinding.instance.removeObserver(this);
    haltLiveAnalysis();
    cameraGeneration++;
    controller?.dispose();
    annotation.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // A permission dialog briefly makes the app inactive. Keep its single
      // initialization request alive until the user has answered.
      if (state == AppLifecycleState.inactive && cameraStarting) return;
      resumeCamera = resumeCamera || controller?.value.isInitialized == true;
      haltLiveAnalysis();
      cameraGeneration++;
      final old = controller;
      controller = null;
      old?.dispose();
      if (mounted) setState(() => initializing = false);
    } else if (state == AppLifecycleState.resumed &&
        step == 2 &&
        resumeCamera &&
        !cameraStarting) {
      resumeCamera = false;
      startCamera();
    }
  }

  Future<void> startCamera() async {
    if (cameraStarting) return;
    cameraStarting = true;
    resumeCamera = false;
    try {
      await stopLiveAnalysis();
      await openCamera();
    } finally {
      cameraStarting = false;
    }
  }

  Future<void> openCamera() async {
    final runtime = ref.read(adaptiveRuntimeProvider);
    await runtime.refreshDevice();
    if (!mounted) return;
    if (runtime.device?.cameraBlocked == true) {
      cameraGeneration++;
      final old = controller;
      controller = null;
      await old?.dispose();
      if (!mounted) return;
      runtime.cameraFailed();
      setState(
        () =>
            cameraError = '기기 정책 또는 하드웨어로 카메라를 사용할 수 없습니다. 수동 부품 선택을 이용해 주세요.',
      );
      return;
    }
    final generation = ++cameraGeneration;
    final old = controller;
    controller = null;
    await old?.dispose();
    if (!mounted) return;
    setState(() {
      initializing = true;
      cameraError = null;
      paused = false;
    });
    CameraController? next;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('camera unavailable');
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      next = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await next.initialize();
      if (!mounted || generation != cameraGeneration) {
        await next.dispose();
        return;
      }
      setState(() => controller = next);
      runtime.cameraOpened();
    } catch (e) {
      runtime.cameraFailed();
      await next?.dispose();
      if (mounted && generation == cameraGeneration) {
        setState(
          () => cameraError =
              e is CameraException &&
                  (e.code.contains('AccessDenied') ||
                      e.code.contains('Permission'))
              ? '카메라 권한이 필요합니다. 기기 설정에서 카메라 권한을 허용한 후 다시 연결해 주세요.'
              : '카메라에 연결할 수 없습니다. 수동 부품 선택을 이용하거나 카메라를 재연결해 주세요.',
        );
      }
    } finally {
      if (mounted && generation == cameraGeneration) {
        setState(() => initializing = false);
      }
    }
  }

  Future<void> capture() async {
    if (controller == null || !controller!.value.isInitialized || capturing) {
      return;
    }
    setState(() => capturing = true);
    try {
      await stopLiveAnalysis();
      if (!mounted || controller?.value.isInitialized != true) return;
      final photo = await controller!.takePicture();
      final folder = await getApplicationDocumentsDirectory();
      final images = Directory('${folder.path}/inspection_images');
      await images.create(recursive: true);
      final path =
          '${images.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(photo.path).copy(path);
      if (!mounted) {
        await _deleteDraftPhoto(path);
        return;
      }
      final previousPath = imagePath;
      if (widget.front && draftId == null && previousPath != null) {
        unawaited(_deleteDraftPhoto(previousPath));
      }
      cameraGeneration++;
      await controller?.dispose();
      controller = null;
      if (mounted) {
        setState(() {
          if (!audioSaved && audioPath != null) {
            unawaited(_deleteDraftPhoto(audioPath!));
          }
          audioPath = null;
          audioPart = null;
          audioSaved = false;
          imagePath = path;
          draftId = null;
          frontObservations.clear();
          photoMarks.clear();
          frontProposals = const {};
          frontProposalMessage = null;
          findingParts = false;
          frontVehicleDetection = null;
          vehicleDetectionMessage = null;
          step = 3;
        });
      } else {
        await _deleteDraftPhoto(path);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('촬영하지 못했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => capturing = false);
    }
  }

  Future<void> save() async {
    if (imagePath == null ||
        vehicle == null ||
        saving ||
        recording ||
        findingVehicle) {
      return;
    }
    setState(() => saving = true);
    try {
      final s = ref.read(storeProvider);
      final id = draftId ??= s.newId('VS');
      await s.saveInspection(
        Inspection(
          id: id,
          vehicleId: vehicle!,
          area: area,
          mode: widget.front ? '전체 사진 점검' : mode,
          created: s.clock().toIso8601String(),
          imagePath: imagePath!,
          audioPath: audioPath,
          audioPart: audioPart,
          note: annotation.text.trim(),
          marks: List.of(photoMarks),
        ),
      );
      audioSaved = true;
      if (mounted) {
        if (widget.front) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(frontMapUrl(vehicle, widget.inspectionArea!));
          }
          return;
        }
        setState(() {
          selectedSession = id;
          step = 4;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('점검 기록을 저장하지 못했습니다. 다시 시도해 주세요.')),
        );
      } else if (audioPath != null) {
        await _deleteDraftPhoto(audioPath!);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(storeProvider);
    if (widget.front && !s.vehicles.any((v) => v.id == widget.vehicleId)) {
      return empty('전면 점검할 차량을 지도에서 다시 선택해 주세요.');
    }
    vehicle ??= s.vehicles.any((v) => v.id == widget.vehicleId)
        ? widget.vehicleId
        : s.activeVehicles.firstOrNull?.id;
    if (vehicle == null || !s.vehicles.any((v) => v.id == vehicle)) {
      return empty('점검할 차량을 찾을 수 없습니다.');
    }
    return ListView(
      key: widget.front ? ValueKey(step) : null,
      children: [
        PageTitle(
          widget.front
              ? [
                  mode,
                  '1. 차량 확인',
                  engineBay ? '2. 엔진룸 촬영' : '2. 전면 촬영',
                  '3. 사진 마크·메모',
                  '사진 기록',
                ][step]
              : ['사진 점검', '대상 지정', '실시간 촬영', '촬영 결과', '사진 기록'][step],
          widget.front && step == 3 ? '사진에 마크 추가 → 메모 작성 → 저장' : '',
          scopeVehicles: [s.vehicle(vehicle!)],
          action: step == 0
              ? TextButton(
                  onPressed: () => setState(() => step = 4),
                  child: const Text('사진 기록'),
                )
              : null,
        ),
        if (ref.watch(adaptiveRuntimeProvider).cameraBlocked &&
            step < (widget.front ? 3 : 4))
          Panel(
            title: '카메라 사용 불가 · 수동 부품 선택',
            subtitle: '다시 연결하거나 부품을 직접 선택하세요.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: const ValueKey('manual-vehicle-without-camera'),
                  initialValue: vehicle,
                  decoration: const InputDecoration(labelText: '차량 선택'),
                  items: s.vehicles
                      .map(
                        (v) => DropdownMenuItem(
                          value: v.id,
                          child: Text(vehiclePickerLabel(v)),
                        ),
                      )
                      .toList(),
                  onChanged: widget.front
                      ? null
                      : (v) => setState(() => vehicle = v ?? vehicle),
                ),
                DropdownButtonFormField<String>(
                  key: const ValueKey('manual-part-without-camera'),
                  initialValue: area,
                  decoration: const InputDecoration(labelText: '부품 선택'),
                  items:
                      {
                            area,
                            ...standardParts.keys,
                            ...s.supportLibrary.knowledge.concepts.map(
                              (c) => c['name'] as String,
                            ),
                          }
                          .map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => area = v ?? area),
                ),
                FilledButton(
                  key: const ValueKey('manual-part-support'),
                  onPressed: () => context.go(supportUrl(vehicle!, area)),
                  child: const Text('책자와 수리 기록'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => step = 2);
                    startCamera();
                  },
                  child: const Text('카메라 다시 연결'),
                ),
              ],
            ),
          )
        else if (step == 0)
          _mode()
        else if (step == 1)
          _target(s)
        else if (step == 2)
          _live(s)
        else if (step == 3)
          _frontResult()
        else
          _sessions(s),
      ],
    );
  }

  Widget _mode() => Panel(
    title: '무엇을 찍을까요?',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => context.push(frontMapUrl(vehicle)),
          icon: const Icon(Icons.directions_car_outlined),
          label: const Text('전면 점검'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () =>
              context.push(frontMapUrl(vehicle, FrontInspectionArea.engineBay)),
          icon: const Icon(Icons.build_outlined),
          label: const Text('엔진룸 점검'),
        ),
        const SizedBox(height: 16),
        const Text('일반 촬영'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in ['차량 촬영', '부품 촬영'])
              ChoiceChip(
                label: Text(value),
                selected: mode == value,
                onSelected: (_) => setState(() => mode = value),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => step = 1),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('시작하기'),
          ),
        ),
      ],
    ),
  );

  Widget _target(AppStore s) => Panel(
    title: widget.front ? '선택한 차량 확인' : '점검 대상을 확인해 주세요',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.front)
          Text(
            vehiclePickerLabel(s.vehicle(vehicle!)),
            style: const TextStyle(fontWeight: FontWeight.w700),
          )
        else ...[
          const Text('차량', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: vehicle,
            isExpanded: true,
            items: [
              for (final v in s.vehicles)
                DropdownMenuItem(
                  value: v.id,
                  child: Text(vehiclePickerLabel(v)),
                ),
            ],
            onChanged: (v) => setState(() => vehicle = v),
          ),
        ],
        if (!widget.front) ...[
          const SizedBox(height: 16),
          const Text('점검 부위', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children:
                {
                      '외관',
                      '차체',
                      '창문',
                      '조명',
                      '하부',
                      '엔진룸',
                      ...standardParts.keys,
                      area,
                    }
                    .map(
                      (a) => ChoiceChip(
                        label: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(a),
                        ),
                        selected: area == a,
                        onSelected: (_) => setState(() => area = a),
                      ),
                    )
                    .toList(),
          ),
        ],
        const SizedBox(height: 16),
        note('주변 안전을 확보하고 장비가 정차된 상태인지 확인해 주세요.'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton(
              onPressed: () {
                if (widget.front) {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(frontMapUrl(vehicle, widget.inspectionArea!));
                  }
                } else {
                  setState(() => step = 0);
                }
              },
              child: const Text('이전'),
            ),
            FilledButton.icon(
              onPressed: () {
                setState(() => step = 2);
                startCamera();
              },
              icon: const DesignIcon('1:2565', 'imgCamera'),
              label: const Text('촬영 시작'),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _live(AppStore store) {
    final ready = controller?.value.isInitialized == true;
    final inspectionArea = widget.inspectionArea;
    final latest = inspectionArea == null
        ? const <FrontPart, FrontObservation>{}
        : latestInspectionParts(
            store.inspections.where((record) => record.vehicleId == vehicle),
          );
    final modelSupported =
        !widget.front &&
        inspectionArea == FrontInspectionArea.exterior &&
        [
          '렉스턴 스포츠',
          'rexton sports',
        ].any(store.vehicle(vehicle!).model.toLowerCase().contains);
    final modelInstalled = ref
        .watch(adaptiveRuntimeProvider)
        .installedModels
        .any((model) => model.task == ModelTask.frontParts);
    final actions = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        if (modelSupported)
          OutlinedButton.icon(
            onPressed:
                !ready || capturing || paused || liveStopping || !modelInstalled
                ? null
                : () async {
                    if (liveStopping) return;
                    if (liveAnalysis) {
                      await stopLiveAnalysis();
                      if (mounted) setState(() => liveMessage = null);
                    } else {
                      setState(() {
                        liveAnalysis = true;
                        liveMessage = '카메라 장면에서 부위를 찾고 있어요.';
                        liveElapsedMs = null;
                      });
                      requestLiveAnalysis();
                    }
                  },
            icon: Icon(
              liveAnalysis
                  ? Icons.stop_circle_outlined
                  : Icons.center_focus_strong,
            ),
            label: Text(liveAnalysis ? '화면 분석 끄기' : '화면 분석 켜기'),
          ),
        OutlinedButton(
          onPressed: capturing
              ? null
              : () async {
                  await stopLiveAnalysis();
                  cameraGeneration++;
                  await controller?.dispose();
                  controller = null;
                  if (mounted) setState(() => step = 1);
                },
          child: const Text('대상 변경'),
        ),
        OutlinedButton.icon(
          onPressed: !ready || capturing || liveStopping
              ? null
              : () async {
                  try {
                    await stopLiveAnalysis();
                    if (paused) {
                      await controller!.resumePreview();
                    } else {
                      await controller!.pausePreview();
                    }
                    if (mounted) setState(() => paused = !paused);
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('미리보기 상태를 변경하지 못했습니다.')),
                      );
                    }
                  }
                },
          icon: const DesignIcon('1:2728', 'imgPause'),
          label: Text(paused ? '미리보기 재개' : '화면 고정'),
        ),
        FilledButton.icon(
          onPressed: !ready || capturing ? null : capture,
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(capturing ? '촬영 중…' : '촬영 및 기록'),
        ),
      ],
    );
    return Panel(
      title: '${vehicleLabel(vehicle!)} · $area',
      child: Column(
        children: [
          ResponsiveColumns(
            flexes: const [5, 3],
            breakpoint: 760,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 10,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: scanBackground),
                          if (ready)
                            Center(
                              child: AspectRatio(
                                aspectRatio: controller!.value.aspectRatio,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CameraPreview(controller!),
                                    const CameraAlignmentFrame(),
                                  ],
                                ),
                              ),
                            )
                          else if (initializing)
                            const Center(
                              child: CircularProgressIndicator(
                                color: scanAccent,
                              ),
                            )
                          else
                            Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  44,
                                  12,
                                  8,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.videocam_outlined,
                                      color: scanAccent,
                                      size: 28,
                                    ),
                                    Text(
                                      cameraError ?? '카메라 연결 대기',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: scanAccent,
                                      ),
                                      onPressed: startCamera,
                                      child: const Text('카메라 다시 연결'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (liveFrame != null)
                            ColoredBox(
                              color: scanBackground,
                              child: DetectedPartsFrame(
                                bytes: liveFrame!,
                                proposals: liveParts,
                                onSelected: (part) =>
                                    setState(() => frontPart = part),
                              ),
                            ),
                          Positioned(
                            top: 8,
                            left: 8,
                            right: 8,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: scanBackground.withValues(alpha: .94),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  ready
                                      ? (liveFrame != null
                                            ? '최근 분석 장면 · ${liveElapsedMs ?? 0}ms'
                                            : paused
                                            ? '미리보기 고정'
                                            : '● 카메라 미리보기')
                                      : '카메라 연결 상태',
                                  style: const TextStyle(
                                    color: scanAccent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  actions,
                  if (liveMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(liveMessage!),
                  ],
                  if (liveFrame != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '최근 분석 장면 · ${liveElapsedMs ?? 0}ms',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final part in liveParts.keys)
                          ActionChip(
                            label: Text(
                              '${part.number}. ${part.label} · ${liveParts[part]!.scoreLabel}',
                            ),
                            onPressed: () => setState(() => frontPart = part),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
              if (!widget.front)
                Panel(
                  title: '촬영 안내',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        engineBay
                            ? '엔진룸 전체가 틀 안에 들어오게 맞추세요.'
                            : widget.front
                            ? '보닛부터 앞범퍼까지 틀 안에 넣으세요.'
                            : '점검할 차량이나 부품을 틀 안에 넣으세요.',
                      ),
                      if (engineBay) ...[
                        const SizedBox(height: 8),
                        const Text('엔진룸은 촬영한 사진에서 부위를 직접 표시해 주세요.'),
                      ],
                      if (modelSupported && !modelInstalled) ...[
                        const SizedBox(height: 8),
                        const Text('부위 분석 모델을 준비한 뒤 화면 분석을 사용할 수 있어요.'),
                      ],
                      if (liveFrame != null) ...[
                        const SizedBox(height: 12),
                        const Text(
                          '이번 장면',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        for (final part in FrontInspectionArea.exterior.parts)
                          if (liveParts[part] case final result?)
                            TextButton(
                              onPressed: () => setState(() => frontPart = part),
                              child: Text(
                                '${part.label} · ${result.scoreLabel}',
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Text(
                                '${part.label} · 미인식',
                                style: const TextStyle(color: muted),
                              ),
                            ),
                        const Text(
                          '인식 점수는 부품의 특징과 얼마나 가까운지 나타냅니다. 고장 확률이나 실제 정확도는 아닙니다.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                      if (liveParts.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('찾은 위치는 부위 후보입니다. 상태는 사진을 저장한 뒤 확인해 주세요.'),
                      ],
                      if (inspectionArea != null) ...[
                        const SizedBox(height: 12),
                        const Text(
                          '마지막 저장 상태',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        for (final part in inspectionArea.parts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${part.number}. ${part.label} · ${latest[part]?.status.label ?? '미점검'}',
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _frontResult() => Panel(
    title: '사진 확인 및 기록',
    subtitle: '사진을 누르면 마크가 추가됩니다. 마크를 다시 누르면 삭제됩니다.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FrontPhoto(
          path: imagePath!,
          observations: const {},
          marks: photoMarks,
          onMark: saving || recording
              ? null
              : (offset) => setState(() {
                  if (photoMarks.length < 100) {
                    photoMarks.add(PhotoMark(offset.dx, offset.dy));
                  }
                }),
          onRemoveMark: saving || recording
              ? null
              : (index) => setState(() => photoMarks.removeAt(index)),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('마크 ${photoMarks.length}개 / 100개'),
            TextButton.icon(
              onPressed: saving || recording || photoMarks.isEmpty
                  ? null
                  : () => setState(() => photoMarks.removeLast()),
              icon: const Icon(Icons.undo),
              label: const Text('마지막 마크 취소'),
            ),
            TextButton(
              onPressed: saving || recording || photoMarks.isEmpty
                  ? null
                  : () => setState(photoMarks.clear),
              child: const Text('마크 모두 지우기'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: annotation,
          enabled: !saving,
          minLines: 2,
          maxLines: 4,
          maxLength: 10000,
          decoration: const InputDecoration(
            labelText: '점검 메모',
            hintText: '예: 1번 위치 오염, 2번 위치 누유 흔적 확인',
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        audioControls(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: saving || recording
                  ? null
                  : () {
                      setState(() => step = 2);
                      startCamera();
                    },
              child: const Text('다시 촬영'),
            ),
            FilledButton(
              onPressed: saving || recording ? null : save,
              child: Text(saving ? '저장 중…' : '사진·점검 기록 저장'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _sessions(AppStore s) {
    final records = s.inspections.where((i) => i.vehicleId == vehicle).toList();
    final selected =
        records.where((i) => i.id == selectedSession).firstOrNull ??
        records.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          title: '저장된 점검 세션',
          subtitle: '차량 $vehicle · ${records.length}건',
          action: TextButton(
            onPressed: () => setState(() => step = 0),
            child: const Text('새 점검'),
          ),
          child: records.isEmpty
              ? empty('아직 저장된 촬영 기록이 없습니다.')
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: records
                      .map(
                        (i) => SizedBox(
                          width: 190,
                          child: InkWell(
                            onTap: () => setState(() => selectedSession = i.id),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: selected?.id == i.id ? green : line,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: 125,
                                    child: Image.file(
                                      File(i.imagePath),
                                      cacheWidth: 570,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, e, stack) =>
                                          const Center(child: Text('원본 파일 없음')),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        cell(i.area, bold: true),
                                        cell(
                                          i.created
                                              .substring(0, 16)
                                              .replaceAll('T', ' '),
                                          color: muted,
                                        ),
                                        cell(
                                          '사진 기록 · 마크 ${i.displayMarks.length}개',
                                          color: muted,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 16),
          if (selected.mode != '전체 사진 점검' &&
              selected.front.isEmpty &&
              ref
                  .watch(adaptiveRuntimeProvider)
                  .installedModels
                  .any((m) => m.id == 'ssd-mobilenet-int8-public-v1')) ...[
            VisionRuntimePanel(inspection: selected),
            const SizedBox(height: 16),
          ],
          Panel(
            title: '점검 기록 상세',
            subtitle: selected.id,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cell(
                  '차량 ${selected.vehicleId} · ${selected.mode} · ${selected.area}',
                  bold: true,
                ),
                const SizedBox(height: 12),
                Text(selected.note.isEmpty ? '점검 메모 없음' : selected.note),
                if (selected.audioPart != null)
                  Text('녹음 부위 · ${selected.audioPart}'),
                if (selected.audioPath case final path?)
                  InspectionAudioPlayback(path, key: ValueKey(path)),
                const SizedBox(height: 12),
                FrontPhoto(
                  path: selected.imagePath,
                  observations: const {},
                  marks: selected.displayMarks,
                ),
                Text('마크 ${selected.displayMarks.length}개'),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: () => context.go(
                        supportUrl(
                          selected.vehicleId,
                          selected.area,
                          selected.id,
                        ),
                      ),
                      child: const Text('부품 근거·정비 이력 연결'),
                    ),
                    OutlinedButton(
                      onPressed: () =>
                          context.go('/vehicles/${selected.vehicleId}'),
                      child: const Text('차량 상세로 이동'),
                    ),
                    FilledButton(
                      onPressed: () => context.go(
                        Uri(
                          path: '/entry',
                          queryParameters: {
                            'vehicle': selected.vehicleId,
                            'inspection': selected.id,
                          },
                        ).toString(),
                      ),
                      child: const Text('정비 기록 등록'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
