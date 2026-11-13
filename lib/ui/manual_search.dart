import 'maintenance_loading.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/adaptive_runtime.dart';
import '../data/local_summary.dart';
import '../data/manual_rag.dart';
import '../data/offline_assistant.dart';
import '../data/store.dart';
import 'components.dart';
import 'manual_book_reader.dart';
import 'manual_page_image.dart';

class ManualSearchScreen extends ConsumerStatefulWidget {
  const ManualSearchScreen({this.initialQuery = '', super.key});
  final String initialQuery;
  @override
  ConsumerState<ManualSearchScreen> createState() => _ManualSearchState();
}

class _ManualSearchState extends ConsumerState<ManualSearchScreen> {
  final query = TextEditingController();
  String document = '', part = '';
  Map<String, Object?>? corpus;
  String? error;
  bool loading = true, busy = false;
  ManualRagResult? result;
  GroundedSummary? summary;
  @override
  void initState() {
    super.initState();
    query.text = widget.initialQuery;
    load();
  }

  Future<void> load() async {
    try {
      final info = await ManualRag(ref.read(adaptiveRuntimeProvider)).info();
      if (mounted) setState(() => corpus = info);
    } catch (_) {
      if (mounted) setState(() => error = '책자 검색 자료를 확인하지 못했습니다. 다시 반입해 주세요.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> search() async {
    if (busy || query.text.trim().isEmpty) return;
    final question = query.text.trim(),
        selectedDocument = document,
        selectedPart = part;
    setState(() {
      busy = true;
      result = null;
      summary = null;
      error = null;
    });
    final runtime = ref.read(adaptiveRuntimeProvider);
    final found = await ManualRag(runtime)
        .search(question, document: selectedDocument, part: selectedPart);
    if (!mounted) return;
    setState(() {
      result = found;
      busy = false;
      final extracted = LocalSummary.directExtract(question, found.evidence);
      final seen = <String>{};
      final excerpts = extracted.excerpts
          .where(
            (item) =>
                OfflineAssistant.fitsQuestion(question, item.quote) &&
                seen.add(OfflineAssistant.plainExplanation(item.quote)),
          )
          .toList();
      summary = GroundedSummary(
        excerpts.isEmpty ? 'retrieval_only' : 'extractive_summary',
        excerpts: excerpts,
      );
    });
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  void source(MaintenanceEvidence e) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('${e.title} · ${e.location}'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManualPageImageCard(e),
                ExpansionTile(
                  title: const Text('책자에서 가져온 글 보기'),
                  children: [SelectableText(e.text)],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('닫기')),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final documents = (corpus?['documents'] as List? ?? const []).cast<Map>();
    final available = documents.isNotEmpty;
    final enabled = !busy;
    final evidence = result?.evidence ?? const <MaintenanceEvidence>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageTitle('책자 검색', '필요한 내용을 물어보고 원본 그림까지 확인하세요.'),
          if (loading) const MaintenanceLoading(detail: '설치된 책자를 확인하고 있어요.'),
          if (error != null) Text(error!),
          if (!loading && !available) ...[
            const Text('현재 검색할 수 있는 정비 책자가 없습니다.'),
          ],
          if (available) ...[
            TextField(
              controller: query,
              enabled: enabled,
              maxLength: 500,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '책자에 질문하기',
                hintText: '예: 브레이크 패드를 분리할 때 주의할 점은?',
              ),
              onSubmitted: enabled ? (_) => search() : null,
              onChanged: (_) => setState(() {
                result = null;
                summary = null;
              }),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey('manual-rag-search'),
                onPressed: enabled && query.text.trim().isNotEmpty
                    ? search
                    : null,
                icon: const Icon(Icons.manage_search),
                label: Text(busy ? '찾는 중…' : '검색'),
              ),
            ),
            if (busy) const MaintenanceLoading(detail: '관련 원문과 그림을 찾고 있어요.'),
          ],
          if (available)
            ExpansionTile(
              title: const Text('검색 범위'),
              subtitle: Text(
                document.isEmpty && part.isEmpty
                    ? '전체 책자 · 전체 부품'
                    : [
                        if (document.isNotEmpty)
                          documents.firstWhere(
                                (item) => item['id'] == document,
                              )['file']
                              as String,
                        if (part.isNotEmpty) part,
                      ].join(' · '),
              ),
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 360,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(document),
                        initialValue: document,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '문서 범위'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('전체 책자'),
                          ),
                          for (final d in documents)
                            DropdownMenuItem(
                              value: d['id'] as String,
                              child: Text(
                                d['file'] as String,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: enabled
                            ? (v) => setState(() {
                                document = v ?? '';
                                result = null;
                                summary = null;
                              })
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(part),
                        initialValue: part,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '본문 부품 필터',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('전체 부품'),
                          ),
                          for (final p in standardParts.keys)
                            DropdownMenuItem(value: p, child: Text(p)),
                        ],
                        onChanged: enabled
                            ? (v) => setState(() {
                                part = v ?? '';
                                result = null;
                                summary = null;
                              })
                            : null,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: enabled && (document.isNotEmpty || part.isNotEmpty)
                      ? () => setState(() {
                          document = '';
                          part = '';
                          result = null;
                          summary = null;
                        })
                      : null,
                  child: const Text('전체로 초기화'),
                ),
              ],
            ),
          if (result != null) ...[
            const SizedBox(height: 20),
            if (result!.reason != null) Text(result!.reason!),
            if (evidence.isEmpty && result!.reason == null)
              Text(
                document.isEmpty && part.isEmpty
                    ? '관련 내용을 찾지 못했어요. 부품 이름과 증상을 함께 입력해 보세요.'
                    : '선택한 범위에서 찾지 못했어요. 검색 범위를 전체로 바꿔 보세요.',
              ),
            if (summary?.mode == 'extractive_summary')
              Panel(
                title: '원문에 근거한 답변',
                subtitle: '책자에 나온 내용을 쉬운 말로 정리했습니다.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (index, excerpt) in summary!.excerpts.indexed)
                      Builder(
                        builder: (context) {
                          final page = evidence.firstWhere(
                            (e) => e.id == excerpt.citation,
                          );
                          final explanation = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                OfflineAssistant.plainExplanation(
                                  excerpt.quote,
                                ),
                                style: const TextStyle(height: 1.55),
                              ),
                              TextButton(
                                onPressed: () => source(page),
                                child: Text('출처: ${page.location}'),
                              ),
                            ],
                          );
                          final alreadyShown = summary!.excerpts
                              .take(index)
                              .any(
                                (earlier) =>
                                    earlier.citation == excerpt.citation,
                              );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: alreadyShown
                                ? explanation
                                : ManualPageImageCard(
                                    page,
                                    key: ValueKey(page.id),
                                    explanation: explanation,
                                  ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            if (evidence.isNotEmpty && summary?.mode != 'extractive_summary')
              const Text('관련 페이지를 찾았어요. 정확한 내용은 원문·그림에서 확인해 주세요.'),
            const SizedBox(height: 16),
            for (var i = 0; i < evidence.length; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${i + 1}. ${evidence[i].title}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(evidence[i].location),
                      if (result!.hits[i]['kind'] == 'catalog')
                        const Text('품번 참고 자료 · 차량 적용 여부는 별도 확인'),
                      TextButton(
                        onPressed: () => source(evidence[i]),
                        child: const Text('원문·그림 보기'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (available) ...[
            const SizedBox(height: 16),
            ManualBookReader(documents),
          ],
        ],
      ),
    );
  }
}
