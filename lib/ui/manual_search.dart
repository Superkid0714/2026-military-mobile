import 'maintenance_loading.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/adaptive_runtime.dart';
import '../data/local_summary.dart';
import '../data/manual_rag.dart';
import '../data/store.dart';
import 'components.dart';
import 'manual_book_reader.dart';

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
  bool loading = true, busy = false, summarizing = false;
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
    if (busy || summarizing || query.text.trim().isEmpty) return;
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
    });
    setState(
      () => summary = LocalSummary.directExtract(question, found.evidence),
    );
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
                Text(e.text),
                const SizedBox(height: 20),
                Text('원본 파일 확인번호: ${e.sourceRef?['sha256']}'),
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
    final enabled = !busy && !summarizing;
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
            const Text('아직 가져온 정비 책자가 없습니다. 책자 파일을 가져온 뒤 검색할 수 있습니다.'),
            TextButton(
              onPressed: () => context.go('/data-tools'),
              child: const Text('책자 가져오기'),
            ),
          ],
          if (available) ...[
            Text(
              '${documents.length}권 · 전체 ${corpus?['pages']}쪽 · 텍스트 검색 ${corpus?['searchablePages'] ?? corpus?['pages']}쪽',
            ),
            ManualBookReader(documents),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 360,
                  child: DropdownButtonFormField<String>(
                    initialValue: document,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '문서 범위'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('전체 책자')),
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
                    initialValue: part,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '본문 부품 필터'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('전체 부품')),
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
            const SizedBox(height: 16),
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
                label: Text(
                  busy
                      ? '원문 검색 중…'
                      : summarizing
                      ? '근거 답변 정리 중…'
                      : '검색',
                ),
              ),
            ),
            if (busy || summarizing)
              const MaintenanceLoading(detail: '관련 원문과 그림을 찾고 있어요.'),
          ],
          if (result != null) ...[
            const SizedBox(height: 20),
            Text(
              result!.mode == 'hybrid'
                  ? '질문 뜻과 입력한 말을 함께 살펴 찾기'
                  : '입력한 말이 들어 있는 내용부터 찾았습니다.',
            ),
            if (result!.reason != null) Text(result!.reason!),
            if (evidence.isEmpty)
              const Text('질문과 연결할 근거를 찾지 못했습니다. 문서·부품 범위와 질문을 확인해 주세요.'),
            if (summary?.mode == 'extractive_summary')
              Panel(
                title: '원문에 근거한 답변',
                subtitle: '문장을 직접 인용합니다. 인용을 눌러 문맥을 확인하세요.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in summary!.excerpts) ...[
                      SelectableText(s.quote),
                      TextButton(
                        onPressed: () => source(
                          evidence.firstWhere((e) => e.id == s.citation),
                        ),
                        child: Text(
                          '출처: ${evidence.firstWhere((e) => e.id == s.citation).location}',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (!summarizing &&
                evidence.isNotEmpty &&
                summary?.mode != 'extractive_summary')
              const Text('원문 근거를 표시합니다. 수치·교환주기는 원문과 등록 기준에서 확인해 주세요.'),
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
                      Text(
                        result!.hits[i]['excerpt'] as String,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (result!.hits[i]['kind'] == 'catalog')
                        const Text('품번 참고 자료 · 차량 적용 여부는 별도 확인'),
                      TextButton(
                        onPressed: () => source(evidence[i]),
                        child: const Text('인용 원문 전체 보기'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
