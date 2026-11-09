import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('운용 예시를 실제 저장하고 반복 실행해도 중복과 기존 기록 변경이 없다', () async {
    final store = AppStore(clock: () => DateTime(2026, 11, 4));
    await store.initialize(database: LocalDatabase(NativeDatabase.memory()));
    final before = store.vehicles.map((v) => v.id).toSet();
    final maintenanceBefore = store.records.map((r) => r.id).toSet();
    await store.loadPresentationFleet();
    expect(store.presentationVehicles.length, 12);
    final ids = store.presentationVehicles.map((v) => v.id).toSet();
    expect(
      store.operations.where((r) => ids.contains(r['vehicleId'])).length,
      84,
    );
    expect(store.records.where((r) => ids.contains(r.vehicleId)).length, 92);
    expect(
      store.supportLibrary.rules.where((r) => ids.contains(r.vehicleId)).length,
      12,
    );
    expect(store.presentationVehicles.every((v) => v.predictionReady), isTrue);
    expect(
      store.presentationVehicles.every(
        (v) => store.predictions.containsKey(v.id),
      ),
      isTrue,
    );
    expect(before.difference(store.vehicles.map((v) => v.id).toSet()), isEmpty);
    expect(
      maintenanceBefore.difference(store.records.map((r) => r.id).toSet()),
      isEmpty,
    );
    final count = store.records.length;
    await store.loadPresentationFleet();
    expect(store.records.length, count);
    expect(store.dashboardExampleView, isTrue);
    await store.setDashboardExampleView(false);
    expect(store.dashboardVehicles, isEmpty);
    expect(store.activeVehicles.length, store.vehicles.length);
    await store.db!.close();
  });

  test('앱 시작 시 운용 예시를 추가해도 기존 정비 기준이 남는다', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = AppStore(clock: () => DateTime(2026, 11, 4));
    await store.initialize(database: database);
    const rule = MaintenanceRule(
      id: 'RULE-EXISTING',
      vehicleId: 'MOCK-RX-0001',
      part: '엔진오일',
      intervalKm: 10000,
      baselineKm: 0,
      baselineDate: '2026-10-01',
      source: '시험 지침',
    );
    await store.saveSupportLibrary(const SupportLibrary(rules: [rule]));

    final reopened = AppStore(clock: store.clock);
    await reopened.initialize(database: database, populatePresentation: true);
    expect(reopened.ready, isTrue);
    expect(reopened.presentationVehicles, hasLength(12));
    expect(reopened.supportLibrary.rules, hasLength(13));
    expect(
      reopened.supportLibrary.rules.firstWhere((r) => r.id == rule.id).toJson(),
      rule.toJson(),
    );
  });
}
