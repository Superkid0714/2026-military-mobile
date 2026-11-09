import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/manual_rag.dart';

void main() {
  test('전체 책자 색인의 출처·검색·기기 비교 입력을 준비한다', () {
    final path = Platform.environment['MANUAL_QA_DIR'];
    if (path == null || !Directory(path).absolute.path.contains('/private/')) {
      throw StateError('Set MANUAL_QA_DIR under private/');
    }
    final manifest = jsonDecode(
      File('$path/bundle/manifest.json').readAsStringSync(),
    ) as Map;
    final hash = manifest['files']['model.onnx']['sha256'] as String,
        config = manifest['executionConfig'] as String;
    final packet = jsonDecode(
      File('$path/questions-vectors.json').readAsStringSync(),
    ) as Map;
    final cases = <Map<String, Object?>>[];
    for (final q in packet['questions'] as List) {
      final watch = Stopwatch()..start();
      final result = searchManualCorpus(
        path: '$path/bundle/corpus.sqlite',
        hash: hash,
        config: config,
        question: q['question'] as String,
        document: q['document'] as String,
        part: q['part'] as String,
        vector: (q['vector'] as List).cast<num>(),
      );
      final hits = (result['hits'] as List).cast<Map>();
      final ids = hits.map((h) => h['id']).toList();
      q['pcIds'] = ids;
      final gold = q['gold'] as List;
      cases.add({
        'id': q['id'],
        'hit5': gold.isEmpty ? ids.isEmpty : ids.any(gold.contains),
        'ids': ids,
        'headingIds': result['headingIds'],
        'lexicalIds': result['lexicalIds'],
        'semanticIds': result['semanticIds'],
        'ms': watch.elapsedMilliseconds,
      });
      for (final h in hits) {
        expect(h['page'], isPositive);
        expect(h['sha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(h['text'], contains(h['excerpt']));
      }
    }
    File('$path/pc-result.json').writeAsStringSync(
      jsonEncode({
        'cases': cases,
        'hit5': cases.where((c) => c['hit5'] == true).length,
      }),
    );
    for (final q in packet['questions'] as List) {
      q.remove('vector');
    }
    File('$path/device-questions.json').writeAsStringSync(jsonEncode(packet));
    expect(cases.length, packet['expectedCaseCount'] ?? 16);
    expect(
      cases.every((c) => c['hit5'] == true),
      isTrue,
      reason: 'Reviewed sources and no-evidence cases must match the local reference packet',
    );
  });
}
