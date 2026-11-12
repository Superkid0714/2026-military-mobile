import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/ui/analysis_charts.dart';
import 'package:military_maintenance/ui/components.dart';
import 'package:military_maintenance/ui/management.dart';

import 'app_test.dart' show loadAppFonts;

Future<AppStore> prepare(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadAppFonts();
  final s = AppStore(clock: () => DateTime(2026, 10, 9, 12));
  await tester.runAsync(
    () => s.initialize(database: LocalDatabase(NativeDatabase.memory())),
  );
  expect(s.error, isNull);
  addTearDown(() async {
    await s.db!.close();
  });
  return s;
}

Future<void> show(WidgetTester tester, AppStore store, Widget screen) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [storeProvider.overrideWith((ref) => store)],
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Pretendard',
          scaffoldBackgroundColor: surface,
          colorScheme: ColorScheme.fromSeed(
            seedColor: green,
            primary: green,
            surface: Colors.white,
          ),
        ),
        home: RepaintBoundary(
          key: const ValueKey('qa-chart-capture'),
          child: Scaffold(body: screen),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  final target = Platform.environment['QA_VISUAL_DIR'];
  if (target == null) return;
  if (!Directory(target).absolute.path.contains('/private/')) {
    throw StateError('Keep QA screenshots private');
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('qa-chart-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = Directory(target)..createSync(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('상태 원형 그래프의 차량 수와 범례가 상태 변경을 반영한다', (tester) async {
    final s = await prepare(tester);
    Vehicle vehicle(String id, int risk, {bool ready = true}) => Vehicle(
      id: id,
      model: '가상 원형 그래프 시험',
      year: 2020,
      distance: 1000,
      hours: 10,
      fuel: 100,
      risk: risk,
      predictionReady: ready,
    );
    final values = ValueNotifier<List<Vehicle>>([
      vehicle('R1', 10),
      vehicle('R2', 65),
      vehicle('R3', 90),
      vehicle('R4', 0, ready: false),
    ]);
    addTearDown(values.dispose);
    await show(
      tester,
      s,
      Center(
        child: ValueListenableBuilder<List<Vehicle>>(
          valueListenable: values,
          builder: (context, v, child) => StatusRing(v),
        ),
      ),
    );
    expect(find.text('4대'), findsOneWidget);
    for (final label in ['낮음', '관찰', '높음', '미분석']) {
      expect(find.text('● $label  1대'), findsOneWidget);
    }
    await capture(tester, 'risk-ring-before');
    values.value = [
      vehicle('R1', 85),
      vehicle('R2', 65),
      vehicle('R3', 90),
      vehicle('R4', 0, ready: false),
    ];
    await tester.pumpAndSettle();
    expect(find.text('● 높음  2대'), findsOneWidget);
    expect(find.text('● 낮음  0대'), findsOneWidget);
    await capture(tester, 'risk-ring-after');
    expect(tester.takeException(), isNull);
  });
  testWidgets('실제 등록 대상만 집계하고 기록 추가가 숫자와 비중·추이 차트에 반영된다', (tester) async {
    final s = await prepare(tester);
    await tester.runAsync(() async {
      for (final id in ['VIS-1', 'VIS-2']) {
        await s.registerVehicle(
          Vehicle(
            id: id,
            model: '가상 시각화 시험차',
            year: 2020,
            distance: 10000,
            hours: 100,
            fuel: 1000,
            risk: 0,
          ),
        );
      }
      for (final row in [
        ('V1', 'VIS-1', '2026-01-10', '엔진/연료', 1000),
        ('V2', 'VIS-2', '2026-02-10', '제동', 2000),
        ('V3', 'VIS-1', '2026-02-15', '엔진/연료', 3000),
        ('OUTSIDE', 'VIS-1', '2025-12-31', '제동', 90000),
      ]) {
        await s.addMaintenance(
          Maintenance(
            id: row.$1,
            vehicleId: row.$2,
            date: row.$3,
            part: '시험부품',
            system: row.$4,
            description: '가상 그래프 검증',
            cost: row.$5,
          ),
        );
      }
    });
    await show(tester, s, const AnalysisScreen());
    expect(find.text('3건'), findsWidgets);
    expect(find.text('6,000원'), findsOneWidget);
    expect(find.text('2,000원'), findsWidgets);
    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('월별 정비 건수'),
      250,
      scrollable: scroll,
    );
    await tester.pumpAndSettle();
    Map<String, num> breakdown() => tester
        .widget<MaintenanceBreakdown>(find.byType(MaintenanceBreakdown))
        .values;
    Map<String, num> trend() =>
        tester.widget<MaintenanceTrend>(find.byType(MaintenanceTrend)).values;
    expect(breakdown(), {'엔진/연료': 2, '제동': 1});
    expect(trend(), {'2026-01': 1, '2026-02': 2});
    await capture(tester, 'analysis-before');
    await tester.runAsync(
      () => s.addMaintenance(
        const Maintenance(
          id: 'V4',
          vehicleId: 'VIS-2',
          date: '2026-02-21',
          part: '시험부품',
          system: '엔진/연료',
          description: '가상 그래프 갱신 검증',
          cost: 4000,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(breakdown(), {'엔진/연료': 3, '제동': 1});
    expect(trend(), {'2026-01': 1, '2026-02': 3});
    await capture(tester, 'analysis-after');
    await tester.scrollUntilVisible(
      find.text('누적 정비 비용'),
      -250,
      scrollable: scroll,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(MaintenanceBreakdown),
        matching: find.text('4건'),
      ),
      findsOneWidget,
    );
    expect(find.text('10,000원'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('머신러닝 재계산 결과가 화면 확률과 이력에 즉시 반영된다', (tester) async {
    final s = await prepare(tester);
    const id = 'MOCK-RX-0001';
    await show(tester, s, const AiHistoryScreen(vehicleId: id));
    expect(find.text('AI 분석 점수 ${s.vehicle(id).risk}%'), findsOneWidget);
    expect(find.text('점검 순서와 이유'), findsOneWidget);
    expect(find.textContaining('AI 분석 점수'), findsWidgets);
    final old = s.predictions[id]!['probability'];
    await tester.runAsync(() async {
      await s.addMaintenance(
        const Maintenance(
          id: 'VIS-ML',
          vehicleId: id,
          date: '2026-10-09',
          part: '브레이크 호스',
          system: '제동',
          description: '제동 압력 이상 점검 및 호스 교환',
          cost: 48000,
          maintenanceType: '고장수리',
        ),
      );
      final v = s.vehicle(id);
      await s.updateOperation(
        id,
        v.year,
        v.distance + 1600,
        v.hours + 40,
        v.fuel + 160,
      );
    });
    await tester.pumpAndSettle();
    final probability = s.predictions[id]!['probability'] as num;
    expect(probability, isNot(old));
    expect(
      find.text('AI 분석 점수 ${(probability * 100).round()}%'),
      findsOneWidget,
    );
    expect(
      find.text('${(probability * 100).toStringAsFixed(1)}%'),
      findsWidgets,
    );
    expect(find.text('운용 입력'), findsWidgets);
    await capture(tester, 'ml-history-after');
    expect(tester.takeException(), isNull);
  });
}
