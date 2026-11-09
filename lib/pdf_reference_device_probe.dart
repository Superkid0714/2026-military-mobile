import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'data/adaptive_runtime.dart';
import 'data/local_rag.dart';
import 'data/local_summary.dart';
import 'data/store.dart';
import 'probe_fixture.dart';

/// Explicit local diagnostic. Questions, answers and original text remain private.
Future<void> runPdfReferenceDeviceProbe() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('maintenance/device_probe');
  final runtime = AdaptiveRuntime();
  AppStore? store;
  final report = <String, Object?>{
    'cases': <Map<String, Object?>>[],
    'persistentDatabaseTouched': false,
  };
  try {
    await runtime.initialize();
    report['physicalDevice'] = runtime.device!.isEmulator == false;
    final directory = File(runtime.modelInfo['indexPath'] as String)
        .parent
        .parent
        .parent;
    final packet = jsonDecode(
      await File('${directory.path}/pdf-reference-questions.json')
          .readAsString(),
    ) as Map;
    final questions = (packet['questions'] as List).cast<Map>();
    if (questions.isEmpty ||
        questions.length > 30 ||
        questions.map((q) => q['id']).toSet().length != questions.length) {
      throw const FormatException('invalid_question_count');
    }
    store = await oilProbeFixture(runtime, 'QA-PDF-DEVICE');
    final originalCriteria = jsonEncode(
      store.selectedRuleCriteria(store.supportLibrary.rules.single),
    );
    final cases = report['cases'] as List<Map<String, Object?>>;
    for (final q in questions) {
      final question = q['question'] as String;
      final result = await LocalRag(runtime)
          .search(store, 'QA-PDF-DEVICE', '오일필터', question);
      if (result.mode != 'hybrid') throw StateError('hybrid_search_failed');
      final ids = result.evidence.map((e) => e.id).toList();
      final gold = (q['goldEvidence'] as List).cast<String>();
      final same = jsonEncode(ids) == jsonEncode(q['pcEvidenceIds']);
      final row = <String, Object?>{
        'id': q['id'],
        'mode': result.mode,
        'evidenceIds': ids,
        'orderedPcParity': same,
        'hit1': ids.take(1).any(gold.contains),
        'hit3': ids.take(3).any(gold.contains),
        'hit5': ids.take(5).any(gold.contains),
        'timingsMs': result.timingsMs,
      };
      cases.add(row);
      if (!same) throw StateError('ordered_pc_parity_failed');
      if (q['runSummary'] == true) {
        final summary = await LocalSummary.summarize(
          runtime,
          question,
          result.evidence,
          maxTokens: 128,
        );
        row['summary'] = {
          'mode': summary.mode,
          'reason': summary.reason,
          'timingsMs': summary.run?.timingsMs,
          'excerpts': summary.excerpts
              .map((e) => {'id': e.citation, 'quote': e.quote})
              .toList(),
        };
        if (summary.mode != 'extractive_summary' || summary.excerpts.isEmpty) {
          throw StateError('no_accepted_summary');
        }
        final required = (q['summaryMustContain'] as List).cast<String>();
        String compact(String value) => value.replaceAll(RegExp(r'\s+'), '');
        if (!summary.excerpts.any(
          (e) =>
              gold.contains(e.citation) &&
              required.every(
                (word) => compact(e.quote).contains(compact(word)),
              ),
        )) {
          throw StateError('summary_does_not_answer_reviewed_question');
        }
      }
    }
    final after = await AndroidModelWorker.channel
        .invokeMapMethod<String, Object?>('probe');
    report['afterUnload'] = after;
    if (after?['loaded'] != false) throw StateError('unload_failed');
    if (jsonEncode(
          store.selectedRuleCriteria(store.supportLibrary.rules.single),
        ) !=
        originalCriteria) {
      throw StateError('registered_rule_changed');
    }
    report['ruleUnchanged'] = true;
    report['hit1'] = cases.where((c) => c['hit1'] == true).length;
    report['hit3'] = cases.where((c) => c['hit3'] == true).length;
    report['hit5'] = cases.where((c) => c['hit5'] == true).length;
    report['status'] = 'passed';
  } catch (e) {
    report['status'] = 'failed';
    report['error'] = '$e';
  } finally {
    await runtime.manager.release();
    await store?.db?.close();
    runtime.dispose();
  }
  await channel.invokeMethod<Object?>('complete', report);
}
