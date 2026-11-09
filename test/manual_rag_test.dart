import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:military_maintenance/data/manual_rag.dart';
import 'package:military_maintenance/data/adaptive_runtime.dart';
import 'package:military_maintenance/data/model_execution.dart';

class ManualTestRuntime extends AdaptiveRuntime {
  ManualTestRuntime(String path) {
    modelInfo = {
      'corpusDatabasePath': path,
      'modelSha256': 'TEST',
      'executionConfig': 'CPU',
    };
  }
  bool fail = false;
  @override
  Future<void> initialize() async {}
  @override
  Future<ModelRunResult> run(
    ModelTask task,
    Map<String, Object?> input,
  ) async => fail
      ? const ModelRunResult('unavailable', reason: 'test')
      : ModelRunResult(
          'model',
          output: {
            'modelSha256': 'TEST',
            'executionConfig': 'CPU',
            'embedding': [1.0, ...List.filled(511, 0.0)],
          },
        );
}

void main() {
  late Directory dir;
  late String path;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('manual-rag-');
    path = '${dir.path}/corpus.sqlite';
    final db = sqlite3.open(path);
    db.execute('CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT)');
    for (final e in {
      'version': '2',
      'dimension': '512',
      'modelSha256': 'TEST',
      'executionConfig': 'CPU',
    }.entries) {
      db.execute('INSERT INTO metadata VALUES(?,?)', [e.key, e.value]);
    }
    db.execute(
      'CREATE TABLE documents(id TEXT,file TEXT,sha256 TEXT,kind TEXT,pages INTEGER)',
    );
    db.execute(
      'CREATE TABLE pages(id TEXT,doc_id TEXT,page INTEGER,location TEXT,text TEXT,search_text TEXT)',
    );
    db.execute(
      'CREATE TABLE chunks(page_id TEXT,char_start INTEGER,char_end INTEGER,vector BLOB)',
    );
    final bytes = ByteData(512 * 4)..setFloat32(0, 1.0, Endian.little);
    for (final d in [
      ('ENGINE', 'P1', '가상엔진.pdf', '가상 필터 잠금핀을 분리한다. 🛠️'),
      ('CHASSIS', 'P2', '가상차대.pdf', '가상 타이어를 점검한다.'),
    ]) {
      db.execute('INSERT INTO documents VALUES(?,?,?,?,?)', [
        d.$1,
        d.$3,
        'a' * 64,
        'manual',
        10,
      ]);
      db.execute('INSERT INTO pages VALUES(?,?,?,?,?,?)', [
        d.$2,
        d.$1,
        7,
        'PDF 7쪽',
        d.$4,
        d.$4.replaceAll(' ', ''),
      ]);
      db.execute('INSERT INTO chunks VALUES(?,?,?,?)', [
        d.$2,
        0,
        d.$4.runes.length,
        bytes.buffer.asUint8List(),
      ]);
    }
    db.close();
  });
  tearDown(() async => dir.delete(recursive: true));
  Map<String, Object?> search(
    String question, {
    String document = '',
    List<num>? vector,
  }) => searchManualCorpus(
    path: path,
    hash: 'TEST',
    config: 'CPU',
    question: question,
    document: document,
    vector: vector,
  );
  test('검색 문자가 없는 페이지도 직접 열고 OCR 출처를 구별한다', () {
    final db = sqlite3.open(path);
    db.execute("ALTER TABLE pages ADD COLUMN text_method TEXT DEFAULT 'pdf'");
    db.execute('ALTER TABLE pages ADD COLUMN ocr_confidence REAL');
    db.execute(
      "UPDATE pages SET search_text='',text_method='ocr',ocr_confidence=0.6 WHERE id='P1'",
    );
    db.close();
    expect(search('가상 필터 잠금핀', document: 'ENGINE')['hits'], isEmpty);
    final page = manualCorpusPage(path, 'TEST', 'CPU', 'ENGINE', 7)!;
    expect(page['id'], 'P1');
    expect(page['textMethod'], 'ocr');
    expect(page['ocrConfidence'], 0.6);
    expect(manualCorpusPage(path, 'TEST', 'CPU', 'ENGINE', 8), isNull);
    expect(manualCorpusPage(path, 'TEST', 'CPU', '../ENGINE', 7), isNull);
  });
  test('다중 책자를 검색하고 정확한 파일·쪽·유니코드 원문 구간을 반환한다', () {
    final result = search('가상 필터 잠금핀');
    final hit = (result['hits'] as List).first as Map;
    expect(hit['file'], '가상엔진.pdf');
    expect(hit['page'], 7);
    expect(hit['sha256'], 'a' * 64);
    expect(hit['excerpt'], contains('🛠️'));
    expect(result['mode'], 'keyword_fallback');
  });
  test('문서 범위를 벗어난 근거와 근거 없는 질문은 반환하지 않는다', () {
    expect(search('가상 필터 잠금핀', document: 'UNKNOWN')['hits'], isEmpty);
    expect(search('은하철도 커피 원두')['hits'], isEmpty);
    expect(
      search('은하철도 커피 원두', vector: [1, ...List.filled(511, 0)])['hits'],
      isEmpty,
    );
    expect(search('가상 타이어', document: 'CHASSIS')['hits'], hasLength(1));
  });
  test('불일치 모델과 손상된 벡터는 검색 결과로 사용하지 않는다', () {
    expect(
      () => searchManualCorpus(
        path: path,
        hash: 'WRONG',
        config: 'CPU',
        question: '필터',
      ),
      throwsFormatException,
    );
    expect(
      () => search('필터', vector: [double.nan, ...List.filled(511, 0)]),
      throwsFormatException,
    );
    final db = sqlite3.open(path);
    db.execute('UPDATE chunks SET vector=?', [Uint8List(4)]);
    db.close();
    expect(
      () => search('필터', vector: [1, ...List.filled(511, 0)]),
      throwsFormatException,
    );
  });
  test('네이티브 임베딩 실패 시에도 별도 isolate에서 키워드 검색을 유지한다', () async {
    final runtime = ManualTestRuntime(path)..fail = true;
    final result = await ManualRag(runtime).search('가상 필터 잠금핀');
    expect(result.mode, 'keyword_fallback');
    expect(result.evidence.first.sourceRef?['page'], 7);
    expect((await ManualRag(runtime).info())['pages'], 2);
    runtime.dispose();
  });
}
