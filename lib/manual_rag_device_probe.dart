import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'data/adaptive_runtime.dart';
import 'data/local_summary.dart';
import 'data/manual_rag.dart';
import 'data/manual_page_images.dart';
import 'data/store.dart';

Future<void> runManualRagDeviceProbe() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('maintenance/device_probe');
  final runtime = AdaptiveRuntime();
  final report = <String, Object?>{
    'cases': <Map<String, Object?>>[],
    'persistentDatabaseTouched': false,
  };
  try {
    final service = ManualRag(runtime);
    report['corpus'] = await service.info();
    report['physicalDevice'] = runtime.device?.isEmulator == false;
    final corpusInfo = report['corpus'] as Map;
    final books = (corpusInfo['documents'] as List).cast<Map>();
    if (books.length != 7 ||
        corpusInfo['pages'] != 5728 ||
        books.any((b) => ['D01', 'D02'].contains(b['id']))) {
      throw StateError('full_manual_scope_failed');
    }
    final pageChecks = <Map<String, Object?>>[];
    for (final book in books) {
      for (final number in [1, book['pages'] as int]) {
        final page = await service.page(book['id'] as String, number);
        if (page == null || page.sourceRef?['page'] != number) {
          throw StateError('book_boundary_page_missing');
        }
        pageChecks.add({'document': book['id'], 'page': number});
      }
    }
    report['directPageChecks'] = pageChecks;
    final files = File(runtime.modelInfo['corpusDatabasePath'] as String)
        .parent
        .parent
        .parent;
    final packet = jsonDecode(
      await File('${files.path}/manual-rag-questions.json').readAsString(),
    ) as Map;
    final cases = report['cases'] as List<Map<String, Object?>>;
    for (final q in (packet['questions'] as List).cast<Map>()) {
      final result = await service.search(
        q['question'] as String,
        document: q['document'] as String,
        part: q['part'] as String,
      );
      if (result.mode != 'hybrid') throw StateError('hybrid_search_failed');
      final ids = result.hits.map((h) => h['id']).toList();
      final same = jsonEncode(ids) == jsonEncode(q['pcIds']);
      final gold = q['gold'] as List;
      final hit = gold.isEmpty ? ids.isEmpty : ids.any(gold.contains);
      final row = <String, Object?>{
        'id': q['id'],
        'hit5': hit,
        'pcParity': same,
        'ids': ids,
        'elapsedMs': result.elapsedMs,
      };
      cases.add(row);
      final topMatch =
          ids.isNotEmpty &&
          (q['pcIds'] as List).isNotEmpty &&
          ids.first == (q['pcIds'] as List).first;
      row['topRankParity'] = topMatch;
      row['rankPolicy'] = q['rankPolicy'] ?? 'exact';
      if (!hit) throw StateError('reviewed_source_missing');
      if (!same && !(q['rankPolicy'] == 'top1_and_gold' && topMatch)) {
        throw StateError('pc_rank_parity_failed');
      }
      if (q['summary'] == true) {
        final summary = await LocalSummary.summarize(
          runtime,
          q['question'] as String,
          result.evidence,
          maxTokens: 128,
        );
        row['summary'] = {
          'mode': summary.mode,
          'reason': summary.reason,
          'timingsMs': summary.run?.timingsMs,
          'excerpts': summary.excerpts
              .map((s) => {'id': s.citation, 'quote': s.quote})
              .toList(),
        };
        if (summary.mode != 'extractive_summary' || summary.excerpts.isEmpty) {
          throw StateError('summary_failed');
        }
        String compact(String s) => s.replaceAll(RegExp(r'\s+'), '');
        final markers = (q['summaryMustContain'] as List).cast<String>();
        if (!summary.excerpts.any(
          (s) =>
              gold.contains(s.citation.replaceFirst('BOOK-', '')) &&
              markers.every((m) => compact(s.quote).contains(compact(m))),
        )) {
          throw StateError('summary_answer_content_failed');
        }
        if ((runtime.modelInfo['corpusImagePageCount'] as int? ?? 0) > 0) {
          final evidence = result.evidence.firstWhere(
            (e) => e.id == summary.excerpts.first.citation,
          );
          final images = ManualPageImages(
            runtime.modelInfo['corpusDatabasePath'] as String,
            runtime.modelInfo['modelSha256'] as String,
            runtime.modelInfo['executionConfig'] as String,
          );
          final image = await images.load(evidence);
          if (image == null ||
              image.evidenceId != evidence.id ||
              image.pdfPage != evidence.sourceRef!['page']) {
            throw StateError('cited_page_image_missing_or_mismatched');
          }
          final codec = await ui.instantiateImageCodec(image.bytes);
          final frame = await codec.getNextFrame();
          final decoded =
              frame.image.width == image.width &&
              frame.image.height == image.height;
          frame.image.dispose();
          codec.dispose();
          if (!decoded) {
            throw StateError('cited_image_decode_failed');
          }
          final wrong = MaintenanceEvidence(
            id: evidence.id,
            model: evidence.model,
            part: evidence.part,
            symptoms: evidence.symptoms,
            title: evidence.title,
            location: evidence.location,
            text: evidence.text,
            sourceRef: {...evidence.sourceRef!, 'page': image.pdfPage + 1},
          );
          if (await images.load(wrong) != null) {
            throw StateError('wrong_page_image_accepted');
          }
          row['image'] = {
            'evidenceId': image.evidenceId,
            'pdfPage': image.pdfPage,
            'width': image.width,
            'height': image.height,
            'bytes': image.bytes.length,
            'decoded': decoded,
            'wrongPageRejected': true,
          };
        }
      }
    }
    final worker = await AndroidModelWorker.channel
        .invokeMapMethod<String, Object?>('probe');
    report['afterUnload'] = worker;
    if (worker?['loaded'] != false) throw StateError('unload_failed');
    report['hit5'] = cases.where((c) => c['hit5'] == true).length;
    report['status'] = 'passed';
  } catch (e) {
    report['status'] = 'failed';
    report['error'] = '$e';
  } finally {
    await runtime.manager.release();
    runtime.dispose();
  }
  await channel.invokeMethod<Object?>('complete', report);
}
