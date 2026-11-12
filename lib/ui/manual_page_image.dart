import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/adaptive_runtime.dart';
import '../data/manual_page_images.dart';
import '../data/store.dart';
import 'components.dart';

typedef ManualImageLoader = Future<ManualPageImage?> Function(
  MaintenanceEvidence,
);
final manualImageLoaderProvider = Provider<ManualImageLoader>(
  (ref) => (e) async {
    if (e.sourceRef?['sha256'] == null) return null;
    final runtime = ref.read(adaptiveRuntimeProvider);
    await runtime.initialize();
    final info = runtime.modelInfo;
    if (info['corpusDatabasePath'] is! String ||
        info['modelSha256'] is! String ||
        info['executionConfig'] is! String) {
      return null;
    }
    return ManualPageImages(
      info['corpusDatabasePath'] as String,
      info['modelSha256'] as String,
      info['executionConfig'] as String,
    ).load(e);
  },
);

class ManualPageImageCard extends ConsumerStatefulWidget {
  const ManualPageImageCard(this.evidence, {this.explanation, super.key});
  final Widget? explanation;
  final MaintenanceEvidence evidence;
  @override
  ConsumerState<ManualPageImageCard> createState() =>
      _ManualPageImageCardState();
}

class _ManualPageImageCardState extends ConsumerState<ManualPageImageCard> {
  late Future<ManualPageImage?> future;
  @override
  void initState() {
    super.initState();
    future = ref.read(manualImageLoaderProvider)(widget.evidence);
  }

  @override
  void didUpdateWidget(covariant ManualPageImageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.evidence != widget.evidence) {
      future = ref.read(manualImageLoaderProvider)(widget.evidence);
    }
  }

  Widget withExplanation(Widget? preview) {
    final explanation = widget.explanation;
    if (explanation == null) return preview ?? const SizedBox.shrink();
    if (preview == null) return explanation;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 520) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: explanation),
              const SizedBox(width: 16),
              preview,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [explanation, const SizedBox(height: 8), preview],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ManualPageImage?>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return withExplanation(
          const SizedBox(
            width: 220,
            height: 48,
            child: Center(
              child: Text('책자 페이지 준비 중…', style: TextStyle(color: muted)),
            ),
          ),
        );
      }
      final page = snapshot.data;
      if (page == null) return withExplanation(null);
      return withExplanation(
        SizedBox(
          width: 220,
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: line),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('manual-image-open-${page.evidenceId}'),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => ManualPageImageDialog(page),
              ),
              child: Semantics(
                button: true,
                label: '${page.location} 페이지 이미지 확대',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.memory(
                      page.bytes,
                      cacheWidth: 640,
                      width: 220,
                      height: widget.explanation == null ? 280 : 176,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 80,
                        child: Center(child: Text('이미지를 표시하지 못했습니다.')),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            page.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            page.location,
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '눌러서 확대',
                            style: TextStyle(
                              color: green,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ManualPageImageDialog extends StatefulWidget {
  const ManualPageImageDialog(this.page, {super.key});
  final ManualPageImage page;
  @override
  State<ManualPageImageDialog> createState() => _ManualPageImageDialogState();
}

class _ManualPageImageDialogState extends State<ManualPageImageDialog> {
  final transform = TransformationController();
  Size viewport = Size.zero;
  void zoom(double factor) {
    final next = (transform.value.getMaxScaleOnAxis() * factor).clamp(1.0, 5.0);
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final scene = transform.toScene(center);
    transform.value = Matrix4.diagonal3Values(next, next, 1)
      ..setTranslationRaw(
        center.dx - scene.dx * next,
        center.dy - scene.dy * next,
        0,
      );
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    child: SizedBox(
      width: 1100,
      height: MediaQuery.sizeOf(context).height * .9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.page.title}\n${widget.page.location}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: '그림 닫기',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: surface,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  viewport = constraints.biggest;
                  return InteractiveViewer(
                    transformationController: transform,
                    minScale: 1,
                    maxScale: 5,
                    child: Center(
                      child: Image.memory(
                        widget.page.bytes,
                        cacheWidth: widget.page.width,
                        cacheHeight: widget.page.height,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Text('이미지를 표시하지 못했습니다. 원문 내용을 확인해 주세요.'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              const Text(
                '두 손가락으로 확대 · 드래그로 이동',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              IconButton(
                tooltip: '축소',
                onPressed: () => zoom(1 / 1.4),
                icon: const Icon(Icons.remove),
              ),
              TextButton(
                onPressed: () => transform.value = Matrix4.identity(),
                child: const Text('원래 크기'),
              ),
              IconButton(
                tooltip: '확대',
                onPressed: () => zoom(1.4),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
