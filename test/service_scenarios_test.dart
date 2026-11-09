import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/local_models.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/data/inspection_priority.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = jsonDecode(
    File('test/fixtures/service_scenarios.json').readAsStringSync(),
  ) as Map;
  final results = <Map<String, Object?>>[];
  late LocalModels models;
  setUpAll(() async {
    expect(source['isSynthetic'], true);
    models = await LocalModels.load();
  });
  for (final raw in source['cases'] as List) {
    final row = Map<String, dynamic>.from(raw as Map);
    test('시나리오 ${row['name']}: 기대 점검 순서와 모델 입력 조건', () {
      final store = AppStore(
        clock: () => DateTime.parse(source['asOf'] as String),
      );
      addTearDown(store.dispose);
      final assessment = assessPrediction(
        vehicle: Map<String, dynamic>.from(row['vehicle'] as Map),
        operations: (row['operations'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList(),
        maintenance: (row['maintenance'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList(),
        asOf: store.clock(),
      );
      final probability = assessment.features == null
          ? null
          : models.predict(assessment.features!);
      expect(probability != null, row['expected']['predictionReady']);
      if (probability != null) {
        expect(probability.isFinite, true);
        expect(probability, inInclusiveRange(0, 1));
      }
      store.vehicles = [
        Vehicle.fromJson({
          ...Map<String, dynamic>.from(row['vehicle'] as Map),
          'risk': ((probability ?? 0) * 100).round(),
        }),
      ];
      final vehicle = store.vehicles.single;
      store.vehicles = [
        Vehicle(
          id: vehicle.id,
          model: vehicle.model,
          year: vehicle.year,
          distance: vehicle.distance,
          hours: vehicle.hours,
          fuel: vehicle.fuel,
          risk: vehicle.risk,
          predictionReady: probability != null,
          cautionThreshold: (models.threshold * 100).round(),
          dangerThreshold: 50,
        ),
      ];
      store.records = (row['maintenance'] as List)
          .map((r) => Maintenance.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      store.supportLibrary = SupportLibrary(
        rules: (row['rules'] as List)
            .map(
              (r) =>
                  MaintenanceRule.fromJson(Map<String, dynamic>.from(r as Map)),
            )
            .toList(),
      );
      final priorities = store.inspectionPriorities(vehicle.id);
      expect(priorities.first.part, row['expected']['firstPart']);
      expect(
        priorities.map((r) => r.order).toList(),
        row['expected']['orders'],
      );
      results.add({
        'id': row['id'],
        'name': row['name'],
        'modelVersion': models.version,
        'probability': probability,
        'unavailableReason': assessment.reason,
        'priorities': [
          for (final r in priorities)
            {'part': r.part, 'order': r.order, 'reason': r.reason},
        ],
        'status': 'passed',
      });
    });
  }
  tearDownAll(() {
    final output = Platform.environment['SERVICE_SCENARIO_REPORT'];
    if (output != null) {
      final path = File(output).absolute;
      if (!path.path.contains('/private/')) {
        throw StateError('Keep runtime reports private');
      }
      path.parent.createSync(recursive: true);
      path.writeAsStringSync(
        const JsonEncoder.withIndent('  ')
            .convert({'asOf': source['asOf'], 'results': results}),
      );
    }
  });
}
