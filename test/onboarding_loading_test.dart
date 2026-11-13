import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/main.dart';
import 'package:military_maintenance/ui/onboarding.dart';
import 'package:military_maintenance/ui/maintenance_loading.dart';
import 'package:military_maintenance/ui/maintenance_mascot.dart';

import 'analysis_visualization_test.dart' show prepare;

Future<void> snapshot(WidgetTester tester, String name) async {
  final target = Platform.environment['QA_ONBOARD_DIR'];
  if (target == null) return;
  if (!Directory(target).absolute.path.contains('/private/')) {
    throw StateError('Private screenshots required');
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final im = await boundary.toImage();
    final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
    im.dispose();
    await Directory(target).create(recursive: true);
    await File('$target/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  test('온보딩은 완료 전에는 유지하고 완료 후 재시작해도 기억한다', () async {
    final dir = Directory.systemTemp.createTempSync('onboard-');
    final path = '${dir.path}/state.sqlite';
    final store = AppStore();
    await store.initialize(database: LocalDatabase(NativeDatabase(File(path))));
    expect(store.onboardingCompleted, isFalse);
    await store.completeOnboarding();
    expect(store.onboardingCompleted, isTrue);
    await store.db!.close();
    final reopened = AppStore();
    await reopened.initialize(
      database: LocalDatabase(NativeDatabase(File(path))),
    );
    expect(reopened.onboardingCompleted, isTrue);
    await reopened.db!.close();
    dir.deleteSync(recursive: true);
  });
  test('정비 동작은 휴식 구간과 반복 경계에서 튀지 않는다', () {
    expect(maintenanceWorkAngle(0), maintenanceWorkAngle(1));
    expect(maintenanceWorkAngle(.05), maintenanceWorkAngle(.15));
    expect(maintenanceWorkAngle(.44), maintenanceWorkAngle(.48));
    for (final edge in [.18, .42, .50, .70, .82, .94]) {
      expect(
        (maintenanceWorkAngle(edge - .0001) -
                maintenanceWorkAngle(edge + .0001))
            .abs(),
        lessThan(.0001),
      );
    }
  });
  testWidgets('첫 실행의 차량 등록과 예시 안내가 실제 화면을 연다', (tester) async {
    final store = await prepare(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    appRouter.go('/');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWith((ref) => store)],
        child: const MilitaryApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.onboardingCompleted, isFalse);
    await tester.runAsync(() async {
      await tester.tap(find.text('내 차량 등록하기'));
      for (var i = 0; i < 100 && !store.onboardingCompleted; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(store.onboardingCompleted, isTrue);
    expect(find.text('새 차량 등록'), findsOneWidget);

    appRouter.go('/welcome');
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('사용 안내 시작'));
      for (var i = 0; i < 200; i++) {
        if (appRouter
                .routeInformationProvider
                .value
                .uri
                .queryParameters['guide'] ==
            '0') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(store.dashboardExampleView, isTrue);
    expect(find.text('정비 일정'), findsOneWidget);
    for (final title in [
      '차량 상태 지도',
      '정비 결과 기록',
      '정비 도우미',
      '더 보기',
      '차량 목록',
      '연간 정비계획',
      '정비 분석',
      '책자 검색',
      '새 차량 등록',
    ]) {
      await tester.tap(find.text('다음'));
      if (title == '책자 검색') {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
      }
      expect(find.text(title), findsWidgets);
    }
    await tester.tap(find.text('안내 마치기'));
    await tester.pumpAndSettle();
    expect(find.byType(ExampleGuide), findsNothing);
    expect(find.text('정비 일정'), findsOneWidget);
  });
  for (final size in [
    const Size(360, 640),
    const Size(600, 800),
    const Size(1280, 800),
  ]) {
    testWidgets('온보딩 선택과 큰 글자 버튼 ${size.width}', (tester) async {
      await prepare(tester);
      tester.view.physicalSize = size;
      final actions = <OnboardingAction>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: 'Pretendard',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00733B),
              primary: const Color(0xFF00733B),
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(1.6),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const ValueKey('capture'),
            child: OnboardingScreen(
              onComplete: (action) async {
                actions.add(action);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const ResizeImage(
            AssetImage('assets/branding/jungbion-vehicle-logo.png'),
            width: 384,
          ),
          tester.element(find.byType(OnboardingScreen)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('어서 오세요!'), findsOneWidget);
      await snapshot(tester, 'intro-${size.width.toInt()}');
      for (final label in ['사용 안내 시작', '내 차량 등록하기', '건너뛰기']) {
        final button = find.text(label);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(actions, OnboardingAction.values);
    });
  }
  testWidgets('정비 캐릭터를 작업·복귀·휴식 자세로 렌더링한다', (tester) async {
    await prepare(tester);
    final phase = ValueNotifier<double>(0);
    addTearDown(phase.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: const ValueKey('capture'),
            child: SizedBox(
              width: 240,
              height: 240,
              child: ColoredBox(
                color: Colors.white,
                child: Center(
                  child: ValueListenableBuilder<double>(
                    valueListenable: phase,
                    builder: (context, value, child) =>
                        MaintenanceMascot(phase: value),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(MaintenanceMascot));
      await Future.wait([
        precacheImage(
          const AssetImage('assets/branding/jungbion-worker-body.png'),
          context,
        ),
        precacheImage(
          const AssetImage('assets/branding/jungbion-worker-arm.png'),
          context,
        ),
      ]);
    });
    for (var i = 0; i < 20; i++) {
      phase.value = i / 20;
      await tester.pump();
      await snapshot(tester, 'motion-${i.toString().padLeft(2, '0')}');
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('작업 중에만 캐릭터가 움직이고 제거 즉시 타이머도 정리한다', (tester) async {
    await prepare(tester);
    Future<void> show({bool reduced = false}) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Pretendard'),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(600, 800),
            disableAnimations: reduced,
          ),
          child: const RepaintBoundary(
            key: ValueKey('capture'),
            child: Scaffold(
              backgroundColor: Colors.white,
              body: Center(
                child: SizedBox(
                  width: 560,
                  child: MaintenanceLoading(detail: '책자에서 근거를 찾고 있어요.'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await show();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/branding/jungbion-worker-body.png'),
        tester.element(find.byType(MaintenanceLoading)),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/branding/jungbion-worker-arm.png'),
        tester.element(find.byType(MaintenanceLoading)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<Opacity>(find.byType(Opacity).last).opacity, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<Opacity>(find.byType(Opacity).last).opacity, 1);
    final bodyPosition = tester.getTopLeft(
      find.byKey(const ValueKey('maintenance-static-body')),
    );
    final first = tester
        .widget<Transform>(
          find.byKey(const ValueKey('maintenance-mascot-tilt')),
        )
        .transform
        .clone();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<Transform>(
            find.byKey(const ValueKey('maintenance-mascot-tilt')),
          )
          .transform,
      isNot(first),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('maintenance-static-body'))),
      bodyPosition,
    );
    await snapshot(tester, 'loading');
    await show(reduced: true);
    await tester.pump();
    final still = tester
        .widget<Transform>(
          find.byKey(const ValueKey('maintenance-mascot-tilt')),
        )
        .transform
        .clone();
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester
          .widget<Transform>(
            find.byKey(const ValueKey('maintenance-mascot-tilt')),
          )
          .transform,
      still,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
