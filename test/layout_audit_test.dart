import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/main.dart';

import 'app_test.dart' show mount;

import 'package:sqlite3/sqlite3.dart';
import 'package:military_maintenance/data/adaptive_runtime.dart';

class LayoutAuditRuntime extends AdaptiveRuntime {
  LayoutAuditRuntime(String path) {
    modelInfo = {
      'corpusDatabasePath': path,
      'modelSha256': 'TEST',
      'executionConfig': 'CPU',
    };
  }
  @override
  Future<void> initialize() async {}
}

void main() {
  const routes = [
    '/',
    '/vehicles',
    '/vehicles/MOCK-RX-0001',
    '/records',
    '/analysis',
    '/ai-history?vehicle=MOCK-RX-0001',
    '/entry',
    '/data-tools',
    '/more',
    '/field-work',
    '/setup',
    '/support?vehicle=MOCK-RX-0001',
    '/manual-search',
    '/plans',
    '/vision?vehicle=MOCK-RX-0001',
    '/front-map?vehicle=MOCK-RX-0001',
    '/front-map?vehicle=MOCK-RX-0001&area=engineBay',
    '/chat?vehicle=MOCK-RX-0001',
  ];
  for (final config in [
    (const Size(600, 800), 1.6),
    (const Size(800, 1280), 1.3),
    (const Size(1280, 800), 1.0),
    (const Size(1280, 800), 1.6),
  ]) {
    for (var index = 0; index < routes.length; index++) {
      final route = routes[index];
      testWidgets(
        '${config.$1.width.toInt()}x${config.$1.height.toInt()} 글자 ${config.$2} $route',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = config.$2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final dir = Directory.systemTemp.createTempSync('layout-corpus-');
          final path = '${dir.path}/corpus.sqlite';
          final db = sqlite3.open(path);
          db.execute('CREATE TABLE metadata(key TEXT,value TEXT)');
          for (final e in {
            'version': '2',
            'dimension': '512',
            'modelSha256': 'TEST',
            'executionConfig': 'CPU',
          }.entries) {
            db.execute('INSERT INTO metadata VALUES(?,?)', [e.key, e.value]);
          }
          db.execute(
            'CREATE TABLE documents(id TEXT,file TEXT,kind TEXT,pages INTEGER)',
          );
          db.execute('CREATE TABLE pages(id TEXT,search_text TEXT)');
          db.execute('CREATE TABLE chunks(page_id TEXT)');
          for (var i = 3; i <= 9; i++) {
            db.execute('INSERT INTO documents VALUES(?,?,?,?)', [
              'D0$i',
              '시험 차량 정비 지침서 및 전기배선도 긴 제목 $i.pdf',
              'manual',
              700,
            ]);
            db.execute('INSERT INTO pages VALUES(?,?)', ['P$i', '시험']);
          }
          db.close();
          addTearDown(() => dir.deleteSync(recursive: true));
          final store = await mount(
            tester,
            config.$1,
            runtime: LayoutAuditRuntime(path),
          );
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
            await store.db!.close();
          });
          appRouter.go(route);
          await tester.pump();
          // Manual corpus metadata is loaded in a real isolate, outside fake time.
          if (route == '/manual-search') {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 150)),
            );
            await tester.pump();
            await tester.pumpAndSettle();
            await tester.tap(find.text('책자 직접 보기 · 전체 페이지'));
          }
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Initial page: $route',
          );
          final target = Platform.environment['QA_LAYOUT_DIR'];
          if (target != null) {
            if (!Directory(target).absolute.path.contains('/private/')) {
              throw StateError('Private output required');
            }
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byType(RepaintBoundary).first,
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              image.dispose();
              await Directory(target).create(recursive: true);
              await File(
                '$target/${config.$1.width.toInt()}-${config.$1.height.toInt()}-${config.$2}-$index.png',
              ).writeAsBytes(data!.buffer.asUint8List());
            });
          }
          // Walk the body to build lazy rows and catch lower-page overflows too.
          for (var step = 0; step < 6; step++) {
            final states = tester
                .stateList<ScrollableState>(find.byType(Scrollable))
                .where(
                  (s) =>
                      s.position.axis == Axis.vertical &&
                      s.position.viewportDimension > 200,
                )
                .toList();
            if (states.isEmpty) break;
            final position = states.last.position;
            if (position.pixels >= position.maxScrollExtent) break;
            position.jumpTo(
              (position.pixels + position.viewportDimension * .8).clamp(
                0,
                position.maxScrollExtent,
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'Body step $step: $route',
            );
          }
        },
      );
    }
  }
}
