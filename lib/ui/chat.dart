import 'maintenance_loading.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/adaptive_runtime.dart';
import '../data/offline_assistant.dart';
import '../data/store.dart';
import 'components.dart';
import 'manual_page_image.dart';

final offlineAssistantProvider = Provider<OfflineAssistant>(
  (ref) => OfflineAssistant.local(ref.read(adaptiveRuntimeProvider)),
);

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({this.vehicleId, super.key});
  final String? vehicleId;
  @override
  ConsumerState<ChatScreen> createState() => _ChatState();
}

class _ChatState extends ConsumerState<ChatScreen> {
  final question = TextEditingController();
  final scroll = ScrollController();
  final replies = <OfflineReply>[];
  String? vehicle, error, pending;
  bool sending = false;

  @override
  void dispose() {
    question.dispose();
    scroll.dispose();
    super.dispose();
  }

  void bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  Future<void> ask() async {
    final q = question.text.trim(), id = vehicle;
    if (sending || id == null || q.isEmpty) return;
    final store = ref.read(storeProvider);
    final assistant = ref.read(offlineAssistantProvider);
    final previous = replies.lastOrNull?.searchQuestion;
    setState(() {
      sending = true;
      error = null;
      pending = q;
    });
    question.clear();
    bottom();
    try {
      final reply = await assistant.ask(
        store,
        id,
        q,
        previousQuestion: previous,
      );
      var saved = true;
      try {
        await store.saveQuestion(id, q);
      } catch (_) {
        saved = false;
      }
      if (!mounted) return;
      setState(() {
        replies.add(reply);
        if (replies.length > 20) replies.removeAt(0);
        if (!saved) {
          error = '답변은 표시했지만 질문 기록을 저장하지 못했습니다.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          error = '답변을 준비하지 못했습니다. 질문을 다시 보내 주세요.';
          question.text = q;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          sending = false;
          pending = null;
        });
        bottom();
      }
    }
  }

  void source(MaintenanceEvidence e) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${e.title} · ${e.location}'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (e.sourceRef?['textMethod'] == 'ocr')
                const Text('검색용 문자인식 결과입니다. 핀번호·배선색은 도면 원본에서 확인해 주세요.'),
              SelectableText(e.text),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    ),
  );

  Widget answer(OfflineReply reply) => Panel(
    title: '정비 도우미',
    subtitle: '기기 내 분석 · 차량 ${reply.vehicleId}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(reply.text, style: const TextStyle(height: 1.6)),
        if (reply.searchQuestion != reply.question)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '이전 질문을 이어서 확인했습니다.',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ),
        if (reply.priorities.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('점검 순서와 이유'),
            subtitle: const Text('판단에 사용한 등록 기준 보기'),
            children: [
              for (final entry in reply.priorities.asMap().entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    child: Text('${entry.key + 1}'),
                  ),
                  title: Text(entry.value.part),
                  subtitle: Text(entry.value.reason),
                ),
            ],
          ),
        if (reply.excerpts.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('쉽게 설명하면', style: TextStyle(fontWeight: FontWeight.w700)),
          for (var i = 0; i < reply.excerpts.length; i++) ...[
            const SizedBox(height: 12),
            SelectableText(
              reply.explanations.length > i
                  ? reply.explanations[i]
                  : reply.excerpts[i].quote,
              style: const TextStyle(fontSize: 15, height: 1.7),
            ),
            TextButton(
              onPressed: () => source(
                reply.evidence.firstWhere(
                  (e) => e.id == reply.excerpts[i].citation,
                ),
              ),
              child: Text(
                '출처: ${reply.evidence.firstWhere((e) => e.id == reply.excerpts[i].citation).location}',
              ),
            ),
          ],
          if (reply.wordHelp.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '용어 풀이',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final entry in reply.wordHelp.entries)
                    Text(
                      '${entry.key}: ${entry.value}',
                      style: const TextStyle(height: 1.6),
                    ),
                ],
              ),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('책자 표현 그대로 보기'),
            children: [
              for (final excerpt in reply.excerpts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SelectableText(excerpt.quote),
                ),
            ],
          ),
        ],
        if (reply.excerpts.isNotEmpty ||
            reply.evidence.any((e) => e.sourceRef?['textMethod'] == 'ocr')) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final e
                  in reply.evidence
                      .where(
                        (e) =>
                            (reply.excerpts.isEmpty &&
                                e.sourceRef?['textMethod'] == 'ocr') ||
                            reply.excerpts.any((s) => s.citation == e.id),
                      )
                      .take(2))
                ManualPageImageCard(
                  e,
                  key: ValueKey('page-image-${e.id}-${e.sourceRef?['sha256']}'),
                ),
            ],
          ),
        ],
        if (reply.evidence.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('관련 책자 ${reply.evidence.length}개'),
            children: [
              for (final e in reply.evidence)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(e.title),
                  subtitle: Text(e.location),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => source(e),
                ),
            ],
          ),
        if (reply.history.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('관련 정비 이력 ${reply.history.length}건'),
            children: [
              for (final r in reply.history)
                ListTile(
                  title: Text('${r.date} · ${r.part}'),
                  subtitle: Text(maintenanceDescriptionLabel(r)),
                  onTap: () => context.go('/records/${r.id}'),
                ),
            ],
          ),
        for (final notice in reply.notices)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(notice, style: const TextStyle(color: muted)),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(storeProvider);
    final vehicles = s.vehicles;
    if (vehicles.isEmpty) return empty('차량을 등록한 뒤 질문해 주세요.');
    vehicle ??= vehicles.any((v) => v.id == widget.vehicleId)
        ? widget.vehicleId
        : s.activeVehicles.first.id;
    if (!vehicles.any((v) => v.id == vehicle)) {
      vehicle = s.activeVehicles.first.id;
      replies.clear();
    }
    final selected = s.vehicle(vehicle!);
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: scroll,
            children: [
              PageTitle(
                '정비 도우미',
                '',
                scopeVehicles: [selected],
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(vehicle),
                initialValue: vehicle,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '질문할 차량'),
                items: [
                  for (final v in vehicles)
                    DropdownMenuItem(
                      value: v.id,
                      child: Text(
                        '${vehicleLabel(v.id)} · ${modelLabel(v.model)}',
                      ),
                    ),
                ],
                onChanged: sending
                    ? null
                    : (id) => setState(() {
                        vehicle = id;
                        replies.clear();
                        error = null;
                        question.clear();
                      }),
              ),
              const SizedBox(height: 16),
              if (replies.isEmpty && pending == null) ...[
                Panel(
                  title: '질문 예시',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final sample in [
                            '무엇부터 점검해야 해?',
                            '최근 정비 이력을 알려줘',
                            '브레이크 패드를 분리할 때 주의사항은?',
                          ])
                            ActionChip(
                              label: Text(sample),
                              onPressed: () =>
                                  setState(() => question.text = sample),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              for (final reply in replies) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 760),
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(reply.question),
                  ),
                ),
                answer(reply),
                const SizedBox(height: 20),
              ],
              if (sending) ...[
                Text(pending ?? ''),
                const SizedBox(height: 8),
                const MaintenanceLoading(
                  detail: '질문에 맞는 차량 기록과 책자 근거를 찾고 있어요.',
                ),
              ],
              if (error != null)
                Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: question,
          enabled: !sending,
          minLines: 1,
          maxLines: 3,
          maxLength: 500,
          key: const ValueKey('assistant-question'),
          decoration: const InputDecoration(
            labelText: '정비 도우미에게 질문하기',
            hintText: '예: 이 차량은 무엇부터 점검해야 해?',
          ),
          onChanged: (_) => setState(() {}),
        ),
        Row(
          children: [
            TextButton(
              onPressed: sending || replies.isEmpty
                  ? null
                  : () => setState(() {
                      replies.clear();
                      error = null;
                    }),
              child: const Text('새 대화'),
            ),
            const Spacer(),
            FilledButton.icon(
              key: const ValueKey('assistant-send'),
              onPressed: !sending && question.text.trim().isNotEmpty
                  ? ask
                  : null,
              icon: const Icon(Icons.send),
              label: Text(sending ? '확인 중…' : '보내기'),
            ),
          ],
        ),
      ],
    );
  }
}
