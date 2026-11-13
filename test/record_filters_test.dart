import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/ui/record_filters.dart';
import 'package:military_maintenance/main.dart';

import 'ui_usability_test.dart' show setup, tap;

void main() {
  test('기간은 시작일과 종료일 전체를 포함한다', () {
    final range = DateTimeRange(
      start: DateTime(2026, 2, 1),
      end: DateTime(2026, 2, 28),
    );
    expect(recordInPeriod('2026-02-01T00:00:00', range), isTrue);
    expect(recordInPeriod('2026-02-28T23:59:59', range), isTrue);
    expect(recordInPeriod('2026-01-31', range), isFalse);
    expect(recordInPeriod('2026-03-01', range), isFalse);
    expect(recordInPeriod('invalid', range), isFalse);
    expect(recordInPeriod('2025-01-01', null), isTrue);
  });

  testWidgets('연도 경계의 최근 3개월과 전체 기간을 선택한다', (tester) async {
    DateTimeRange? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordPeriodFilter(
            now: DateTime(2026, 1, 15),
            value: null,
            onChanged: (v) => result = v,
          ),
        ),
      ),
    );
    await tester.tap(find.text('최근 3개월'));
    expect(result!.start, DateTime(2025, 11, 1));
    expect(result!.end, DateTime(2026, 1, 15));
    await tester.tap(find.text('전체 기간'));
    expect(result, isNull);
  });

  testWidgets('기록 화면의 두 탭과 기간 필터가 연결된다', (tester) async {
    await setup(tester, size: const Size(1440, 1080));
    appRouter.go('/records');
    await tester.pumpAndSettle();
    expect(find.text('이번 달 정비'), findsNothing);
    expect(find.byType(RecordTabs), findsOneWidget);
    await tap(tester, find.widgetWithText(ChoiceChip, '최근 3개월'));
    expect(
      tester.widget<RecordPeriodFilter>(find.byType(RecordPeriodFilter)).value,
      isNotNull,
    );
    await tap(tester, find.widgetWithText(ChoiceChip, '전체 기간'));
    expect(
      tester.widget<RecordPeriodFilter>(find.byType(RecordPeriodFilter)).value,
      isNull,
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, 1200));
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(ChoiceChip, '운행 기록'));
    expect(find.byType(RecordPeriodFilter), findsOneWidget);
    expect(find.text('누적 거리(km)'), findsOneWidget);
    expect(find.text('출고연도'), findsOneWidget);
    expect(find.text('수정·삭제 이력'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
