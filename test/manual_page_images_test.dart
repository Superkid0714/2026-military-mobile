import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:military_maintenance/data/manual_page_images.dart';
import 'package:military_maintenance/data/store.dart';

void main() {
  late Directory dir;
  late String path;
  MaintenanceEvidence evidence({
    String? sha,
    int page = 7,
    String file = 'sample-manual.pdf',
  }) => MaintenanceEvidence(
    id: 'BOOK-P1',
    model: 'sample',
    part: '',
    symptoms: '',
    title: file,
    location: 'PDF 7쪽',
    text: 'test',
    sourceRef: {'sha256': sha ?? 'b' * 64, 'page': page, 'file': file},
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('manual-images-');
    path = '${dir.path}/corpus.sqlite';
    final db = sqlite3.open(path);
    db.execute('CREATE TABLE metadata(key TEXT,value TEXT)');
    for (final e in {
      'version': '2',
      'modelSha256': 'a' * 64,
      'executionConfig': 'CPU',
      'imageFormat': 'jpeg-pages-v1',
    }.entries) {
      db.execute('INSERT INTO metadata VALUES(?,?)', [e.key, e.value]);
    }
    db.execute('CREATE TABLE documents(id TEXT,file TEXT,sha256 TEXT)');
    db.execute(
      'CREATE TABLE pages(id TEXT,doc_id TEXT,page INTEGER,location TEXT)',
    );
    db.execute(
      'CREATE TABLE page_images(page_id TEXT,width INTEGER,height INTEGER,jpeg BLOB)',
    );
    db.execute('INSERT INTO documents VALUES(?,?,?)', [
      'D1',
      'sample-manual.pdf',
      'b' * 64,
    ]);
    db.execute("INSERT INTO pages VALUES('P1','D1',7,'PDF 7쪽')");
    db.execute('INSERT INTO page_images VALUES(?,?,?,?)', [
      'P1',
      300,
      420,
      File('test/fixtures/manual_preview.jpg').readAsBytesSync(),
    ]);
    db.close();
  });
  tearDown(() async => dir.delete(recursive: true));
  test('인용 문서 해시·파일·페이지가 모두 맞는 이미지와 원문 위치를 읽는다', () async {
    final page = await ManualPageImages(path, 'a' * 64, 'CPU').load(evidence());
    expect(page, isNotNull);
    expect(page!.pdfPage, 7);
    expect(page.width, 300);
    expect(page.height, 420);
    expect(
      page.bytes,
      File('test/fixtures/manual_preview.jpg').readAsBytesSync(),
    );
  });
  test('같은 페이지 ID여도 다른 원문·페이지·파일의 이미지를 잘못 붙이지 않는다', () async {
    final images = ManualPageImages(path, 'a' * 64, 'CPU');
    expect(await images.load(evidence(sha: 'c' * 64)), isNull);
    expect(await images.load(evidence(page: 8)), isNull);
    expect(await images.load(evidence(file: 'different.pdf')), isNull);
    expect(
      await ManualPageImages(path, 'wrong', 'CPU').load(evidence()),
      isNull,
    );
  });
  test('기존 그림 없는 검색 묶음은 글 답변을 방해하지 않는다', () async {
    final db = sqlite3.open(path);
    db.execute("DELETE FROM metadata WHERE key='imageFormat'");
    db.execute('DROP TABLE page_images');
    db.close();
    expect(
      await ManualPageImages(path, 'a' * 64, 'CPU').load(evidence()),
      isNull,
    );
  });
  test('손상된 그림·과도한 해상도·없는 파일은 보류한다', () async {
    final db = sqlite3.open(path);
    db.execute('UPDATE page_images SET jpeg=?', [Uint8List(200)]);
    db.close();
    expect(
      await ManualPageImages(path, 'a' * 64, 'CPU').load(evidence()),
      isNull,
    );
    final second = sqlite3.open(path);
    second.execute('UPDATE page_images SET width=50000,jpeg=?', [
      File('test/fixtures/manual_preview.jpg').readAsBytesSync(),
    ]);
    second.close();
    expect(
      await ManualPageImages(path, 'a' * 64, 'CPU').load(evidence()),
      isNull,
    );
    expect(
      await ManualPageImages('$path-missing', 'a' * 64, 'CPU').load(evidence()),
      isNull,
    );
  });
}
