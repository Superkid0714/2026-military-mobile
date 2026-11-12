import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'adaptive_runtime.dart';
import 'model_execution.dart';
import 'store.dart';

String _compactManual(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

// Everyday terms and equivalent wording used in the manuals.
const _manualSynonyms = [
  ['전조등', '헤드램프', '헤드라이트'],
  ['에어필터', '에어클리너', '흡기필터'],
  ['배터리', '축전지'],
  ['브레이크패드', '제동패드'],
  ['오일필터', '오일필터엘리먼트'],
  ['시동안걸', '시동이안걸', '시동이걸리지', '시동불량', '시동곤란'],
  ['분리', '탈거'],
  ['교체', '교환'],
];

Database _openManual(String path, String hash, String config) {
  final file = File(path);
  if (!file.existsSync() || file.lengthSync() > 1024 * 1024 * 1024) {
    throw const FormatException('manual_corpus_missing_or_too_large');
  }
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final meta = {
      for (final r in db.select('SELECT key,value FROM metadata'))
        r['key']: r['value'],
    };
    if (meta['version'] != '2' ||
        meta['dimension'] != '512' ||
        meta['modelSha256'] != hash ||
        meta['executionConfig'] != config) {
      throw const FormatException('manual_corpus_model_mismatch');
    }
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}

Map<String, Object?> manualCorpusInfo(String path, String hash, String config) {
  final db = _openManual(path, hash, config);
  try {
    final metadata = {
      for (final r in db.select('SELECT key,value FROM metadata'))
        r['key']: r['value'],
    };
    return {
      'searchablePages': db
          .select("SELECT count(*) n FROM pages WHERE search_text!=''")
          .single['n'],
      'imagePages':
          int.tryParse(metadata['imagePageCount'] as String? ?? '') ?? 0,
      'documents': [
        for (final r in db.select(
          'SELECT id,file,kind,pages FROM documents ORDER BY id',
        ))
          {
            'id': r['id'],
            'file': r['file'],
            'kind': r['kind'],
            'pages': r['pages'],
          },
      ],
      'pages': db.select('SELECT count(*) n FROM pages').single['n'],
      'chunks': db.select('SELECT count(*) n FROM chunks').single['n'],
    };
  } finally {
    db.close();
  }
}

/// Pure, read-only corpus search. Runs off the UI isolate; returns only five pages.
Map<String, Object?> searchManualCorpus({
  required String path,
  required String hash,
  required String config,
  required String question,
  List<num>? vector,
  String document = '',
  String part = '',
}) {
  final db = _openManual(path, hash, config);
  try {
    if (vector != null &&
        (vector.length != 512 || vector.any((x) => !x.isFinite))) {
      throw const FormatException('invalid_query_vector');
    }
    final pages = db.select(
      '''SELECT p.*,d.file,d.sha256,d.kind FROM pages p
      JOIN documents d ON d.id=p.doc_id WHERE (?='' OR p.doc_id=?) AND length(p.search_text)>0''',
      [document, document],
    );
    const aliases = {
      '에어필터': ['에어클리너', 'aircleaner'],
      '전조등': ['헤드램프', '헤드라이트'],
      '배터리': ['축전지', 'battery'],
      '냉각수호스': ['냉각수호스', '냉각호스'],
    };
    final partNames = [
      part,
      ...?standardParts[part],
      ...?aliases[part],
    ].map(_compactManual).toList();
    final eligible = {
      for (final r in pages)
        if (part.isEmpty ||
            partNames.any(
              (name) => (r['search_text'] as String).contains(name),
            ))
          r['id'] as String: r,
    };
    final terms = maintenanceSearchTerms(question)
        .map(
          (t) => t.replaceFirst(RegExp(r'(에서|으로|에는|이|가|을|를|은|는|도|에|의)$'), ''),
        )
        .map((t) => t.replaceFirst(RegExp(r'(되나요|인가요|하나요|나요|하는|한다|할)$'), ''))
        .map(_compactManual)
        .where(
          (t) =>
              t.isNotEmpty &&
              !const {
                '무엇',
                '어떻게',
                '알려줘',
                '알려주세요',
                '설명',
                '보여줘',
                '방법',
                '관련',
                '있나',
                '어디',
                '어디서',
                '어디에',
                '싶어요',
                '궁금',
                '궁금해요',
                '찾아줘',
                '뭐',
                '뭔',
                '뭐야',
              }.contains(t),
        )
        .toSet();
    final words = question
        .toLowerCase()
        .split(RegExp(r'[\s,.;!?()]+'))
        .map(
          (t) => t.replaceFirst(RegExp(r'(에서|으로|에는|이|가|을|를|은|는|도|에|의)$'), ''),
        )
        .map(_compactManual)
        .where((t) => t.length > 1)
        .toList();
    // Preserve multi-word component names, instead of treating every occurrence
    // of e.g. "rear", "brake" and "hose" as the same subject.
    for (var n = 2; n <= 3; n++) {
      for (var i = 0; i + n <= words.length; i++) {
        terms.add(words.sublist(i, i + n).join());
      }
    }
    final compactQuestion = _compactManual(question);
    final subjects = <String>{};
    for (final group in _manualSynonyms) {
      if (group.any(compactQuestion.contains)) {
        terms.addAll(group);
        if (group.first != '분리' &&
            group.first != '교체' &&
            group.first != '시동안걸') {
          subjects.addAll(group);
        }
      }
    }
    for (final name in partsIn(question)) {
      subjects.addAll([name, ...standardParts[name]!].map(_compactManual));
    }
    final texts = eligible.values
        .map((r) => r['search_text'] as String)
        .toList();
    final average = texts.isEmpty
        ? 1.0
        : texts.fold<int>(0, (n, t) => n + t.length) / texts.length;
    final weights = <String, double>{};
    final patterns = <String, RegExp>{};
    for (final term in terms) {
      final frequency = texts.where((text) => text.contains(term)).length;
      weights[term] = math.log(
        1 + (texts.length - frequency + .5) / (frequency + .5),
      );
      patterns[term] = RegExp(RegExp.escape(term));
    }
    final uniqueWords = words.toSet();
    final lexical = <String, double>{};
    final headingScores = <String, double>{};
    for (final e in eligible.entries) {
      final text = e.value['search_text'] as String;
      if (subjects.isNotEmpty && !subjects.any(text.contains)) continue;
      var score = 0.0;
      for (final t in terms) {
        final count = patterns[t]!.allMatches(text).length;
        if (count > 0) {
          score +=
              weights[t]! *
              count *
              2.2 /
              (count + 1.2 * (.25 + .75 * text.length / average));
        }
      }
      // Circuit drawings often contain many repeated connector labels. Prefer
      // a matching page heading over a page that merely repeats those labels.
      final headingLines = (e.value['text'] as String)
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(3)
          .toList();
      final heading = _compactManual(headingLines.join(' '));
      final headingMatches = uniqueWords.where(heading.contains).length;
      if (headingMatches >= 2) {
        final title = _compactManual(headingLines.first);
        final titleWords = uniqueWords.where(title.contains).toList();
        headingScores[e.key] =
            (titleWords.length >= 2
                ? 1000.0 +
                      100 *
                          titleWords.fold<int>(0, (n, t) => n + t.length) /
                          math.max(1, title.length)
                : 0.0) +
            terms
                .where((t) => t.length > 1 && heading.contains(t))
                .fold<double>(0, (n, t) => n + weights[t]!);
      }
      for (final t in terms.where(
        (t) => t.length >= 2 && heading.contains(t),
      )) {
        score += weights[t]! * 3;
      }
      if (score > 0) lexical[e.key] = score;
    }
    final semantic = <String, double>{};
    final matched = <String, Map<String, int>>{};
    if (vector != null) {
      final qnorm = math.sqrt(vector.fold<double>(0, (s, v) => s + v * v));
      if (qnorm == 0) throw const FormatException('zero_query_vector');
      // Only pages with a lexical match can be returned. Skip vectors for
      // all other pages. Stream a bounded SQLite result. Vectors stay in this isolate and are
      // never materialized as a large JSON index in Flutter's UI isolate.
      final statement = db.prepare(
        'SELECT page_id,char_start,char_end,vector FROM chunks WHERE page_id=?',
      );
      try {
        for (final pageId in lexical.keys) {
          for (final c in statement.select([pageId])) {
            final bytes = c['vector'] as Uint8List;
            if (bytes.length != 512 * 4) {
              throw const FormatException('invalid_corpus_vector');
            }
            final data = ByteData.sublistView(bytes);
            var dot = 0.0, norm = 0.0;
            for (var i = 0; i < 512; i++) {
              final v = data.getFloat32(i * 4, Endian.little);
              if (!v.isFinite) {
                throw const FormatException('nonfinite_corpus_vector');
              }
              dot += v * vector[i];
              norm += v * v;
            }
            if (norm == 0) throw const FormatException('zero_corpus_vector');
            final score = dot / (qnorm * math.sqrt(norm));
            if (score > (semantic[pageId] ?? -2)) {
              semantic[pageId] = score;
              matched[pageId] = {
                'start': c['char_start'] as int,
                'end': c['char_end'] as int,
              };
            }
          }
        }
      } finally {
        statement.close();
      }
    }
    List<String> ranked(Map<String, double> scores) =>
        scores.keys.toList()..sort((a, b) {
          final c = scores[b]!.compareTo(scores[a]!);
          return c != 0 ? c : a.compareTo(b);
        });
    final fusion = <String, double>{};
    final lexicalRanking = ranked(lexical);
    final semanticRanking = ranked(semantic);
    final headingRanking = ranked(headingScores);
    for (final ranking in [lexicalRanking, semanticRanking]) {
      for (var i = 0; i < math.min(60, ranking.length); i++) {
        fusion.update(
          ranking[i],
          (v) => v + 1 / (60 + i + 1),
          ifAbsent: () => 1 / (60 + i + 1),
        );
      }
    }
    final hits = <Map<String, Object?>>[];
    final ordered = ranked(fusion);
    final headingAnchor = headingRanking.firstOrNull;
    if (headingAnchor != null && !ordered.take(5).contains(headingAnchor)) {
      ordered.remove(headingAnchor);
      ordered.insert(0, headingAnchor);
    }
    final anchor = lexicalRanking.firstOrNull;
    // Keep the strongest lexical source in the final set, even if broad
    // semantic matches would otherwise push it outside the first five.
    if (anchor != null && !ordered.take(5).contains(anchor)) {
      ordered.remove(anchor);
      ordered.insert(math.min(4, ordered.length), anchor);
    }
    for (final id in ordered) {
      // Similarity alone is not evidence. Require a lexical anchor as well;
      // matching is still a retrieval heuristic, not an answer confidence score.
      if ((lexical[id] ?? 0) <= 0) continue;
      final r = eligible[id]!;
      final text = r['text'] as String;
      final span = matched[id];
      var excerpt = text;
      if (span != null) {
        final runes = text.runes.toList();
        if (span['start']! < 0 ||
            span['end']! > runes.length ||
            span['end']! <= span['start']!) {
          throw const FormatException('invalid_corpus_offsets');
        }
        excerpt = String.fromCharCodes(
          runes.sublist(span['start']!, span['end']!),
        );
      }
      if (span == null && excerpt.runes.length > 420) {
        final lines = text.split('\n');
        final focused = lines.where((line) {
          final compact = _compactManual(line);
          return subjects.isEmpty
              ? terms.any(compact.contains)
              : subjects.any(compact.contains);
        }).firstOrNull;
        excerpt = String.fromCharCodes((focused ?? text).runes.take(420));
      }
      hits.add({
        'id': id,
        'text': text,
        'excerpt': excerpt,
        'file': r['file'],
        'sha256': r['sha256'],
        'page': r['page'],
        'location': r['location'],
        'kind': r['kind'],
        'textMethod': r.keys.contains('text_method') ? r['text_method'] : 'pdf',
        'ocrConfidence': r.keys.contains('ocr_confidence')
            ? r['ocr_confidence']
            : null,
        'lexicalScore': lexical[id] ?? 0,
        'semanticScore': semantic[id],
      });
      if (hits.length == 5) break;
    }
    return {
      'hits': hits,
      'headingIds': headingRanking.take(5).toList(),
      'lexicalIds': lexicalRanking.take(5).toList(),
      'semanticIds': semanticRanking.take(5).toList(),
      'eligiblePages': eligible.length,
      'mode': vector == null ? 'keyword_fallback' : 'hybrid',
    };
  } finally {
    db.close();
  }
}

Map<String, Object?>? manualCorpusPage(
  String path,
  String hash,
  String config,
  String document,
  int page,
) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(document) ||
      page < 1 ||
      page > 10000) {
    return null;
  }
  final db = _openManual(path, hash, config);
  try {
    final rows = db.select(
      'SELECT p.*,d.file,d.sha256,d.kind FROM pages p JOIN documents d ON p.doc_id=d.id WHERE p.doc_id=? AND p.page=?',
      [document, page],
    );
    if (rows.length != 1) return null;
    final r = rows.single;
    return {
      'id': r['id'],
      'file': r['file'],
      'sha256': r['sha256'],
      'page': r['page'],
      'location': r['location'],
      'text': r['text'],
      'textMethod': r.keys.contains('text_method') ? r['text_method'] : 'pdf',
      'ocrConfidence': r.keys.contains('ocr_confidence')
          ? r['ocr_confidence']
          : null,
    };
  } finally {
    db.close();
  }
}

class ManualRagResult {
  const ManualRagResult(
    this.evidence,
    this.mode, {
    this.hits = const [],
    this.reason,
    this.elapsedMs = 0,
  });
  final List<MaintenanceEvidence> evidence;
  final List<Map<String, Object?>> hits;
  final String mode;
  final String? reason;
  final double elapsedMs;
}

class ManualRag {
  ManualRag(this.runtime);
  final AdaptiveRuntime runtime;
  Future<Map<String, Object?>> info() async {
    await runtime.initialize();
    final path = runtime.modelInfo['corpusDatabasePath'] as String?;
    if (path == null) {
      return {'documents': <Map<String, Object?>>[], 'pages': 0, 'chunks': 0};
    }
    final hash = runtime.modelInfo['modelSha256'] as String,
        config = runtime.modelInfo['executionConfig'] as String;
    return Isolate.run(() => manualCorpusInfo(path, hash, config));
  }

  static MaintenanceEvidence evidenceFromPage(
    Map<String, Object?> h, {
    String part = '',
  }) => MaintenanceEvidence(
    id: 'BOOK-${h['id']}',
    model: '렉스턴스포츠 · 책자 참고 자료',
    part: part.isEmpty ? '책자 원문' : part,
    symptoms: '',
    title: h['file'] as String,
    location: h['location'] as String,
    text: h['text'] as String,
    sourceRef: {
      'file': h['file'],
      'page': h['page'],
      'location': h['location'],
      'sha256': h['sha256'],
      'textMethod': h['textMethod'] ?? 'pdf',
      'ocrConfidence': h['ocrConfidence'],
    },
  );

  Future<MaintenanceEvidence?> page(String document, int page) async {
    try {
      await runtime.initialize();
      final path = runtime.modelInfo['corpusDatabasePath'] as String?;
      if (path == null) return null;
      final hash = runtime.modelInfo['modelSha256'] as String,
          config = runtime.modelInfo['executionConfig'] as String;
      final result = await Isolate.run(
        () => manualCorpusPage(path, hash, config, document, page),
      );
      return result == null ? null : evidenceFromPage(result);
    } catch (_) {
      return null;
    }
  }

  Future<ManualRagResult> search(
    String question, {
    String document = '',
    String part = '',
  }) async {
    if (question.trim().isEmpty || question.runes.length > 500) {
      return const ManualRagResult(
        [],
        'unavailable',
        reason: '질문을 1~500자로 입력해 주세요.',
      );
    }
    final watch = Stopwatch()..start();
    try {
      await runtime.initialize();
      final path = runtime.modelInfo['corpusDatabasePath'] as String?;
      if (path == null) {
        return const ManualRagResult(
          [],
          'unavailable',
          reason: '전체 책자 검색 묶음을 먼저 반입해 주세요.',
        );
      }
      final hash = runtime.modelInfo['modelSha256'] as String,
          config = runtime.modelInfo['executionConfig'] as String;
      List<num>? vector;
      try {
        final run = await runtime.run(ModelTask.embedding, {'text': question});
        final raw = run.output?['embedding'];
        if (run.mode == 'model' &&
            run.output?['modelSha256'] == hash &&
            run.output?['executionConfig'] == config &&
            raw is List &&
            raw.length == 512 &&
            raw.every((v) => v is num && v.isFinite) &&
            raw.any((v) => v != 0)) {
          vector = raw.cast<num>().toList();
        }
      } catch (_) {
        /* A native failure must preserve lexical retrieval. */
      }
      final queryVector = vector;
      final data = await Isolate.run(
        () => searchManualCorpus(
          path: path,
          hash: hash,
          config: config,
          question: question,
          vector: queryVector,
          document: document,
          part: part,
        ),
      );
      final hits = (data['hits'] as List).cast<Map<String, Object?>>();
      return ManualRagResult(
        [for (final h in hits) evidenceFromPage(h, part: part)],
        data['mode'] as String,
        hits: hits,
        elapsedMs: watch.elapsedMicroseconds / 1000,
      );
    } catch (_) {
      return const ManualRagResult(
        [],
        'unavailable',
        reason: '검색 자료를 읽지 못했습니다. 묶음 파일을 확인해 주세요.',
      );
    }
  }
}
