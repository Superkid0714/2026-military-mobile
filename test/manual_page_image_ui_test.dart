import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/manual_page_images.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/ui/manual_page_image.dart';

void main() {
  const evidence = MaintenanceEvidence(
    id: 'BOOK-P1',
    model: 'sample',
    part: '',
    symptoms: '',
    title: 'sample-manual.pdf',
    location: 'PDF 7쪽',
    text: 'test',
  );
  Future<void> mount(
    WidgetTester tester, {
    bool missing = false,
    bool compact = false,
  }) async {
    tester.view.physicalSize = Size(compact ? 600 : 1280, compact ? 800 : 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = File('test/fixtures/manual_preview.jpg').readAsBytesSync();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          manualImageLoaderProvider.overrideWithValue(
            (_) async => missing
                ? null
                : ManualPageImage(
                    evidenceId: evidence.id,
                    title: evidence.title,
                    location: evidence.location,
                    pdfPage: 7,
                    width: 300,
                    height: 420,
                    bytes: bytes,
                  ),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(compact ? 1.6 : 1)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: ManualPageImageCard(evidence)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('미리보기에서 확대창을 열고 확대·원래 크기·닫기를 사용할 수 있다', (tester) async {
    await mount(tester);
    expect(find.text('눌러서 확대'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('manual-image-open-BOOK-P1')));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    final viewer = find.byType(InteractiveViewer);
    final center = tester.getSize(viewer).center(Offset.zero);
    final controller = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    final previousCenter = controller.toScene(center);
    await tester.tap(find.byTooltip('확대'));
    await tester.pump();
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      greaterThan(1),
    );
    expect(
      (controller.toScene(center) - previousCenter).distance,
      lessThan(.001),
    );
    await tester.tap(find.text('원래 크기'));
    await tester.pump();
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      1,
    );
    await tester.tap(find.byTooltip('그림 닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('그림이 없으면 빈 썸네일이나 잘못된 그림을 표시하지 않는다', (tester) async {
    await mount(tester, missing: true);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('600×800 큰 글자에서도 확대 그림과 닫기를 사용할 수 있다', (tester) async {
    await mount(tester, compact: true);
    await tester.tap(find.byKey(const ValueKey('manual-image-open-BOOK-P1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('확대'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('그림 닫기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
