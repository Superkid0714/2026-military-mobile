import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/main.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/ui/components.dart';

import 'ui_usability_test.dart' show setup, tap;

void main() {
  testWidgets('AI 상태를 선택하면 차량 목록과 대수가 필터링된다', (tester) async {
    final store = await setup(tester, size: const Size(1440, 1080));
    appRouter.go('/vehicles');
    await tester.pumpAndSettle();
    final vehicles = store.dashboardVehicles;
    for (final label in ['낮음', '관찰', '높음', '미분석', '전체']) {
      await tap(tester, find.byKey(ValueKey('vehicle-status-$label')));
      final expected = vehicles
          .where((v) => label == '전체' || statusLabel(v.status) == label)
          .length;
      expect(
        find.text('$expected대 · 차량을 선택하면 상세 정비 이력으로 이동합니다.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(ValueKey('vehicle-status-$label')))
            .selected,
        isTrue,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('홈 조회 대상과 일반 차량 목록이 같은 차량 범위를 사용한다', (tester) async {
    final store = await setup(tester, size: const Size(1440, 1080));
    await tester.runAsync(() => store.loadPresentationFleet());
    await tester.runAsync(() => store.setDashboardExampleView(false));
    for (final enabled in [false, true]) {
      await tester.runAsync(() => store.setDashboardExampleView(enabled));
      final expected = store.dashboardVehicles.map((v) => v.id).toSet();
      for (final route in ['/vehicles', '/vehicles?scope=home']) {
        appRouter.go(route);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SummaryCards>(find.byType(SummaryCards))
              .vehicles
              .map((v) => v.id)
              .toSet(),
          expected,
        );
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('홈에 미분석을 포함한 네 상태와 전체 합계를 표시한다', (tester) async {
    final store = await setup(tester, size: const Size(1440, 1080));
    await tester.runAsync(() => store.loadPresentationFleet());
    appRouter.go('/');
    await tester.pumpAndSettle();
    final vehicles = store.dashboardVehicles;
    final ready = vehicles.where((v) => v.predictionReady).length;
    expect(
      find.text(
        '분석 완료 $ready대 · 미분석 ${vehicles.length - ready}대 · 전체 ${vehicles.length}대',
      ),
      findsOneWidget,
    );
    for (final state in VehicleStatus.values) {
      final bar = find.byKey(ValueKey('fleet-risk-${state.name}'));
      expect(bar, findsOneWidget);
      expect(
        find.descendant(
          of: bar,
          matching: find.text(
            '${vehicles.where((v) => v.status == state).length}대',
          ),
        ),
        findsOneWidget,
      );
    }
    await tap(tester, find.byKey(const ValueKey('fleet-risk-unavailable')));
    expect(find.text('미분석 · ${vehicles.length - ready}대'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('더 보기에서 백업과 현장 요청 메뉴를 숨긴다', (tester) async {
    await setup(tester, size: const Size(1440, 1080));
    appRouter.go('/more');
    await tester.pumpAndSettle();
    expect(find.text('현장 요청'), findsNothing);
    expect(find.text('백업·자료 가져오기'), findsNothing);
    expect(find.text('차량 목록'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
