import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:military_maintenance/main.dart';

import 'ui_usability_test.dart' show setup;
import 'data_tools_test.dart' show tapWithIo;

import 'package:military_maintenance/data/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('일정은 연속 저장·수정 후 재실행과 백업 복원에도 남는다', () async {
    final directory = Directory.systemTemp.createTempSync('schedule-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = File('${directory.path}/records.sqlite');
    final store = AppStore();
    await store.initialize(database: LocalDatabase(NativeDatabase(path)));
    final vehicle = store.vehicles.first.id;
    MaintenanceSchedule item(String id, String title) => MaintenanceSchedule(
      id: id,
      vehicleId: vehicle,
      date: '2026-11-20',
      title: title,
    );
    await Future.wait([
      store.saveSchedule(item('S-1', '오일 교환')),
      store.saveSchedule(item('S-2', '타이어 점검')),
    ]);
    await store.saveSchedule(item('S-1', '엔진오일과 필터 교환'));
    expect(store.schedules, hasLength(2));
    await store.db!.close();

    final reopened = AppStore();
    await reopened.initialize(database: LocalDatabase(NativeDatabase(path)));
    addTearDown(() => reopened.db!.close());
    expect(
      reopened.schedules.map((item) => item.title),
      contains('엔진오일과 필터 교환'),
    );
    await reopened.deleteSchedule('S-2');
    expect(reopened.schedules.single.id, 'S-1');
    final backup = File('${directory.path}/saved.mbackup');
    await reopened.exportBackup(backup);
    final snapshot = await BackupSnapshot.read(backup);
    await reopened.deleteSchedule('S-1');
    await reopened.restoreBackup(snapshot, directory);
    expect(reopened.schedules.single.title, '엔진오일과 필터 교환');
    await expectLater(
      () => reopened.saveSchedule(
        MaintenanceSchedule(
          id: 'BAD',
          vehicleId: vehicle,
          date: '2026-02-30',
          title: '날짜 오류',
        ),
      ),
      throwsFormatException,
    );
  });
  testWidgets('일정 추가 화면에서 저장하면 달력 날짜에 표시한다', (tester) async {
    final store = await setup(tester);
    appRouter.go('/plans');
    await tester.pumpAndSettle();
    expect(find.textContaining('예상'), findsNothing);
    await tester.tap(find.text('일정 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '정비 내용'),
      '타이어 점검',
    );
    await tapWithIo(
      tester,
      find.widgetWithText(FilledButton, '저장'),
      completed: () => store.schedules.isNotEmpty,
    );
    expect(store.schedules.single.title, '타이어 점검');
    expect(find.textContaining('타이어 점검'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
