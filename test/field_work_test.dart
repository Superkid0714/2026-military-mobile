import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/main.dart';

import 'ui_usability_test.dart' show setup;
import 'data_tools_test.dart' show tapWithIo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('현장 요청은 연속 저장·처리·재실행·백업 복원 후에도 유지된다', () async {
    final directory = Directory.systemTemp.createTempSync('field-work-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = File('${directory.path}/records.sqlite');
    final store = AppStore();
    await store.initialize(database: LocalDatabase(NativeDatabase(path)));
    final id = store.vehicles.first.id;
    FieldWork item(String key, FieldWorkKind kind) => FieldWork(
      id: key,
      vehicleId: id,
      kind: kind,
      part: '배터리',
      note: '부품 상태 재확인',
      created: '2026-11-12T09:00:00',
      partNumber: kind == FieldWorkKind.parts ? 'CONFIRMED-PART' : '',
      quantity: 2,
    );
    await Future.wait([
      store.saveFieldWork(item('REQUEST-1', FieldWorkKind.parts)),
      store.saveFieldWork(item('FEEDBACK-1', FieldWorkKind.feedback)),
    ]);
    await store.closeFieldWork(store.fieldWork.first, true);
    expect(store.fieldWork, hasLength(2));
    await store.db!.close();
    final reopened = AppStore();
    await reopened.initialize(database: LocalDatabase(NativeDatabase(path)));
    addTearDown(() => reopened.db!.close());
    expect(reopened.fieldWork.where((item) => item.closed), hasLength(1));
    final backup = File('${directory.path}/saved.mbackup');
    await reopened.exportBackup(backup);
    final snapshot = await BackupSnapshot.read(backup);
    await reopened.closeFieldWork(
      reopened.fieldWork.firstWhere((item) => item.closed),
      false,
    );
    await reopened.restoreBackup(snapshot, directory);
    expect(reopened.fieldWork, hasLength(2));
    expect(reopened.fieldWork.where((item) => item.closed), hasLength(1));
    expect(
      reopened.fieldWork
          .firstWhere((item) => item.kind == FieldWorkKind.parts)
          .partNumber,
      'CONFIRMED-PART',
    );
    final bad = item('BAD', FieldWorkKind.parts).toJson()
      ..['vehicleId'] = 'UNKNOWN';
    final decoded = FieldWork.decode(jsonEncode([bad])).single;
    await expectLater(
      () => reopened.saveFieldWork(decoded),
      throwsArgumentError,
    );
    expect(reopened.fieldWork, hasLength(2));
    final raw =
        jsonDecode(utf8.decode(gzip.decode(await backup.readAsBytes()))) as Map;
    final metadata = raw['metadata'] as List;
    (metadata.firstWhere((value) => value['key'] == 'field_work')
        as Map)['value'] = jsonEncode([
      bad,
    ]);
    final corrupt = File('${directory.path}/invalid.mbackup');
    await corrupt.writeAsBytes(gzip.encode(utf8.encode(jsonEncode(raw))));
    await expectLater(
      () => BackupSnapshot.read(corrupt),
      throwsFormatException,
    );
  });

  test('현장 요청은 중복 ID와 잘못된 수량·날짜·종류를 거부한다', () {
    final valid = FieldWork(
      id: 'ONE',
      vehicleId: 'V',
      kind: FieldWorkKind.parts,
      part: '배터리',
      note: '교체 필요',
      created: '2026-11-12T09:00:00',
    ).toJson();
    for (final change in [
      {'quantity': 0},
      {'quantity': 1000},
      {'quantity': '1'},
      {'kind': 'sent'},
      {'created': 'invalid'},
      {'created': '2026-02-30T09:00:00'},
      {'part': ' '},
      {'note': ''},
    ]) {
      expect(
        () => FieldWork.decode(
          jsonEncode([
            {...valid, ...change},
          ]),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => FieldWork.decode(jsonEncode([valid, valid])),
      throwsFormatException,
    );
  });

  testWidgets('부속 요청 작성·처리 상태 변경과 인식 오류 제보를 할 수 있다', (tester) async {
    final store = await setup(tester);
    appRouter.go('/field-work');
    await tester.pumpAndSettle();
    await tester.tap(find.text('부속 요청 작성'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '부품 이름'), '배터리');
    await tester.enterText(
      find.widgetWithText(TextFormField, '요청 사유'),
      '전압 확인 후 교체 요청',
    );
    await tapWithIo(
      tester,
      find.widgetWithText(FilledButton, '저장'),
      completed: () => store.fieldWork.isNotEmpty,
    );
    expect(find.text('품번: 확인 필요 · 1개'), findsOneWidget);
    expect(find.text('확인 대기'), findsOneWidget);
    expect(find.textContaining('전송 완료'), findsNothing);
    await tapWithIo(
      tester,
      find.text('처리 완료로 변경'),
      completed: () => store.fieldWork.single.closed,
    );
    expect(find.text('처리 완료'), findsOneWidget);
    await tester.tap(find.text('인식 오류 제보'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '부품 이름'), '그릴');
    await tester.enterText(
      find.widgetWithText(TextFormField, '어떤 부분이 달랐나요?'),
      '부위 표시가 오른쪽으로 치우침',
    );
    await tapWithIo(
      tester,
      find.widgetWithText(FilledButton, '저장'),
      completed: () => store.fieldWork.length == 2,
    );
    expect(
      store.fieldWork.where((item) => item.kind == FieldWorkKind.feedback),
      hasLength(1),
    );
    await tester.tap(find.text('삭제').first);
    await tester.pumpAndSettle();
    await tapWithIo(
      tester,
      find.widgetWithText(FilledButton, '삭제'),
      completed: () => store.fieldWork.length == 1,
    );
    expect(store.fieldWork, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
