import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/adaptive_runtime.dart';
import '../data/manual_rag.dart';
import '../data/store.dart';
import 'manual_page_image.dart';

class ManualBookReader extends ConsumerStatefulWidget {
  const ManualBookReader(this.documents, {super.key});
  final List<Map> documents;
  @override
  ConsumerState<ManualBookReader> createState() => _ManualBookReaderState();
}

class _ManualBookReaderState extends ConsumerState<ManualBookReader> {
  final page = TextEditingController(text: '1');
  String? document, error;
  MaintenanceEvidence? source;
  bool busy = false;
  @override
  void dispose() {
    page.dispose();
    super.dispose();
  }

  Future<void> open(int number) async {
    final doc = widget.documents.firstWhere((d) => d['id'] == document);
    if (number < 1 || number > (doc['pages'] as int)) {
      setState(() => error = '1~${doc['pages']}쪽 사이의 페이지를 입력해 주세요.');
      return;
    }
    setState(() {
      busy = true;
      source = null;
      error = null;
      page.text = '$number';
    });
    try {
      final found = await ManualRag(ref.read(adaptiveRuntimeProvider))
          .page(document!, number);
      if (mounted) {
        setState(() {
          busy = false;
          source = found;
          if (found == null) error = '이 자료에서 페이지를 열지 못했습니다. 검색 묶음을 확인해 주세요.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '페이지를 열지 못했습니다. 설치된 책자 묶음을 확인해 주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.documents.isEmpty) return const SizedBox.shrink();
    document ??= widget.documents.first['id'] as String;
    final doc = widget.documents.firstWhere((d) => d['id'] == document);
    final number = int.tryParse(page.text), total = doc['pages'] as int;
    final valid = number != null && number >= 1 && number <= total;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('책자 직접 보기 · 전체 페이지'),
      subtitle: const Text('검색되지 않는 도면도 책자와 페이지를 선택해 볼 수 있습니다.'),
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(document),
          initialValue: document,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '직접 볼 책자'),
          items: [
            for (final d in widget.documents)
              DropdownMenuItem(
                value: d['id'] as String,
                child: Text(
                  d['file'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: busy
              ? null
              : (value) => setState(() {
                  document = value;
                  source = null;
                  error = null;
                  page.text = '1';
                }),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 180,
              child: TextField(
                key: const ValueKey('manual-reader-page'),
                controller: page,
                enabled: !busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'PDF 페이지',
                  suffixText: '/ $total',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (valid && !busy) open(number);
                },
              ),
            ),
            FilledButton(
              onPressed: busy || !valid ? null : () => open(number),
              child: Text(busy ? '페이지 준비 중…' : '페이지 열기'),
            ),
            TextButton(
              onPressed: busy || !valid || number <= 1
                  ? null
                  : () => open(number - 1),
              child: const Text('이전 페이지'),
            ),
            TextButton(
              onPressed: busy || !valid || number >= total
                  ? null
                  : () => open(number + 1),
              child: const Text('다음 페이지'),
            ),
          ],
        ),
        if (error != null) Text(error!),
        if (source != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ManualPageImageCard(source!, key: ValueKey(source!.id)),
          ),
          if (source!.text.isNotEmpty)
            ExpansionTile(
              title: const Text('페이지 글 보기'),
              children: [
                if (source!.sourceRef?['textMethod'] == 'ocr')
                  const Text('검색용 문자인식 결과입니다. 핀번호·배선색은 원본 도면에서 확인해 주세요.'),
                SelectableText(source!.text),
              ],
            ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
