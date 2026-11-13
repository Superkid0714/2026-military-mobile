import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/main.dart';
import 'package:military_maintenance/ui/components.dart';
import 'package:military_maintenance/ui/analysis_charts.dart';
import 'package:military_maintenance/ui/maintenance_calendar.dart';

import 'ui_usability_test.dart' show setup, tap;
import 'data_tools_test.dart' show tapWithIo;

void main() {
  testWidgets('홈에서 조회 기간을 바꾸고 월별 정비와 운행 기록으로 이동한다', (tester) async {
    await setup(tester);
    final slider = find.byType(Slider);
    await tap(tester, slider);
    tester.widget<Slider>(slider).onChanged!(3);
    await tester.pumpAndSettle();
    expect(find.text('최근 3개월'), findsOneWidget);
    tester.widget<Slider>(slider).onChanged!(12);
    await tester.pumpAndSettle();
    expect(find.text('최근 12개월'), findsOneWidget);
    tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .where((state) => state.position.axis == Axis.vertical)
        .elementAt(1)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(InkWell, '이달 정비 기록').first);
    expect(find.text('우선 점검'), findsNothing);
    await tap(tester, find.text('운행 기록'));
    expect(find.text('운행 기록'), findsWidgets);
    expect(find.text('운행 기록 조회'), findsOneWidget);
  });

  testWidgets('정비 추이는 차량별 구분 없이 전체 월별 건수를 표시한다', (tester) async {
    final store = await setup(tester);
    await tester.runAsync(store.loadPresentationFleet);
    await tester.pumpAndSettle();
    await tap(tester, find.text('최근 6개월'));
    final chart = tester.widget<MaintenanceTrend>(
      find.byType(MaintenanceTrend),
    );
    expect(chart.series, isEmpty);
    expect(
      chart.values.values.fold<num>(0, (total, count) => total + count),
      greaterThan(0),
    );
  });

  testWidgets('위험도 상태 막대에서 차량 목록과 개별 분석을 연다', (tester) async {
    final store = await setup(tester);
    await tester.runAsync(store.loadPresentationFleet);
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const ValueKey('fleet-risk-normal')));
    final candidates = store.dashboardVehicles.where(
      (vehicle) => vehicle.status == VehicleStatus.normal,
    );
    expect(candidates, isNotEmpty);
    await tap(
      tester,
      find.widgetWithText(ListTile, vehicleLabel(candidates.first.id)),
    );
    expect(find.text('지난 분석 결과'), findsOneWidget);
  });

  testWidgets('분석 이력에서 전체 차량과 개별 차량을 전환한다', (tester) async {
    final store = await setup(tester);
    await tap(tester, find.text('분석 이력'));
    expect(find.text('차량별 분석 현황'), findsOneWidget);
    await tap(
      tester,
      find
          .widgetWithText(
            ListTile,
            vehicleLabel(store.dashboardVehicles.first.id),
          )
          .first,
    );
    expect(find.text('지난 분석 결과'), findsOneWidget);
    final selector = find.byType(DropdownButtonFormField<String>).first;
    await tap(tester, selector);
    await tester.scrollUntilVisible(
      find.text('전체 차량'),
      -500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('전체 차량').last);
    await tester.pumpAndSettle();
    expect(find.text('차량별 분석 현황'), findsOneWidget);
  });

  testWidgets('홈 달력에서 다음 달 점검 일정을 확인한다', (tester) async {
    final store = await setup(tester);
    final vehicle = store.dashboardVehicles.first;
    await tester.runAsync(
      () => store.saveSchedule(
        MaintenanceSchedule(
          id: 'HOME-CALENDAR',
          vehicleId: vehicle.id,
          date: '2026-11-12',
          title: '타이어 점검 예약',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tap(tester, find.byTooltip('다음 달'));
    expect(find.text('2026년 11월'), findsOneWidget);
    final calendar = find.byType(MaintenanceCalendar);
    expect(tester.widget<MaintenanceCalendar>(calendar).counts, {12: 1});
    await tap(tester, find.descendant(of: calendar, matching: find.text('12')));
    expect(find.text('타이어 점검 예약'), findsOneWidget);
    final otherVehicle = store.dashboardVehicles.last;
    await tap(tester, find.byTooltip('점검 차량 선택'));
    await tap(
      tester,
      find.widgetWithText(
        CheckedPopupMenuItem<String>,
        vehicleLabel(otherVehicle.id),
      ),
    );
    expect(tester.widget<MaintenanceCalendar>(calendar).counts, isEmpty);
    expect(find.text('타이어 점검 예약'), findsNothing);

    await tap(tester, find.text('일정 추가'));
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('2026.11.12')),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextFormField)).first,
      '브레이크 점검',
    );
    await tapWithIo(
      tester,
      find.widgetWithText(FilledButton, '저장'),
      completed: () => store.schedules.any((item) => item.title == '브레이크 점검'),
    );
    expect(
      store.schedules.singleWhere((item) => item.title == '브레이크 점검').vehicleId,
      otherVehicle.id,
    );
    expect(tester.widget<MaintenanceCalendar>(calendar).counts, {12: 1});
    expect(find.text('브레이크 점검'), findsOneWidget);
    await tap(tester, find.byTooltip('이전 달'));
    expect(find.text('2026년 10월'), findsOneWidget);
    expect(find.text('타이어 점검 예약'), findsNothing);
  });

  testWidgets('최근 정비 기록 카드에서 최대 다섯 건과 전체 기록을 연다', (tester) async {
    final store = await setup(tester);
    await tester.runAsync(store.loadPresentationFleet);
    await tester.pumpAndSettle();

    final card = find.widgetWithText(Panel, '최근 정비 기록');
    final list = find.byType(ListView).at(1);
    await tester.scrollUntilVisible(
      card,
      300,
      scrollable: find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first,
    );
    expect(
      find.descendant(of: card, matching: find.byType(ListTile)),
      findsNWidgets(5),
    );
    await tap(tester, find.descendant(of: card, matching: find.text('전체 보기')));
    expect(find.text('정비 기록'), findsWidgets);
  });

  testWidgets('홈 요약 카드 네 개에서 해당 목록과 비용 내역을 연다', (tester) async {
    final store = await setup(tester);
    await tester.runAsync(store.loadPresentationFleet);
    await tester.pumpAndSettle();

    for (final (card, title) in [
      ('관리 차량', '차량 목록'),
      ('점검 필요', '점검 대상 3건'),
      ('이달 정비 기록', '전체 정비 기록'),
      ('이번 달 비용', '정비 비용 합계'),
    ]) {
      await tap(tester, find.widgetWithText(InkWell, card).first);
      expect(find.text(title), findsWidgets);
      if (card == '이번 달 비용') {
        expect(find.widgetWithText(Panel, '643,000원'), findsOneWidget);
        expect(find.text('가격 높은 순'), findsOneWidget);
      }
      await tap(tester, find.text('뒤로'));
      expect(find.text('뒤로'), findsNothing);
      expect(find.widgetWithText(InkWell, '관리 차량').first, findsOneWidget);
    }
  });

  testWidgets('메뉴에서 연 하위 화면도 상단 뒤로 버튼으로 돌아간다', (tester) async {
    await setup(tester);
    await tap(tester, find.widgetWithText(ListTile, '더 보기'));
    await tap(tester, find.widgetWithText(ListTile, '정비 분석'));
    await tap(tester, find.text('뒤로'));
    expect(appRouter.routeInformationProvider.value.uri.path, '/more');

    await tap(tester, find.widgetWithText(ListTile, '기록'));
    await tap(tester, find.text('기록 쓰기'));
    await tap(tester, find.text('뒤로'));
    expect(appRouter.routeInformationProvider.value.uri.path, '/records');
    expect(find.text('뒤로'), findsNothing);
  });

  testWidgets('다섯 메뉴에서 기록 쓰기와 추가 화면으로 이동한다', (tester) async {
    await setup(tester);
    expect(find.text('00 수송부'), findsOneWidget);
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
    expect(find.text('예제 차량'), findsNothing);
    expect(find.text('등록 차량'), findsNothing);
    expect(
      find.descendant(
        of: find.widgetWithText(InkWell, '관리 차량'),
        matching: find.text('12대'),
      ),
      findsOneWidget,
    );
    expect(find.text('AI 정비 예측'), findsOneWidget);
    expect(find.text('관리 차량'), findsOneWidget);
    expect(find.byType(Bars), findsNothing);
    await expectLater(
      find.byType(MilitaryApp),
      matchesGoldenFile('goldens/workflow_home_demo_1280x800.png'),
    );
    await tap(tester, find.text('차량 등록'));
    expect(find.text('아직 등록한 차량이 없습니다.'), findsOneWidget);
    expect(find.text('준비 상태'), findsNothing);
    await tap(tester, find.text('새 차량 등록'));
    expect(find.widgetWithText(AlertDialog, '새 차량 등록'), findsOneWidget);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    await tap(tester, find.text('뒤로'));
    expect(find.text('차량 등록'), findsOneWidget);
    await tester.runAsync(
      () => s.registerVehicle(
        const Vehicle(
          id: 'HOME-SCOPE-TEST',
          model: '홈 시험차',
          year: 2020,
          distance: 0,
          hours: 0,
          fuel: 0,
          risk: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(s.dashboardExampleView, isTrue);
    expect(s.dashboardVehicles.map((v) => v.id), ['HOME-SCOPE-TEST']);
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
    expect(
      find.descendant(
        of: find.widgetWithText(InkWell, '관리 차량'),
        matching: find.text('2대'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(InkWell, '점검 필요'),
        matching: find.text('1건'),
      ),
      findsOneWidget,
    );
    expect(find.byType(StatusRing), findsNothing);

    await expectLater(
      find.byType(MilitaryApp),
      matchesGoldenFile('goldens/workflow_home_registered_1280x960.png'),
    );
    await tap(tester, find.widgetWithText(InkWell, 'HOME-REAL-A · 브레이크패드'));
    expect(
      appRouter.routerDelegate.currentConfiguration.last.matchedLocation,
      '/support',
    );
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
