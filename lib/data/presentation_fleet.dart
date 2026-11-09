part of 'store.dart';

extension PresentationFleet on AppStore {
  List<Vehicle> get presentationVehicles =>
      vehicles.where((v) => v.id.startsWith('MOCK-OPS-')).toList();
  List<Vehicle> get dashboardVehicles =>
      dashboardExampleView && presentationVehicles.isNotEmpty
      ? presentationVehicles
      : presentationVehicles.isNotEmpty
      ? registeredVehicles
      : activeVehicles;

  Future<void> setDashboardExampleView(bool enabled) async {
    await db!.customStatement(
      'INSERT OR REPLACE INTO app_metadata (key,value) VALUES (?,?)',
      ['dashboard_scope', enabled ? 'examples' : 'registered'],
    );
    dashboardExampleView = enabled;
    _notifyChanged();
  }

  Future<void> loadPresentationFleet() => _mutate(() async {
    await _seedPresentationFleet();
    await _read();
    await setDashboardExampleView(true);
  });

  Future<void> _seedPresentationFleet() async {
    final exists = await db!
        .customSelect(
          "SELECT value FROM app_metadata WHERE key='presentation_fleet_v1'",
        )
        .getSingleOrNull();
    if (exists != null) return;
    final now = clock();
    final today = DateTime(now.year, now.month, now.day);
    String date(DateTime d) => d.toIso8601String().substring(0, 10);
    final rules = <MaintenanceRule>[];
    const parts = [
      ('엔진오일', '엔진/연료', '오일과 필터 교환 후 누유 여부 확인', 85000),
      ('브레이크패드', '제동', '마모 상태 확인 후 패드 교환 및 제동 상태 점검', 148000),
      ('에어클리너', '흡기/배기', '먼지 유입 상태 확인 및 필터 교환', 32000),
      ('냉각수', '냉각', '호스 연결부와 냉각수량 점검', 46000),
      ('타이어', '조향/현가', '편마모 확인 및 타이어 위치 교환', 68000),
      ('배터리', '전장', '시동 전압과 단자 체결 상태 점검', 52000),
    ];
    await db!.transaction(() async {
      for (var i = 0; i < 12; i++) {
        final vid = 'MOCK-OPS-${(i + 1).toString().padLeft(2, '0')}';
        final distance = 24000 + i * 9300, step = 2200 + i * 90;
        final v = Vehicle(
          id: vid,
          model: '렉스턴 스포츠',
          year: today.year - 1 - i % 7,
          distance: distance,
          hours: distance ~/ 32,
          fuel: distance ~/ 9,
          risk: 0,
        );
        await _put('vehicles', vid, {
          ...v.toJson(),
          'isSynthetic': true,
          'dataset': 'presentation-fleet-v1',
        });
        for (var month = 0; month < 6; month++) {
          final at = DateTime(today.year, today.month - 5 + month, 0, 18);
          final km = distance - 200 - (5 - month) * step;
          final oid = '$vid-OP-$month';
          await _put('operations', oid, {
            'id': oid,
            'vehicleId': vid,
            'created': at.toIso8601String(),
            'distance': km,
            'hours': km ~/ 32,
            'fuel': km ~/ 9,
            'isSynthetic': true,
          }, vehicleId: vid);
          final p = parts[1 + (i + month) % (parts.length - 1)];
          final mid = '$vid-MT-$month';
          final m = Maintenance(
            id: mid,
            vehicleId: vid,
            date: date(at),
            part: p.$1,
            system: p.$2,
            description: p.$3,
            cost: p.$4 + i * 1500,
            maintenanceType: month % 3 == 0 ? '고장수리' : '예방정비',
            replacementCompleted: month % 3 != 0,
            odometerKm: km,
          );
          await _put('maintenance', mid, {
            ...m.toJson(),
            'isSynthetic': true,
          }, vehicleId: vid);
        }
        final oid = '$vid-OP-NOW';
        await _put('operations', oid, {
          'id': oid,
          'vehicleId': vid,
          'created': today.toIso8601String(),
          'distance': distance,
          'hours': distance ~/ 32,
          'fuel': distance ~/ 9,
          'isSynthetic': true,
        }, vehicleId: vid);
        if (i < 8) {
          final p = parts[4 + i % 2], mid = '$vid-MT-RECENT';
          final at = today.subtract(Duration(days: i % 5 + 1));
          final m = Maintenance(
            id: mid,
            vehicleId: vid,
            date: date(at),
            part: p.$1,
            system: p.$2,
            description: p.$3,
            cost: p.$4 + i * 2000,
            maintenanceType: i % 2 == 0 ? '예방정비' : '고장수리',
            odometerKm: distance - 100,
            replacementCompleted: false,
          );
          await _put('maintenance', mid, {
            ...m.toJson(),
            'isSynthetic': true,
          }, vehicleId: vid);
        }
        final used = [10200, 9700, 8600, 6200][i % 4];
        final baselineDate = today.subtract(
          Duration(days: ((used - 200) / step * 30 + today.day).round()),
        );
        final baselineId = '$vid-MT-OIL-BASE';
        final baseline = Maintenance(
          id: baselineId,
          vehicleId: vid,
          date: date(baselineDate),
          part: '엔진오일',
          system: '엔진/연료',
          description: '엔진오일과 필터 교환 후 누유 점검',
          cost: 85000 + i * 1000,
          maintenanceType: '예방정비',
          odometerKm: distance - used,
          replacementCompleted: true,
        );
        await _put('maintenance', baselineId, {
          ...baseline.toJson(),
          'isSynthetic': true,
        }, vehicleId: vid);
        rules.add(
          MaintenanceRule(
            id: '$vid-RULE-OIL',
            vehicleId: vid,
            part: '엔진오일',
            intervalKm: 10000,
            baselineKm: distance - used,
            baselineDate: date(baselineDate),
            source: '운용 예시의 점검 간격 · 실제 적용 시 지침 확인',
          ),
        );
      }
      final existingLibrary = await _readSupportLibrary();
      final library = existingLibrary.copyWith(
        rules: [...existingLibrary.rules, ...rules],
      );
      SupportLibrary.decode(library.encode());
      await db!.customStatement(
        'INSERT OR REPLACE INTO app_metadata (key,value) VALUES (?,?)',
        ['maintenance_support', library.encode()],
      );
      for (final row in {
        'presentation_fleet_v1': today.toIso8601String(),
        'dashboard_scope': 'examples',
      }.entries) {
        await db!.customStatement(
          'INSERT OR REPLACE INTO app_metadata (key,value) VALUES (?,?)',
          [row.key, row.value],
        );
      }
    });
  }
}
