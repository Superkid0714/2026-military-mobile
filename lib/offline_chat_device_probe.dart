import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'data/adaptive_runtime.dart';
import 'data/offline_assistant.dart';
import 'data/store.dart';

Future<void> runOfflineChatDeviceProbe() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('maintenance/device_probe');
  final runtime = AdaptiveRuntime();
  final store = AppStore(clock: () => DateTime(2026, 11, 4));
  final report = <String, Object?>{
    'persistentDatabaseTouched': false,
    'cases': <Map<String, Object?>>[],
  };
  try {
    await runtime.initialize();
    report['physicalDevice'] = runtime.device?.isEmulator == false;
    store.vehicles = [
      for (final id in ['CHAT-QA', 'OTHER-QA'])
        Vehicle(
          id: id,
          model: '렉스턴 스포츠',
          year: 2020,
          distance: 20000,
          hours: 500,
          fuel: 2000,
          risk: 80,
          predictionReady: true,
        ),
    ];
    store.supportLibrary = const SupportLibrary(
      rules: [
        MaintenanceRule(
          id: 'CHAT-RULE',
          vehicleId: 'CHAT-QA',
          part: '엔진오일',
          intervalKm: 10000,
          baselineKm: 10000,
          baselineDate: '2026-01-01',
          source: '진단용 기준',
        ),
      ],
    );
    store.records = [
      for (final row in [
        ('C1', 'CHAT-QA'),
        ('C2', 'CHAT-QA'),
        ('OTHER', 'OTHER-QA'),
      ])
        Maintenance(
          id: row.$1,
          vehicleId: row.$2,
          date: '2026-10-01',
          part: '브레이크 패드',
          system: '제동',
          description: '진단용 정비 이력',
          cost: 100,
          maintenanceType: '고장수리',
        ),
    ];
    final assistant = OfflineAssistant.local(runtime);
    final cases = report['cases'] as List<Map<String, Object?>>;
    final priorities = await assistant.ask(store, 'CHAT-QA', '무엇부터 점검해야 해?');
    if (priorities.priorities.map((p) => p.order).join(',') != '0,1,2' ||
        priorities.history.any((h) => h.vehicleId != 'CHAT-QA')) {
      throw StateError('vehicle_context_or_priority_failed');
    }
    cases.add({
      'id': 'vehicle_priorities',
      'passed': true,
      'text': priorities.text,
    });
    final corpus = File(runtime.modelInfo['corpusDatabasePath'] as String);
    final packet = jsonDecode(
      await File(
        '${corpus.parent.parent.parent.path}/manual-rag-questions.json',
      ).readAsString(),
    ) as Map;
    final questions = (packet['questions'] as List)
        .cast<Map>()
        .where((q) => q['summary'] == true)
        .take(2);
    if (questions.length != 2) throw StateError('missing_private_qa_questions');
    for (final q in questions) {
      final watch = Stopwatch()..start();
      final answer = await assistant.ask(
        store,
        'CHAT-QA',
        q['question'] as String,
      );
      if (answer.evidence.isEmpty || answer.excerpts.isEmpty) {
        throw StateError('chat_grounded_answer_missing:${q['id']}');
      }
      for (final excerpt in answer.excerpts) {
        if (!answer.evidence.any(
          (e) =>
              e.id == excerpt.citation &&
              e.text.replaceAll(RegExp(r'\s+'), ' ').contains(excerpt.quote),
        )) {
          throw StateError('chat_citation_invalid');
        }
      }
      cases.add({
        'id': q['id'],
        'passed': true,
        'sources': answer.evidence.length,
        'excerpts': answer.excerpts.length,
        'elapsedMs': watch.elapsedMilliseconds,
        'question': answer.question,
        'text': answer.text,
        'explanations': answer.explanations,
        'citations': answer.excerpts
            .map((s) => {'id': s.citation, 'quote': s.quote})
            .toList(),
        'sourceFiles': answer.evidence.map((e) => e.title).toList(),
      });
    }
    final wiring = await assistant.ask(store, 'CHAT-QA', 'CAN 통신 구성도');
    if (!wiring.evidence.any((e) => e.sourceRef?['textMethod'] == 'ocr') ||
        wiring.excerpts.isNotEmpty ||
        !wiring.text.contains('원본 그림')) {
      throw StateError('ocr_diagram_answer_guard_failed');
    }
    cases.add({'id': 'wiring_diagram_guard', 'passed': true});
    final broad = await assistant.ask(store, 'CHAT-QA', '브레이크 점검 시 주의사항은?');
    if (broad.excerpts.isEmpty ||
        broad.excerpts.any(
          (e) => !OfflineAssistant.fitsQuestion(broad.question, e.quote),
        ) ||
        broad.evidence.any((e) => !e.title.contains('새시'))) {
      throw StateError('brake_precaution_answer_quality_failed');
    }
    cases.add({
      'id': 'brake_precaution_quality',
      'passed': true,
      'text': broad.text,
      'explanations': broad.explanations,
      'sourceFiles': broad.evidence.map((e) => e.title).toList(),
    });
    final follow = await assistant.ask(
      store,
      'CHAT-QA',
      '그럼 주의사항은?',
      previousQuestion: questions.first['question'] as String,
    );
    if (!follow.searchQuestion.contains(
          questions.first['question'] as String,
        ) ||
        follow.evidence.isEmpty) {
      throw StateError('followup_failed');
    }
    cases.add({'id': 'followup', 'passed': true});
    final other = await assistant.ask(store, 'OTHER-QA', '최근 정비 이력을 알려줘');
    if (other.history.length != 1 || other.history.single.id != 'OTHER') {
      throw StateError('vehicle_isolation_failed');
    }
    cases.add({'id': 'vehicle_isolation', 'passed': true});
    final unrelated = await assistant.ask(store, 'CHAT-QA', '점심 메뉴 알려줘');
    if (unrelated.evidence.isNotEmpty || unrelated.history.isNotEmpty) {
      throw StateError('unrelated_question_failed');
    }
    cases.add({'id': 'unrelated_question', 'passed': true});
    final term = await assistant.ask(store, 'CHAT-QA', '탈거가 무슨 뜻이야?');
    if (!term.text.contains('부품을 분리') || term.evidence.isNotEmpty) {
      throw StateError('plain_term_answer_failed');
    }
    cases.add({'id': 'plain_term_answer', 'passed': true, 'text': term.text});
    final worker = await AndroidModelWorker.channel
        .invokeMapMethod<String, Object?>('probe');
    if (worker?['loaded'] != false) throw StateError('worker_unload_failed');
    report['afterUnload'] = worker;
    report['status'] = 'passed';
  } catch (e) {
    report['status'] = 'failed';
    report['error'] = '$e';
  } finally {
    store.dispose();
    await runtime.manager.release();
    runtime.dispose();
  }
  await channel.invokeMethod<Object?>('complete', report);
}
