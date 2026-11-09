import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/data/inspection_priority.dart';

void main() {
  AppStore setup({bool ready = true}) {
    final s = AppStore(clock: () => DateTime(2026, 11, 4));
    s.vehicles = [
      Vehicle(
        id: 'TEST',
        model: '시험 차량',
        year: 2020,
        distance: 20000,
        hours: 500,
        fuel: 2000,
        risk: 90,
        predictionReady: ready,
      ),
    ];
    return s;
  }

  Maintenance record(
    String id,
    String date, {
    String type = '고장수리',
    String vehicle = 'TEST',
  }) => Maintenance(
    id: id,
    vehicleId: vehicle,
    date: date,
    part: '브레이크 패드',
    system: '제동',
    description: '시험 기록',
    cost: 100,
    maintenanceType: type,
  );

  test('주기 도래가 반복 수리와 ML보다 먼저이며 근거를 함께 표시한다', () {
    final s = setup();
    addTearDown(s.dispose);
    s.supportLibrary = const SupportLibrary(
      rules: [
        MaintenanceRule(
          id: 'R',
          vehicleId: 'TEST',
          part: '엔진오일',
          intervalKm: 10000,
          baselineKm: 10000,
          baselineDate: '2026-01-01',
          source: '시험 기준',
        ),
      ],
    );
    s.records = [record('1', '2026-10-01'), record('2', '2026-10-10')];
    final rows = s.inspectionPriorities('TEST');
    expect(rows.map((r) => r.order), [0, 1, 2]);
    expect(rows.first.part, '엔진오일');
    expect(rows[1].reason, contains('2회'));
    expect(rows.last.reason, contains('90%'));
  });
  test('미래·다른 차량·예방정비·90일 밖 이력은 반복 고장으로 세지 않는다', () {
    final s = setup(ready: false);
    addTearDown(s.dispose);
    s.records = [
      record('1', '2026-10-01'),
      record('2', '2026-12-01'),
      record('3', '2026-10-02', type: '예방정비'),
      record('4', '2026-10-03', vehicle: 'OTHER'),
      record('5', '2026-01-01'),
    ];
    final rows = s.inspectionPriorities('TEST');
    expect(rows, hasLength(1));
    expect(rows.single.part, '점검 기준 확인');
    expect(rows.single.reason, isNot(contains('90%')));
  });
  test('입력 기록이 바뀌면 반복 수리 점검 순서가 즉시 재계산된다', () {
    final s = setup();
    addTearDown(s.dispose);
    expect(s.inspectionPriorities('TEST').first.order, 2);
    s.records = [record('1', '2026-10-01'), record('2', '2026-10-10')];
    expect(s.inspectionPriorities('TEST').first.order, 1);
    s.records = [];
    expect(s.inspectionPriorities('TEST').first.order, 2);
  });
}
