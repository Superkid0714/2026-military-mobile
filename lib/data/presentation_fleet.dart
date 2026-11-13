part of 'store.dart';

extension PresentationFleet on AppStore {
  List<Vehicle> get presentationVehicles =>
      vehicles.where((v) => v.id.startsWith('MOCK-OPS-')).toList();
  List<Vehicle> get dashboardVehicles {
    if (_includePresentationFleet) return activeVehicles;
    final registered = registeredVehicles;
    if (registered.isNotEmpty) return registered;
    final examples = presentationVehicles;
    if (examples.isEmpty) return activeVehicles;
    return dashboardExampleView ? examples : registered;
  }

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
    if (exists != null) {
      await _seedAdditionalMaintenance(
        DateTime.parse(exists.read<String>('value')),
      );
      await _seedPresentationSchedules();
      return;
    }
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
            source: '체험 차량의 점검 기준',
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
    await _seedAdditionalMaintenance(today);
    await _seedPresentationSchedules();
  }

  Future<void> _updatePresentationVehicleProfiles() =>
      db!.transaction(() async {
        const profiles = [
          '렉스턴 스포츠',
          '봉고 III 1톤',
          '스타리아 11인승',
          '마이티 2.5톤',
          '포터 II 1톤',
          '쏠라티 15인승',
          '렉스턴 스포츠',
          '봉고 III 1톤',
          '스타리아 11인승',
          '마이티 2.5톤',
          '포터 II 1톤',
          '쏠라티 15인승',
        ];
        for (var i = 0; i < profiles.length; i++) {
          final id = 'MOCK-OPS-${(i + 1).toString().padLeft(2, '0')}';
          final row = await db!
              .customSelect(
                'SELECT payload FROM vehicles WHERE id = ?',
                variables: [Variable<String>(id)],
              )
              .getSingleOrNull();
          if (row == null) continue;
          final payload =
              jsonDecode(row.read<String>('payload')) as Map<String, dynamic>;
          if (payload['model'] == profiles[i]) continue;
          payload['model'] = profiles[i];
          await _put('vehicles', id, payload);
        }
      });

  Future<void> _seedPresentationSchedules() => db!.transaction(() async {
    const marker = 'presentation_schedules_v1';
    final completed = await db!
        .customSelect(
          'SELECT value FROM app_metadata WHERE key = ?',
          variables: [const Variable<String>(marker)],
        )
        .getSingleOrNull();
    if (completed != null) return;
    final existing = await db!
        .customSelect(
          "SELECT value FROM app_metadata WHERE key = 'maintenance_schedules'",
        )
        .getSingleOrNull();
    final schedules = existing == null
        ? <MaintenanceSchedule>[]
        : MaintenanceSchedule.decode(existing.read<String>('value'));
    final now = clock();
    const jobs = [
      (1, 4, '타이어 공기압·마모 점검', '예비 타이어도 함께 확인'),
      (2, 9, '엔진오일·필터 교환', '교환 후 누유 여부 확인'),
      (3, 9, '브레이크 패드 점검', '좌우 패드 잔량 기록'),
      (4, 15, '배터리 전압 점검', '시동 전압과 단자 체결 상태 확인'),
      (5, 21, '냉각수·호스 점검', '냉각수량과 연결부 누수 확인'),
      (6, 26, '등화장치 점검', '전조등과 방향지시등 작동 확인'),
    ];
    final vehicleRows = await db!
        .customSelect("SELECT id FROM vehicles WHERE id LIKE 'MOCK-OPS-%'")
        .get();
    final ids = vehicleRows.map((row) => row.read<String>('id')).toSet();
    final existingIds = schedules.map((item) => item.id).toSet();
    for (var offset = -1; offset <= 2; offset++) {
      for (final (vehicle, day, title, note) in jobs) {
        final date = DateTime(
          now.year,
          now.month + offset,
          day,
        ).toIso8601String().substring(0, 10);
        final vehicleId = 'MOCK-OPS-${vehicle.toString().padLeft(2, '0')}';
        final id = 'DEMO-SCHEDULE-$vehicleId-$date';
        if (ids.contains(vehicleId) && existingIds.add(id)) {
          schedules.add(
            MaintenanceSchedule(
              id: id,
              vehicleId: vehicleId,
              date: date,
              title: title,
              note: note,
            ),
          );
        }
      }
    }
    await _writeSchedules(schedules);
    await db!.customStatement(
      'INSERT INTO app_metadata (key,value) VALUES (?,?)',
      [marker, now.toIso8601String()],
    );
  });

  Future<void> _seedAdditionalMaintenance(DateTime anchor) async {
    const marker = 'presentation_maintenance_v2';
    final affected = <String>{};
    await db!.transaction(() async {
      final completed = await db!
          .customSelect(
            'SELECT value FROM app_metadata WHERE key = ?',
            variables: [const Variable<String>(marker)],
          )
          .getSingleOrNull();
      if (completed != null) return;

      final vehicles = await db!
          .customSelect(
            "SELECT id FROM vehicles WHERE id LIKE 'MOCK-OPS-%' ORDER BY id",
          )
          .get();
      const jobs = [
        ('와이퍼', '차체', '닦임 불량으로 와이퍼 교환', 22000, true),
        ('에어컨 필터', '공조', '송풍량 저하 확인 후 필터 교환', 38000, true),
        ('전조등', '전장', '좌측 전조등 점등 불량 수리', 64000, false),
        ('냉각수 호스', '냉각', '연결부 누수 확인 후 호스 교환', 96000, true),
        ('브레이크액', '제동', '브레이크액 교환 후 페달 응답 확인', 72000, true),
        ('도어 잠금장치', '차체', '잠금장치 연결부 점검 및 조정', 47000, false),
        ('휠 얼라인먼트', '조향/현가', '쏠림 증상 확인 후 바퀴 정렬 조정', 78000, false),
        ('보조 벨트', '엔진/연료', '벨트 소음 확인 후 교환', 108000, true),
      ];
      const monthOffsets = [0, 1, 1, 2, 2, 2, 3, 4, 4, 5, 5, 5];
      for (final (index, vehicle) in vehicles.indexed) {
        final vehicleId = vehicle.read<String>('id');
        for (var visit = 0; visit < 2; visit++) {
          final (part, system, description, cost, replaced) =
              jobs[(index * 3 + visit) % jobs.length];
          final offset =
              monthOffsets[(index + visit * 5) % monthOffsets.length];
          final day = DateTime(
            anchor.year,
            anchor.month - offset,
            anchor.day,
          ).subtract(Duration(days: 2 + (index * 3 + visit) % 18));
          final record = Maintenance(
            id: '$vehicleId-MT-EXTRA-$visit',
            vehicleId: vehicleId,
            date: day.toIso8601String().substring(0, 10),
            part: part,
            system: system,
            description: description,
            cost: cost + index * 1000,
            maintenanceType: replaced ? '예방정비' : '고장수리',
            replacementCompleted: replaced,
          );
          await db!.customStatement(
            'INSERT OR IGNORE INTO maintenance (id,vehicle_id,payload) VALUES (?,?,?)',
            [
              record.id,
              vehicleId,
              jsonEncode({
                ...record.toJson(),
                'isSynthetic': true,
                'source': 'presentation-fleet-v2',
              }),
            ],
          );
          affected.add(vehicleId);
        }
      }
      await db!.customStatement(
        'INSERT INTO app_metadata (key,value) VALUES (?,?)',
        [marker, 'done'],
      );
    });
    for (final id in affected) {
      _dirtyVehicles[id] = '체험 기록 추가';
    }
  }
}
