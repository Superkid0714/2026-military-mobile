import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:military_maintenance/data/adaptive_runtime.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/front_inspection.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/main.dart';
import 'package:military_maintenance/ui/front_inspection.dart';
import 'package:military_maintenance/ui/inspection_display.dart';

import 'data_tools_test.dart' show tapWithIo;
import 'ui_usability_test.dart' show setup, reveal, tap;

void main() {
  test('인식 점수는 모델 값을 유지하고 없거나 잘못된 값을 구분한다', () {
    Map<String, Object?> output(Object? score, {bool include = true}) => {
      'modelId': FrontPartProposal.modelId,
      'proposals': [
        {
          'part': 'hood',
          'box': [.2, .2, .6, .6],
          if (include) 'score': score,
        },
      ],
    };
    final found = FrontPartProposal.decode(output(.875))[FrontPart.hood]!;
    expect(found.score, .875);
    expect(found.scoreLabel, '인식 점수 87.5%');
    expect(
      FrontPartProposal.decode(
        output(null, include: false),
      )[FrontPart.hood]!.scoreLabel,
      '점수 없음',
    );
    for (final invalid in [-.1, 1.1, double.nan, double.infinity, '90%']) {
      expect(
        () => FrontPartProposal.decode(output(invalid)),
        throwsFormatException,
      );
    }
    expect(
      FrontPartProposal.decode({
        'modelId': FrontPartProposal.modelId,
        'proposals': [],
      }),
      isEmpty,
    );
  });

  testWidgets('분석 박스가 사진 비율을 유지하고 선택한 부위를 전달한다', (tester) async {
    final bytes = File('test/fixtures/manual_preview.jpg').readAsBytesSync();
    FrontPart? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 500,
              height: 300,
              child: DetectedPartsFrame(
                bytes: bytes,
                proposals: const {
                  FrontPart.hood: FrontPartProposal(.2, .25, .6, .75),
                },
                onSelected: (part) => selected = part,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    final picture = tester.getRect(find.byType(Image));
    final candidate = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == '보닛 위치 후보',
    );
    final box = tester.getRect(candidate);
    expect(box.left, closeTo(picture.left + picture.width * .2, .1));
    expect(box.top, closeTo(picture.top + picture.height * .25, .1));
    expect(box.width, closeTo(picture.width * .4, .1));
    expect(box.height, closeTo(picture.height * .5, .1));
    await tester.tap(candidate);
    expect(selected, FrontPart.hood);
    expect(tester.takeException(), isNull);
  });

  test('기존 사진 기록은 읽을 수 있고 잘못된 사진 좌표는 거부한다', () {
    expect(FrontObservation.decode(null), isEmpty);
    for (final observation in [
      {'status': 'checked', 'x': 1.5, 'y': .5},
      {'status': 'review', 'x': .5},
      {'status': 'hidden', 'x': .5, 'y': .5},
      {'status': 'unknown'},
    ]) {
      expect(
        () => FrontObservation.decode({'hood': observation}),
        throwsFormatException,
      );
    }
  });

  testWidgets('차량별 최근 부위 상태와 이전 사진을 나란히 표시한다', (tester) async {
    final store = await setup(tester, size: const Size(1280, 1000));
    final first = store.vehicles.first;
    final other = store.vehicles.firstWhere((v) => v.id != first.id);
    final path = File('test/fixtures/manual_preview.jpg').absolute.path;

    Inspection session(
      String id,
      String vehicle,
      String created,
      Map<FrontPart, FrontObservation> observations,
    ) => Inspection(
      id: id,
      vehicleId: vehicle,
      area: '전면',
      mode: '전면 점검',
      created: created,
      imagePath: path,
      note: '',
      front: observations,
    );

    await tester.runAsync(() async {
      await precacheImage(
        FileImage(File(path)),
        tester.element(find.byType(Scaffold).first),
      );
      await store.saveInspection(
        session('FRONT-1', first.id, '2026-10-08T12:00:00', {
          FrontPart.leftLamp: const FrontObservation(
            FrontCheck.review,
            x: .8,
            y: .5,
          ),
        }),
      );
      await store.saveInspection(
        session('FRONT-2', first.id, '2026-10-09T10:00:00', {
          FrontPart.leftLamp: const FrontObservation(
            FrontCheck.checked,
            x: .76,
            y: .5,
          ),
        }),
      );
      await store.saveInspection(
        session('FRONT-3', other.id, '2026-10-09T11:00:00', {
          FrontPart.leftLamp: const FrontObservation(FrontCheck.hidden),
        }),
      );
    });

    appRouter.go(frontMapUrl(first.id));
    await tester.pump();
    expect(find.text('왼쪽 전조등\n점검 완료'), findsOneWidget);
    expect(find.text('앞범퍼\n미점검'), findsOneWidget);
    await tester.tap(find.text('왼쪽 전조등\n점검 완료'));
    await tester.pumpAndSettle();
    expect(find.text('최근 점검 · 점검 완료'), findsOneWidget);
    expect(find.text('이전 점검 · 추가 확인'), findsOneWidget);
    expect(find.byType(FrontPhoto), findsNWidgets(2));

    appRouter.go(frontMapUrl(other.id));
    await tester.pumpAndSettle();
    expect(find.text('왼쪽 전조등\n사진에서 확인 어려움'), findsOneWidget);
    expect(find.text('왼쪽 전조등\n점검 완료'), findsNothing);
    await tap(tester, find.text('전면 사진 찍기'));
    expect(find.text('촬영 시작'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final area in FrontInspectionArea.values) {
    testWidgets('${area.label} 사진과 부위 표시를 저장하면 해당 지도가 갱신된다', (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'front-photo-test-',
      );
      final path = File('test/fixtures/manual_preview.jpg').absolute.path;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final runtimeCalls = <String>[];
      Completer<void>? inferenceGate;
      messenger.setMockMethodCallHandler(AndroidModelWorker.channel, (
        call,
      ) async {
        runtimeCalls.add(call.method);
        if (call.method == 'infer' && inferenceGate != null) {
          await inferenceGate.future;
        }
        return switch (call.method) {
          'modelInfo' => {
            'optionalModels': [
              {'modelId': FrontPartProposal.modelId, 'installed': true},
            ],
          },
          'capabilities' => {
            'totalRamBytes': 4294967296,
            'availableRamBytes': 2147483648,
            'cores': 4,
            'abis': ['arm64-v8a'],
            'androidApi': 34,
            'freeStorageBytes': 2147483648,
            'lowMemory': false,
            'cameraStatus': 'available',
          },
          'infer' => {
            'modelId': FrontPartProposal.modelId,
            'proposals': [
              {
                'part': 'hood',
                'box': [.2, .2, .5, .6],
              },
            ],
          },
          _ => null,
        };
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(AndroidModelWorker.channel, null);
      });
      final previousCamera = CameraPlatform.instance;
      final previousPaths = PathProviderPlatform.instance;
      final camera = _TestCamera(path);
      CameraPlatform.instance = camera;
      PathProviderPlatform.instance = _TestPaths(directory.path);
      addTearDown(() {
        CameraPlatform.instance = previousCamera;
        PathProviderPlatform.instance = previousPaths;
        directory.deleteSync(recursive: true);
      });

      final store = await setup(tester, size: const Size(1280, 1000));
      final vehicle = store.vehicles.first;
      appRouter.go(frontMapUrl(vehicle.id));
      await tester.pumpAndSettle();
      if (area == FrontInspectionArea.engineBay) {
        await tap(tester, find.widgetWithText(ChoiceChip, '엔진룸'));
      }
      await tap(tester, find.text(area.captureLabel));
      final start = find.text('촬영 시작');
      final shutter = find.text('촬영 및 기록');
      final capture = find.widgetWithText(FilledButton, '촬영 및 기록');
      await reveal(tester, start);
      await tapWithIo(
        tester,
        start,
        completed: () =>
            capture.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(capture).onPressed != null,
      );
      if (area == FrontInspectionArea.exterior) {
        await tapWithIo(
          tester,
          find.text('화면 분석 켜기'),
          completed: () => runtimeCalls.contains('infer'),
        );
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          if (find.byType(DetectedPartsFrame).evaluate().isNotEmpty) break;
        }
        expect(find.byType(DetectedPartsFrame), findsOneWidget);
        expect(store.inspections, isEmpty);
        await tester.tap(find.text('화면 분석 끄기'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DetectedPartsFrame), findsNothing);
        expect(File(path).existsSync(), isTrue);
      } else {
        expect(find.text('화면 분석 켜기'), findsNothing);
      }
      await reveal(tester, shutter);
      expect(find.byType(CameraAlignmentFrame), findsOneWidget);
      final guide = tester.widget<InspectionDiagram>(
        find.byType(InspectionDiagram),
      );
      expect(guide.area, area);
      expect(find.text('마지막 저장 상태'), findsOneWidget);
      if (area == FrontInspectionArea.exterior) {
        inferenceGate = Completer<void>();
        final previousCalls = runtimeCalls
            .where((call) => call == 'infer')
            .length;
        await tapWithIo(
          tester,
          find.text('화면 분석 켜기'),
          completed: () =>
              runtimeCalls.where((call) => call == 'infer').length >
              previousCalls,
        );
      }
      await tester.runAsync(() async {
        final picturesBeforeCapture = camera.pictures;
        await tester.tap(shutter);
        if (area == FrontInspectionArea.exterior) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(
            camera.pictures,
            picturesBeforeCapture,
            reason: '분석 중에는 기록 촬영을 겹쳐 실행하지 않는다',
          );
          inferenceGate!.complete();
        }
      });
      final images = Directory('${directory.path}/inspection_images');
      var copied = false;
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        final files = images.existsSync()
            ? images.listSync()
            : <FileSystemEntity>[];
        if (files.isNotEmpty && File(files.single.path).lengthSync() > 0) {
          await tester.runAsync(
            () => precacheImage(
              FileImage(File(files.single.path)),
              tester.element(find.byType(Scaffold).first),
            ),
          );
          copied = true;
          break;
        }
      }
      expect(copied, isTrue, reason: '분석 종료 후 점검 사진을 복사해야 한다');
      await tester.pumpAndSettle();

      final photo = find.byType(FrontPhoto);
      await reveal(tester, photo);
      if (area == FrontInspectionArea.engineBay) {
        expect(find.text('1. 배터리'), findsOneWidget);
        expect(find.text('1. 보닛 · 후보'), findsNothing);
        expect(tester.widget<FrontPhoto>(photo).proposals, isEmpty);
        await tester.tap(photo);
        await tester.pumpAndSettle();
        await tap(tester, find.widgetWithText(ChoiceChip, '점검 완료'));
        await tap(tester, find.text('2. 냉각수통'));
        await tap(tester, find.widgetWithText(ChoiceChip, '사진에서 확인 어려움'));
      } else {
        final candidate = find.text('1. 보닛 · 후보');
        for (var i = 0; i < 20 && candidate.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(candidate, findsOneWidget, reason: runtimeCalls.join(', '));
        expect(tester.widget<FrontPhoto>(photo).observations, isEmpty);
        expect(store.inspections, isEmpty);
        await tap(tester, find.widgetWithText(ChoiceChip, '점검 완료'));
        await tap(tester, find.text('3. 그릴'));
        await reveal(tester, photo);
        await tester.tap(photo);
        await tester.pumpAndSettle();
        await tap(tester, find.text('2. 왼쪽 전조등'));
        await tap(tester, find.widgetWithText(ChoiceChip, '사진에서 확인 어려움'));
      }
      final save = find.text('점검 저장');
      await reveal(tester, save);
      await tapWithIo(
        tester,
        save,
        completed: () => store.inspections.isNotEmpty,
      );
      final saved = store.inspections.single;
      expect(saved.vehicleId, vehicle.id);
      expect(saved.area, area.recordArea);
      expect(File(saved.imagePath).existsSync(), isTrue);
      if (area == FrontInspectionArea.engineBay) {
        expect(find.text('배터리\n점검 완료'), findsOneWidget);
        expect(find.text('냉각수통\n사진에서 확인 어려움'), findsOneWidget);
        expect(saved.front[FrontPart.battery]?.x, closeTo(.5, .05));
        expect(saved.front[FrontPart.coolantTank]?.status, FrontCheck.hidden);
        expect(runtimeCalls, isNot(contains('infer')));
        await tap(tester, find.widgetWithText(ChoiceChip, '전면 외관'));
        expect(find.text('보닛\n미점검'), findsOneWidget);
      } else {
        expect(find.text('보닛\n점검 완료'), findsOneWidget);
        expect(find.text('왼쪽 전조등\n사진에서 확인 어려움'), findsOneWidget);
        expect(saved.front[FrontPart.hood]?.x, closeTo(.35, .001));
        expect(saved.front[FrontPart.grille]?.x, closeTo(.5, .05));
        expect(saved.front[FrontPart.leftLamp]?.x, isNull);
      }
    });
  }
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.directory);
  final String directory;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory;

  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

class _TestCamera extends CameraPlatform {
  _TestCamera(this.path);

  final String path;
  int pictures = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'qa',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async => 1;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          640,
          480,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => Stream.multi((_) {});

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();

  @override
  Future<XFile> takePicture(int cameraId) async {
    pictures++;
    return XFile(path);
  }

  @override
  Future<void> dispose(int cameraId) async {}
}
