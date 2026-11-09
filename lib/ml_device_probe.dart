import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'data/local_models.dart';
import 'data/store.dart';
import 'data/inspection_priority.dart';

/// Explicit androidTest entry point. Only reads separately provisioned QA input.
Future<void> runMlDeviceProbe() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('maintenance/device_probe');
  final report = <String, Object?>{'scope': 'synthetic_heldout_runtime_parity'};
  try {
    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/ml-qa-probes.json');
    if (await file.length() > 8 * 1024 * 1024) {
      throw const FormatException('qa_input_limit');
    }
    final data = jsonDecode(await file.readAsString()) as Map;
    if (data['format'] != 'synthetic-model-qa' || data['isSynthetic'] != true) {
      throw const FormatException('synthetic_input_required');
    }
    final model = await LocalModels.load();
    if (data['modelVersions']['prediction'] != model.prediction['version'] ||
        data['modelVersions']['classification'] !=
            model.classification['version']) {
      throw const FormatException('model_version_mismatch');
    }
    final predictions = data['prediction'] as List;
    final classifications = data['classification'] as List;
    if (predictions.length != 3600 || classifications.length != 861) {
      throw const FormatException('qa_case_count');
    }
    double numericError = 0, textError = 0;
    final watch = Stopwatch()..start();
    for (final raw in predictions) {
      final row = raw as Map;
      final actual = model.predict(
        Map<String, num>.from(row['features'] as Map),
      );
      final delta = (actual - (row['expected'] as num)).abs();
      if (!actual.isFinite || !delta.isFinite || delta > 1e-10) {
        throw const FormatException('prediction_parity');
      }
      numericError = math.max(numericError, delta);
    }
    final numericMs = watch.elapsedMicroseconds / 1000;
    watch.reset();
    for (final raw in classifications) {
      final row = raw as Map;
      final actual = model.classify(
        row['part'] as String,
        row['description'] as String,
      );
      for (final head in [
        ('system', actual.system),
        ('maintenanceType', actual.type),
      ]) {
        final expected = row['expected'][head.$1] as Map;
        final confidence =
            (head.$2.confidence - (expected['confidence'] as num)).abs();
        final coverage = (head.$2.coverage - (expected['coverage'] as num))
            .abs();
        if (head.$2.label != expected['label'] ||
            !confidence.isFinite ||
            !coverage.isFinite ||
            confidence > 1e-10 ||
            coverage > 1e-10) {
          throw const FormatException('classification_parity');
        }
        textError = math.max(textError, math.max(confidence, coverage));
      }
    }
    // Isolated scenario: real model output feeds the ordinary priority engine.
    // No persistent store is opened and no user records are written.
    final store = AppStore(clock: () => DateTime(2026, 11, 4));
    try {
      final score =
          (model.predict(
                    Map<String, num>.from(
                      (predictions.first as Map)['features'] as Map,
                    ),
                  ) *
                  100)
              .round();
      store.vehicles = [
        Vehicle(
          id: 'QA-ONLY',
          model: '분석 검증',
          year: 2020,
          distance: 20000,
          hours: 500,
          fuel: 2000,
          risk: score,
          predictionReady: true,
        ),
      ];
      store.supportLibrary = const SupportLibrary(
        rules: [
          MaintenanceRule(
            id: 'QA-RULE',
            vehicleId: 'QA-ONLY',
            part: '엔진오일',
            intervalKm: 10000,
            baselineKm: 10000,
            baselineDate: '2026-01-01',
            source: 'QA 기준',
          ),
        ],
      );
      store.records = [
        for (var i = 0; i < 2; i++)
          Maintenance(
            id: 'QA-$i',
            vehicleId: 'QA-ONLY',
            date: '2026-10-01',
            part: '브레이크 패드',
            system: '제동',
            description: '분석 검증',
            cost: 100,
            maintenanceType: '고장수리',
          ),
      ];
      var queue = store.inspectionPriorities('QA-ONLY');
      if (queue.map((r) => r.order).join(',') != '0,1,2' ||
          !queue.last.reason.contains('$score%')) {
        throw const FormatException('priority_model_integration');
      }
      store.records = [];
      queue = store.inspectionPriorities('QA-ONLY');
      if (queue.map((r) => r.order).join(',') != '0,2') {
        throw const FormatException('priority_edit_refresh');
      }
      store.supportLibrary = const SupportLibrary();
      queue = store.inspectionPriorities('QA-ONLY');
      if (queue.length != 1 || queue.single.order != 2) {
        throw const FormatException('priority_rule_refresh');
      }
      report['priorityIntegrationCases'] = 3;
      report['priorityUsesActualModelOutput'] = true;
    } finally {
      store.dispose();
    }
    report.addAll({
      'status': 'passed',
      'predictionCases': predictions.length,
      'classificationCases': classifications.length,
      'predictionMaxAbsError': numericError,
      'classificationMaxAbsError': textError,
      'predictionTotalMs': numericMs,
      'classificationTotalMs': watch.elapsedMicroseconds / 1000,
      'timingScope': 'single debug batch; not production latency benchmark',
      'persistentDatabaseTouched': false,
    });
  } catch (error) {
    report.addAll({
      'status': 'failed',
      'errorType': error.runtimeType.toString(),
    });
  }
  await channel.invokeMethod<Object?>('complete', report);
}
