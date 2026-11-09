// Explicit local-only command; the reference documents and answers stay private.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/adaptive_runtime.dart';
import 'package:military_maintenance/data/local_summary.dart';
import 'package:military_maintenance/data/rag_ranking.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/probe_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('실제 PDF의 원문 연결과 앱 정렬기 검색을 검사한다', () async {
    final path = Platform.environment['PDF_QA_DIR'];
    if (path == null || !Directory(path).absolute.path.contains('/private/')) {
      throw StateError('Set PDF_QA_DIR to the private reference bundle');
    }
    final index =
        jsonDecode(File('$path/bundle/index.json').readAsStringSync()) as Map;
    final packet = jsonDecode(
      File('$path/questions-vectors.json').readAsStringSync(),
    ) as Map;
    final runtime = AdaptiveRuntime()
      ..modelInfo = {'knowledgePath': '$path/bundle/knowledge.json'};
    final store = await oilProbeFixture(runtime, 'QA-PDF-PC');
    addTearDown(() async {
      await store.db!.close();
      runtime.dispose();
    });
    final eligible = {
      for (final e in store.eligibleEvidence('QA-PDF-PC', '오일필터')) e.id: e,
    };
    expect(eligible.length, (index['sourceEvidence'] as List).length);
    final cases = <Map<String, Object?>>[];
    for (final q in packet['questions'] as List) {
      final chunks = (index['chunks'] as List).cast<Map>();
      for (final c in chunks) {
        final source = eligible[c['evidenceId']]!;
        expect(
          String.fromCharCodes(
            source.text.runes.toList().sublist(
              c['charStart'] as int,
              c['charEnd'] as int,
            ),
          ),
          c['text'],
        );
        expect(source.sourceRef, c['sourceRef']);
      }
      final ranks = rankRag(
        chunks: chunks,
        vector: (q['embedding'] as List).cast<num>(),
        keywordIds: store
            .searchEvidence('QA-PDF-PC', '오일필터', q['question'] as String)
            .map((e) => e.id)
            .toList(),
        conditions: {
          for (final e in eligible.values)
            e.id: evidenceCondition(e, store.supportLibrary.knowledge),
        },
        intent: RagIntent.parse(q['question'] as String, 'unselected'),
      );
      final ids = ranks.hybridIds;
      final gold = (q['goldEvidence'] as List).cast<String>();
      cases.add({
        'id': q['id'],
        'evidenceIds': ids,
        'hit1': ids.take(1).any(gold.contains),
        'hit3': ids.take(3).any(gold.contains),
        'hit5': ids.take(5).any(gold.contains),
      });
    }
    File('$path/pc-search-result.json').writeAsStringSync(
      jsonEncode({
        'scope': packet['scope'],
        'cases': cases,
        'hit1': cases.where((c) => c['hit1'] == true).length,
        'hit3': cases.where((c) => c['hit3'] == true).length,
        'hit5': cases.where((c) => c['hit5'] == true).length,
      }),
    );
    expect(cases.length, greaterThan(0));
    expect(
      cases.every((c) => c['hit5'] == true),
      isTrue,
      reason: 'A reviewed reference must appear in the first five results',
    );
    final summaries = jsonDecode(
      File('$path/device-questions.json').readAsStringSync(),
    ) as Map;
    for (final q in (summaries['questions'] as List).where(
      (q) => q['runSummary'] == true,
    )) {
      final evidence = (q['pcEvidenceIds'] as List)
          .map((id) => eligible[id]!)
          .toList();
      final selected = LocalSummary.selectEvidence(
        q['question'] as String,
        evidence,
      );
      final allowed = LocalSummary.candidates(
        LocalSummary.sources(selected),
        question: q['question'] as String,
      );
      String compact(String s) => s.replaceAll(RegExp(r'\s+'), '');
      final gold = q['goldEvidence'] as List;
      final markers = (q['summaryMustContain'] as List).cast<String>();
      File('$path/${q['id']}-candidate-audit.json').writeAsStringSync(
        jsonEncode(
          allowed.map((s) => {'id': s.citation, 'quote': s.quote}).toList(),
        ),
      );
      expect(allowed, isNotEmpty, reason: q['id'] as String);
      expect(
        allowed.every(
          (s) =>
              gold.contains(s.citation) &&
              markers.every((m) => compact(s.quote).contains(compact(m))),
        ),
        isTrue,
        reason:
            '${q['id']}: every permitted sentence must answer the reviewed question',
      );
    }
  });
}
