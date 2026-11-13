import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/front_inspection.dart';
import 'package:military_maintenance/ui/inspection_demo.dart';

void main() {
  for (final area in FrontInspectionArea.values) {
    testWidgets('${area.label} 순차 점검과 이상 자동 열기·계속·초기화', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: InspectionDemo(area: area)),
        ),
      );
      expect(find.textContaining('AI 점검 동작을 가정한'), findsNothing);
      expect(find.text('새 결과 따라보기'), findsNothing);
      expect(find.text('미점검'), findsNWidgets(area.parts.length));
      await tester.ensureVisible(find.text('AI 점검 시작'));
      await tester.tap(find.text('AI 점검 시작'));
      await tester.pump();
      await tester.pump(
        Duration(seconds: area == FrontInspectionArea.engineBay ? 13 : 13),
      );
      expect(find.textContaining('확인 순서'), findsOneWidget);
      expect(find.text('점검 계속'), findsOneWidget);
      final before = tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('inspection-total-progress')),
          )
          .value;
      await tester.pump(const Duration(seconds: 5));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('inspection-total-progress')),
            )
            .value,
        before,
      );
      await tester.ensureVisible(find.text('정비 확인 필요'));
      await tester.tap(find.text('정비 확인 필요'));
      await tester.pump();
      expect(find.text('확인 요청됨'), findsOneWidget);
      await tester.ensureVisible(find.text('점검 계속'));
      await tester.tap(find.text('점검 계속'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 17));
      expect(find.textContaining('전체 점검 종료'), findsOneWidget);
      await tester.ensureVisible(find.text('다시 점검'));
      await tester.tap(find.text('다시 점검'));
      await tester.pump();
      expect(find.text('미점검'), findsNWidgets(area.parts.length));
      expect(find.textContaining('확인 순서'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
