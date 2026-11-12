import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/main.dart';
import 'package:military_maintenance/ui/components.dart';

import 'ui_usability_test.dart' show setup, tap;

void main() {
  testWidgets('홈에서 조회 기간을 바꾸고 월별 정비와 운행 기록으로 이동한다', (tester) async {
    await setup(tester);
    await tap(tester, find.text('3개월'));
    expect(find.text('최근 3개월 정비'), findsOneWidget);
    await tap(tester, find.text('12개월'));
    expect(find.text('최근 12개월 정비'), findsOneWidget);
    tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .where((state) => state.position.axis == Axis.vertical)
        .last
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tap(tester, find.text('이번 달 정비와 점검 순서'));
    expect(find.text('우선 점검'), findsOneWidget);
    await tap(tester, find.text('운행 기록'));
    expect(find.text('운행 기록'), findsOneWidget);
    expect(find.text('운용 기록 관리'), findsOneWidget);
  });

  testWidgets('다섯 메뉴에서 기록 쓰기와 추가 화면으로 이동한다', (tester) async {
    await setup(tester);
    expect(find.text('정비참모부 관리단'), findsOneWidget);
    for (final label in ['홈', '사진 점검', '기록', '정비 질문', '더 보기']) {
      expect(find.widgetWithText(ListTile, label), findsOneWidget);
    }
    expect(find.widgetWithText(ListTile, '차량 목록'), findsNothing);
    await tap(tester, find.widgetWithText(ListTile, '기록'));
    await tap(tester, find.text('기록 쓰기'));
    expect(appRouter.routeInformationProvider.value.uri.path, '/entry');

    await tap(tester, find.widgetWithText(ListTile, '더 보기'));
    await tap(tester, find.widgetWithText(ListTile, '정비 분석'));
    await tap(tester, find.text('지난 분석 결과'));
    expect(appRouter.routeInformationProvider.value.uri.path, '/ai-history');

    await tap(tester, find.widgetWithText(ListTile, '더 보기'));
    await tester.tap(find.widgetWithText(ListTile, '책자 검색'));
    await tester.pump();
    expect(appRouter.routeInformationProvider.value.uri.path, '/manual-search');
    appRouter.go('/');
    await tester.pumpAndSettle();
  });

  testWidgets('예제 시작과 합성 분석을 분리하고 준비·업무 동선을 제공한다', (tester) async {
    final s = await setup(tester);
    await tester.runAsync(s.loadPresentationFleet);
    await tester.pumpAndSettle();
    expect(find.text('앱 제공 차량 12대'), findsOneWidget);
    expect(find.text('다음 점검'), findsOneWidget);
    expect(find.text('관리 차량'), findsOneWidget);
    expect(find.byType(Bars), findsNothing);
    await expectLater(
      find.byType(MilitaryApp),
      matchesGoldenFile('goldens/workflow_home_demo_1280x800.png'),
    );
    await tap(tester, find.text('초기 설정·차량 등록'));
    expect(find.text('준비 상태'), findsOneWidget);
    expect(find.text('차량 등록 미등록'), findsOneWidget);
    expect(find.text('정비 근거 미등록'), findsOneWidget);
    expect(find.text('정비 주기 미등록'), findsOneWidget);
    appRouter.go('/');
    await tester.pumpAndSettle();
    await tap(tester, find.text('등록 차량 0대'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(s.dashboardVehicles, isEmpty);
    expect(find.widgetWithText(OutlinedButton, '차량 등록'), findsOneWidget);
  });

  testWidgets('실제 등록 차량의 주기 도달·기준 확인·미등록을 구분하고 작업 대상을 연결한다', (tester) async {
    final s = await setup(tester, size: const Size(1280, 960));
    await tester.runAsync(() async {
      for (final id in ['HOME-REAL-A', 'HOME-REAL-B']) {
        await s.registerVehicle(
          Vehicle(
            id: id,
            model: '홈 구성 시험차',
            year: 2020,
            distance: 20000,
            hours: 500,
            fuel: 1000,
            risk: 0,
          ),
        );
      }
      await s.saveSupportLibrary(
        const SupportLibrary(
          rules: [
            MaintenanceRule(
              id: 'DUE',
              vehicleId: 'HOME-REAL-A',
              part: '엔진오일',
              intervalKm: 5000,
              baselineKm: 13000,
              baselineDate: '2026-10-09',
              source: '가상 시험 지침',
            ),
            MaintenanceRule(
              id: 'CHECK',
              vehicleId: 'HOME-REAL-A',
              part: '브레이크패드',
              intervalKm: 10000,
              baselineKm: 10000,
              baselineDate: '2026-10-01',
              source: '가상 시험 지침',
            ),
          ],
        ),
      );
      await s.addMaintenance(
        const Maintenance(
          id: 'UNKNOWN',
          vehicleId: 'HOME-REAL-A',
          date: '2026-10-09',
          part: 'brake_pad',
          system: '제동',
          description: '교환 여부가 미확인인 과거 시험 기록',
          cost: 0,
        ),
      );
    });
    await tester.pumpAndSettle();
    expect(find.text('차량 2대'), findsOneWidget);
    expect(find.text('지금 점검 1건'), findsOneWidget);
    expect(find.text('기준 확인 필요'), findsOneWidget);
    expect(find.byType(StatusRing), findsNothing);

    await expectLater(
      find.byType(MilitaryApp),
      matchesGoldenFile('goldens/workflow_home_registered_1280x960.png'),
    );
    await tap(tester, find.widgetWithText(ListTile, 'HOME-REAL-A · 브레이크패드'));
    final uri = appRouter.routeInformationProvider.value.uri;
    expect(uri.path, '/support');
    expect(uri.queryParameters['vehicle'], 'HOME-REAL-A');
    expect(uri.queryParameters['part'], '브레이크패드');
  });

  testWidgets('정비지원에서 촬영 없이 선택한 부품의 작업 기록으로 이동한다', (tester) async {
    final s = await setup(tester);
    final vehicle = s.vehicles.first.id;
    appRouter.go('/support?vehicle=$vehicle&part=brake_pad');
    await tester.pumpAndSettle();
    final before = s.records.length;
    await tap(tester, find.widgetWithText(OutlinedButton, '정비 결과 기록'));
    final uri = appRouter.routeInformationProvider.value.uri;
    expect(uri.path, '/entry');
    expect(uri.queryParameters['vehicle'], vehicle);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('수리부속 품명')))
          .controller!
          .text,
      '브레이크패드',
    );
    expect(s.records.length, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('홈에서 정비 결과 입력과 정비 질문을 바로 연다', (tester) async {
    await setup(tester);
    await tap(tester, find.text('정비 결과 입력'));
    expect(appRouter.routeInformationProvider.value.uri.path, '/entry');
    appRouter.go('/');
    await tester.pumpAndSettle();
    await tap(tester, find.text('정비 질문하기'));
    expect(appRouter.routeInformationProvider.value.uri.path, '/chat');
  });

  testWidgets('재구성한 홈을 600×800·글자 1.6배에서 사용할 수 있다', (tester) async {
    await setup(tester, size: const Size(600, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tap(tester, find.widgetWithText(OutlinedButton, '차량 사진 점검'));
    expect(find.text('차량 상태 지도'), findsOneWidget);
    expect(find.text('전면 사진 찍기'), findsOneWidget);
    expect(tester.takeException(), isNull);
    appRouter.go('/');
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(OutlinedButton, '부품별 정비'));
    expect(appRouter.routeInformationProvider.value.uri.path, '/support');
    expect(tester.takeException(), isNull);
  });
}
