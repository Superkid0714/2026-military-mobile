import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:military_maintenance/data/front_inspection.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/data/adaptive_runtime.dart';
import 'package:military_maintenance/main.dart';
import 'package:military_maintenance/ui/front_inspection.dart';
import 'package:military_maintenance/ui/inspection_display.dart';
import 'package:military_maintenance/ui/inspection_demo.dart';

import 'ui_usability_test.dart' show setup, reveal, tap;
import 'data_tools_test.dart' show tapWithIo;

void main() {
  test('사진 마크 좌표 검증과 이전 기록 호환', () {
    final data = Inspection(
      id: 'VS1',
      vehicleId: 'V1',
      area: '전면',
      mode: '전체 사진 점검',
      created: '2026-11-13T10:00:00',
      imagePath: '/photo.png',
      note: '',
      marks: const [PhotoMark(.2, .3), PhotoMark(1, 0)],
    ).toJson();
    expect(Inspection.fromJson(data).marks[0].x, .2);
    expect(Inspection.fromJson(Map.of(data)..remove('marks')).marks, isEmpty);
    for (final invalid in [
      [
        {'x': -1, 'y': .2},
      ],
      [
        {'x': double.nan, 'y': .2},
      ],
      List.filled(101, {'x': .2, 'y': .3}),
    ]) {
      expect(() => PhotoMark.decode(invalid), throwsFormatException);
    }
  });

  for (final area in FrontInspectionArea.values) {
    testWidgets('${area.label} AI 점검 시연 진입과 순차 검사를 유지한다', (tester) async {
      final store = await setup(tester, size: const Size(1440, 1200));
      appRouter.go(frontMapUrl(store.vehicles.first.id, area));
      await tester.pumpAndSettle();
      expect(find.byType(InspectionDiagram), findsOneWidget);
      await tap(tester, find.byType(InspectionDiagram));
      expect(find.byType(InspectionDemo), findsOneWidget);
      expect(find.text('새 결과 따라보기'), findsNothing);
      await tap(tester, find.text('AI 점검 시작'));
      await tester.pump(const Duration(seconds: 13));
      expect(find.textContaining('확인 순서'), findsOneWidget);
      await tap(tester, find.text('점검 계속'));
      await tester.pump(const Duration(seconds: 17));
      expect(find.textContaining('전체 점검 종료'), findsOneWidget);
      expect(find.text('사진·점검 기록 저장'), findsOneWidget);
      expect(find.text('직접 촬영해서 기록'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final area in FrontInspectionArea.values) {
    testWidgets('${area.label} 전체 촬영·여러 마크·삭제·저장·재조회', (tester) async {
      final store = await setup(tester, size: const Size(1440, 1100));
      late Directory dir;
      late String path;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('whole-photo-');
        path = '${dir.path}/camera.jpg';
        await File('test/fixtures/manual_preview.jpg').copy(path);
      });
      final oldCamera = CameraPlatform.instance;
      final oldPaths = PathProviderPlatform.instance;
      CameraPlatform.instance = _TestCamera(path);
      PathProviderPlatform.instance = _TestPaths(dir.path);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        AndroidModelWorker.channel,
        (call) async => switch (call.method) {
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
          'modelInfo' => {'optionalModels': []},
          _ => null,
        },
      );
      addTearDown(() async {
        CameraPlatform.instance = oldCamera;
        PathProviderPlatform.instance = oldPaths;
        messenger.setMockMethodCallHandler(AndroidModelWorker.channel, null);
        await tester.runAsync(() => dir.delete(recursive: true));
      });
      final vehicle = store.vehicles.first;
      appRouter.go(frontMapUrl(vehicle.id, area));
      await tester.pumpAndSettle();
      expect(find.text('부위별 상태'), findsNothing);
      await tap(tester, find.text(area.captureLabel));
      await tapWithIo(tester, find.text('촬영 시작'));
      final shutter = find.text('촬영 및 기록');
      await reveal(tester, shutter);
      await tapWithIo(tester, shutter);
      expect(find.text('사진 확인 및 기록'), findsOneWidget);
      expect(find.textContaining('부위별'), findsNothing);
      expect(find.text('점검 완료'), findsNothing);
      expect(find.text('추가 확인'), findsNothing);
      expect(find.text('사진에서 확인 어려움'), findsNothing);
      final photo = find.byType(FrontPhoto);
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find
            .descendant(of: photo, matching: find.byType(LayoutBuilder))
            .evaluate()
            .isNotEmpty)
          break;
      }
      expect(
        find.descendant(of: photo, matching: find.byType(LayoutBuilder)),
        findsOneWidget,
      );
      await reveal(tester, photo);
      final bounds = tester.getRect(
        find.descendant(of: photo, matching: find.byType(Image)).first,
      );
      await tester.tapAt(
        Offset(
          bounds.left + bounds.width * .25,
          bounds.top + bounds.height * .3,
        ),
      );
      await tester.pump();
      await tester.tapAt(
        Offset(
          bounds.left + bounds.width * .7,
          bounds.top + bounds.height * .6,
        ),
      );
      await tester.pump();
      expect(tester.widget<FrontPhoto>(photo).marks, hasLength(2));
      await tester.tap(find.byKey(const ValueKey('photo-mark-0')));
      await tester.pump();
      expect(tester.widget<FrontPhoto>(photo).marks, hasLength(1));
      await tester.enterText(
        find.widgetWithText(TextField, '점검 메모'),
        '1번 위치 확인',
      );
      final save = find.text('사진·점검 기록 저장');
      await reveal(tester, save);
      await tapWithIo(
        tester,
        save,
        completed: () => store.inspections.isNotEmpty,
      );
      final record = store.inspections.single;
      expect(record.front, isEmpty);
      expect(record.marks, hasLength(1));
      expect(record.marks.single.x, closeTo(.7, .03));
      expect(record.note, '1번 위치 확인');
      expect(record.area, area.recordArea);
      expect(find.text('점검 기록'), findsOneWidget);
      expect(
        tester.widget<FrontPhoto>(find.byType(FrontPhoto)).marks,
        hasLength(1),
      );
      await tester.runAsync(() async {
        expect(await File(record.imagePath).exists(), isTrue);
      });
      expect(tester.takeException(), isNull);
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
