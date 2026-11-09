import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'store.dart';

class ManualPageImage {
  const ManualPageImage({
    required this.evidenceId,
    required this.title,
    required this.location,
    required this.pdfPage,
    required this.width,
    required this.height,
    required this.bytes,
  });
  final String evidenceId, title, location;
  final int pdfPage, width, height;
  final Uint8List bytes;
}

/// Images are joined to the exact cited page/document, never a guessed filename
/// or a remote URL. Keep bytes outside the main search result and load on demand.
class ManualPageImages {
  const ManualPageImages(this.path, this.modelSha, this.config);
  final String path, modelSha, config;

  Future<ManualPageImage?> load(MaintenanceEvidence evidence) async {
    final source = evidence.sourceRef;
    final sha = source?['sha256'],
        page = source?['page'],
        file = source?['file'];
    if (!evidence.id.startsWith('BOOK-') ||
        sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        page is! int ||
        page < 1 ||
        page > 10000 ||
        file is! String) {
      return null;
    }
    try {
      return await Isolate.run(() => _read(evidence));
    } catch (_) {
      // Legacy bundles and damaged/missing previews must preserve the text reply.
      return null;
    }
  }

  ManualPageImage? _read(MaintenanceEvidence evidence) {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() > 1024 * 1024 * 1024) {
      return null;
    }
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final meta = {
        for (final r in db.select('SELECT key,value FROM metadata'))
          r['key']: r['value'],
      };
      if (meta['version'] != '2' ||
          meta['modelSha256'] != modelSha ||
          meta['executionConfig'] != config ||
          meta['imageFormat'] != 'jpeg-pages-v1') {
        return null;
      }
      final rows = db.select(
        '''SELECT i.width,i.height,i.jpeg,p.page,p.location,d.file
        FROM page_images i JOIN pages p ON p.id=i.page_id
        JOIN documents d ON d.id=p.doc_id
        WHERE p.id=? AND p.page=? AND d.sha256=? AND d.file=?
        AND length(i.jpeg) BETWEEN 128 AND 2097152
        AND i.width BETWEEN 1 AND 1800 AND i.height BETWEEN 1 AND 1800''',
        [
          evidence.id.substring(5),
          evidence.sourceRef!['page'],
          evidence.sourceRef!['sha256'],
          evidence.sourceRef!['file'],
        ],
      );
      if (rows.length != 1) return null;
      final row = rows.single;
      final width = row['width'] as int, height = row['height'] as int;
      final bytes = Uint8List.fromList(row['jpeg'] as List<int>);
      if (width < 1 ||
          width > 1800 ||
          height < 1 ||
          height > 1800 ||
          bytes.length < 128 ||
          bytes.length > 2 * 1024 * 1024 ||
          bytes[0] != 0xff ||
          bytes[1] != 0xd8 ||
          bytes[bytes.length - 2] != 0xff ||
          bytes.last != 0xd9) {
        return null;
      }
      return ManualPageImage(
        evidenceId: evidence.id,
        title: row['file'] as String,
        location: row['location'] as String,
        pdfPage: row['page'] as int,
        width: width,
        height: height,
        bytes: bytes,
      );
    } finally {
      db.close();
    }
  }
}
