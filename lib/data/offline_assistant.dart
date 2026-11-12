import 'package:intl/intl.dart';

import 'adaptive_runtime.dart';
import 'calendar.dart';
import 'inspection_priority.dart';
import 'local_summary.dart';
import 'manual_rag.dart';
import 'store.dart';

typedef AssistantSearch = Future<ManualRagResult> Function(String question);
typedef AssistantSummary = Future<GroundedSummary> Function(
  String question,
  List<MaintenanceEvidence> evidence,
);

class OfflineReply {
  const OfflineReply({
    required this.question,
    required this.searchQuestion,
    required this.vehicleId,
    required this.text,
    this.priorities = const [],
    this.history = const [],
    this.evidence = const [],
    this.excerpts = const [],
    this.notices = const [],
    this.explanations = const [],
    this.wordHelp = const {},
  });
  final String question, searchQuestion, vehicleId, text;
  final List<InspectionPriority> priorities;
  final List<Maintenance> history;
  final List<MaintenanceEvidence> evidence;
  final List<SummaryExcerpt> excerpts;
  final List<String> notices;
  final List<String> explanations;
  final Map<String, String> wordHelp;
}

/// Composes only local facts and validated source excerpts. Never calls a server,
/// executes source instructions, edits records, or turns model scores into repairs.
class OfflineAssistant {
  OfflineAssistant({required this.search, this.summarize});
  final AssistantSearch search;
  final AssistantSummary? summarize;

  factory OfflineAssistant.local(
    AdaptiveRuntime runtime, {
    bool useLocalModel = false,
  }) {
    final rag = ManualRag(runtime);
    List<Map>? documents;
    return OfflineAssistant(
      search: (q) async {
        final hint = preferredManual(q);
        if (hint.isNotEmpty) {
          try {
            documents ??= ((await rag.info())['documents'] as List).cast<Map>();
            final book = documents!
                .where((d) => (d['file'] as String).contains(hint))
                .firstOrNull;
            if (book != null) {
              final scoped = await rag.search(
                q,
                document: book['id'] as String,
              );
              if (scoped.evidence.isNotEmpty) return scoped;
            }
          } catch (_) {
            /* Keep global retrieval available. */
          }
        }
        return rag.search(q);
      },
      summarize: useLocalModel
          ? (q, evidence) async => runtime.generationTrialAvailable
                ? LocalSummary.summarize(runtime, q, evidence, maxTokens: 128)
                : const GroundedSummary('retrieval_only')
          : null,
    );
  }

  static String preferredManual(String question) {
    final q = question.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(
      r'배선|회로|커넥터|퓨즈|릴레이|접지|ECU|CAN',
      caseSensitive: false,
    ).hasMatch(q)) {
      return '전기배선도';
    }
    if (q.contains('엔진브레이크')) return '엔진';
    final chassis = RegExp(r'브레이크|제동|타이어|조향|현가|서스펜션|액슬').hasMatch(q);
    final engine = RegExp(r'엔진|엔진오일|오일필터|연료필터|에어필터').hasMatch(q);
    if (chassis && !engine) return '새시';
    if (engine && !chassis) return '엔진';
    return '';
  }

  static bool fitsQuestion(String question, String quote) {
    if (RegExp(r'주의|조심|파손|손상|금지').hasMatch(question)) {
      return RegExp(r'주의|조심|파손|손상|금지|위험|않도록|안\s*된|하지\s*말').hasMatch(quote);
    }
    if (RegExp(r'분리|탈거').hasMatch(question)) {
      return RegExp(r'분리|탈거|해제|풀어|푼다').hasMatch(quote);
    }
    return true;
  }

  // Fixed vocabulary/politeness changes only. Keep the complete original beside
  // its citation; no unconstrained paraphrase may add a repair or remove a negation.
  static String plainExplanation(String quote) =>
      LocalSummary.canonical(quote)
          .replaceAll(RegExp(r'바\s+이패스'), '바이패스')
          .replaceAll(RegExp(r'필\s+터'), '필터')
          .replaceAll(RegExp(r'부\s+트'), '부트')
          .replaceAll(RegExp(r'엘리\s+먼트|엘리\s+멘트'), '엘리먼트')
          .replaceAll(RegExp(r'오일\s*필터\s*(엘리먼트|엘리멘트)'), '오일 필터 내부 여과재')
          .replaceAll(RegExp(r'에어\s*클리너\s*(엘리먼트|엘리멘트)'), '에어 필터 내부 여과재')
          .replaceAll(RegExp(r'헤드\s*램프'), '전조등')
          .replaceAll('축전지', '배터리')
          .replaceAll('탈거', '분리')
          .replaceAll('장착', '설치')
          .replaceAll('이탈되어', '빠져')
          .replaceAll('파손될', '망가질')
          .replaceAll('교환시', '교환 시')
          .replaceAll('분리시', '분리 시')
          .replaceAll('점검 및 교환', '점검하고 교환')
          .replaceAll('해야 한다.', '해야 합니다.')
          .replaceAll('한다.', '합니다.')
          .replaceAll('않는다.', '않습니다.')
          .replaceAll('있다.', '있습니다.');

  static const _glossary = {
    '탈거': '부품을 분리하는 것',
    '장착': '부품을 설치하는 것',
    '누유': '오일이 새는 현상',
    '마모': '사용하면서 닳는 것',
    '클램프': '대상을 잡아 고정하는 부품',
    'O-링': '연결 부위를 밀봉하는 고리 모양 부품',
    '고무 부트': '부품을 감싸 먼지 등이 들어가지 않게 하는 고무 덮개',
    '바이패스 밸브': '흐름이 우회할 수 있게 하는 밸브',
  };

  static String _quantity(num value) =>
      NumberFormat.decimalPattern('ko').format(value);

  static String _recordOverview(Maintenance r) {
    final text =
        (r.vehicleId.startsWith('MOCK-')
                ? r.description.replaceFirst(RegExp(r'^목업 기록:\s*'), '')
                : r.description)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    return text.runes.length <= 100
        ? text
        : '${String.fromCharCodes(text.runes.take(100))}…';
  }

  static String _priorityExplanation(
    AppStore store,
    InspectionPriority p,
    String id,
  ) {
    if (p.order == 0) {
      final details = <String>[];
      for (final rule in store.supportLibrary.rules.where(
        (r) => r.vehicleId == id && standardPart(r.part) == p.part,
      )) {
        final state = store.serviceDistance(rule);
        if (state.remainingKm == 0 &&
            state.travelledKm != null &&
            rule.intervalKm != null) {
          details.add(
            '마지막 교환 후 ${_quantity(state.travelledKm!)} km를 사용해, 등록한 ${_quantity(rule.intervalKm!)} km 주기에 도달했습니다.',
          );
        }
        if (state.remainingDays != null && state.remainingDays! <= 0) {
          details.add('등록한 기간 기준의 점검 시점에 도달했습니다.');
        }
      }
      return '${p.part}부터 확인하세요. ${details.isEmpty ? p.reason : details.join(' ')} 마지막 교환 기록과 현재 계기를 먼저 확인해 주세요.';
    }
    if (p.order == 1) {
      final count = store.history(id).where((r) {
        final date = DateTime.tryParse(r.date);
        if (date == null) return false;
        final days = calendarDaysBetween(store.clock(), date);
        return days >= 0 &&
            days < 90 &&
            r.maintenanceType == '고장수리' &&
            standardPart(r.part) == p.part;
      }).length;
      return '${p.part} 수리 원인을 다시 확인하세요. 최근 90일 동안 같은 부품의 고장수리가 $count회 기록되어 있습니다. 이전 수리 내용과 같은 증상이 다시 생겼는지 비교해 주세요.';
    }
    if (p.order == 2) {
      final features = store.predictions[id]?['features'];
      final inputs =
          features is Map &&
              features['distanceKm'] is num &&
              features['monthlyDistanceKm'] is num
          ? ' 계산에 사용한 누적 거리는 ${_quantity(features['distanceKm'] as num)} km이고, 최근 관측 월의 운행 거리는 ${_quantity(features['monthlyDistanceKm'] as num)} km입니다.'
          : '';
      return '차량 전체 상태를 함께 확인하세요. ${p.reason}$inputs 점수만으로 특정 부품의 고장을 확정할 수는 없습니다.';
    }
    return '${p.part}: ${p.reason}';
  }

  static String resolveQuestion(String question, String? previous) {
    final q = question.trim();
    if (previous == null || previous.isEmpty || partsIn(q).isNotEmpty) return q;
    // Carry one bounded topic only for explicit short follow-ups. New questions
    // must not inherit an unrelated component from the preceding turn.
    if (RegExp(
          r'^(그럼\s*)?(그\s*부품[은의을]?\s*|그거[는를]?\s*|그건\s*)?(왜|어떻게|주의할\s*점|주의사항|자세히|좀\s*더)(.*)$',
        ).hasMatch(q) &&
        q.runes.length <= 45) {
      return '${String.fromCharCodes(previous.runes.take(200))} / $q';
    }
    return q;
  }

  Future<OfflineReply> ask(
    AppStore store,
    String vehicleId,
    String question, {
    String? previousQuestion,
  }) async {
    final q = question.trim();
    if (q.isEmpty || q.runes.length > 500) {
      throw ArgumentError('질문을 1~500자로 입력해 주세요.');
    }
    final vehicle = store.vehicles.where((v) => v.id == vehicleId).firstOrNull;
    if (vehicle == null) throw ArgumentError('질문할 차량을 선택해 주세요.');
    final resolved = resolveQuestion(q, previousQuestion);
    final termsToExplain = _glossary.entries
        .where(
          (e) => q
              .replaceAll(RegExp(r'\s+'), '')
              .contains(e.key.replaceAll(' ', '')),
        )
        .toList();
    if (termsToExplain.isNotEmpty &&
        RegExp(r'무슨\s*뜻|뜻이|뜻은|뭐야|뭔가|용어|의미').hasMatch(q)) {
      return OfflineReply(
        question: q,
        searchQuestion: q,
        vehicleId: vehicleId,
        text: termsToExplain
            .take(3)
            .map((e) => '${e.key}: ${e.value}입니다.')
            .join('\n\n'),
      );
    }

    final retrievalQuestion = resolved.replaceAll(
      RegExp(r'주의사항|주의할\s*점|조심할\s*점'),
      '주의',
    );
    final parts = partsIn(resolved);
    final priorityQuestion = RegExp(
      r'무엇부터|뭐부터|어디부터|먼저|우선|순서|분석|점수|위험|차량.*상태|주기|언제.*(해야|하나|할)|잔여|남았',
    ).hasMatch(resolved);
    final historyQuestion = RegExp(r'이력|기록|반복|최근.*수리|정비한|교환한|마지막.*(정비|교환)')
        .hasMatch(resolved);
    final needsBooks =
        !historyQuestion &&
        (!priorityQuestion ||
            RegExp(r'방법|주의|조심|파손|손상|분리|탈거|장착|어떻게|책자|교범|매뉴얼')
                .hasMatch(resolved));
    final domainQuestion =
        parts.isNotEmpty ||
        termsToExplain.isNotEmpty ||
        priorityQuestion ||
        historyQuestion ||
        RegExp(
          r'엔진|오일|필터|브레이크|냉각|시동|소음|진동|누유|누수|과열|제동|충전|경고등|차량|정비|타이어|변속|토크|분리|장착|배선|회로|커넥터|퓨즈|릴레이|접지|와이퍼|통신|전원|도면|ECU|CAN',
        ).hasMatch(resolved);
    if (!domainQuestion) {
      return OfflineReply(
        question: q,
        searchQuestion: resolved,
        vehicleId: vehicleId,
        text: '차량 정비를 도와드릴게요. 어떤 증상이 있거나 어떤 부품을 확인하려는지 알려주세요. 예를 들어 “무엇부터 점검해야 해?” 또는 “브레이크 패드 분리 시 주의사항은?”처럼 물어보시면 됩니다.',
      );
    }
    // Snapshot vehicle facts before awaiting model work; selection is never read
    // again after the async boundary.
    final priorities = priorityQuestion
        ? store
              .inspectionPriorities(vehicleId)
              .where(
                (p) =>
                    parts.isEmpty ||
                    parts.contains(standardPart(p.part)) ||
                    p.part == '점검 기준 확인',
              )
              .toList()
        : <InspectionPriority>[];
    final today = store.clock();
    final terms = maintenanceSearchTerms(resolved);
    final matchingHistory = store.history(vehicleId).where((r) {
      final date = DateTime.tryParse(r.date);
      if (date == null ||
          date.isAfter(DateTime(today.year, today.month, today.day))) {
        return false;
      }
      if (parts.isNotEmpty) {
        return parts.any((p) => matchesPart('${r.part} ${r.description}', p));
      }
      if (historyQuestion || priorityQuestion) return true;
      return terms.any(
        (t) => t.length >= 2 && '${r.part} ${r.description}'.contains(t),
      );
    }).toList()..sort((a, b) => b.date.compareTo(a.date));
    final history = matchingHistory.take(5).toList();
    final priorityDetails = [
      for (final p in priorities) _priorityExplanation(store, p, vehicleId),
    ];
    final notices = <String>[];
    if (priorityQuestion && parts.isNotEmpty && priorities.isEmpty) {
      notices.add(
        '선택 차량에서 해당 부품의 확인된 점검 기준을 찾지 못했습니다. 마지막 교환 기준과 적용 주기를 확인해 주세요.',
      );
    }
    ManualRagResult found;
    try {
      found = needsBooks
          ? await search(retrievalQuestion)
          : const ManualRagResult([], 'not_needed');
    } catch (_) {
      found = const ManualRagResult([], 'unavailable');
    }
    // Corpus currently covers the 2023 Rexton manuals, not every vehicle variant.
    final evidence = vehicle.model.startsWith('렉스턴')
        ? found.evidence.take(5).toList()
        : <MaintenanceEvidence>[];
    if (needsBooks && !vehicle.model.startsWith('렉스턴')) {
      notices.add('현재 책자는 렉스턴 참고 자료입니다. 선택 차량에 맞는 책자를 확인해 주세요.');
    } else if (needsBooks && evidence.isEmpty) {
      notices.add(
        found.mode == 'unavailable'
            ? '기기에 책자 검색 자료가 준비되지 않았습니다. 데이터 관리에서 검색 자료를 확인해 주세요.'
            : '질문에 맞는 책자 근거를 찾지 못했습니다. 부품명과 증상을 더 구체적으로 알려주세요.',
      );
    }
    final answerEvidence = evidence
        .where((e) => e.sourceRef?['textMethod'] != 'ocr')
        .toList();
    var excerpts = <SummaryExcerpt>[];
    if (answerEvidence.length >= 2 && summarize != null) {
      try {
        final summary = await summarize!(retrievalQuestion, answerEvidence);
        // Do not trust even a plugged-in summarizer: independently validate IDs
        // and complete exact source sentences again before showing its output.
        if (summary.mode == 'extractive_summary') {
          final context = LocalSummary.sources(
            LocalSummary.selectEvidence(retrievalQuestion, answerEvidence),
          );
          excerpts = summary.excerpts
              .where(
                (s) => LocalSummary.candidates(context, question: resolved).any(
                  (c) =>
                      c.citation == s.citation &&
                      c.quote == s.quote &&
                      fitsQuestion(resolved, c.quote),
                ),
              )
              .toList();
        }
      } catch (_) {
        notices.add('답변 요약을 완료하지 못했습니다. 아래 책자 원문을 확인해 주세요.');
      }
    }
    // Keep the answer useful even without generation weights or under memory
    // pressure: quote a relevant complete source sentence, never improvise one.
    if (excerpts.isEmpty && answerEvidence.isNotEmpty) {
      excerpts = LocalSummary.candidates(
        LocalSummary.sources(
          LocalSummary.selectEvidence(retrievalQuestion, answerEvidence),
        ),
        question: retrievalQuestion,
      ).where((e) => fitsQuestion(resolved, e.quote)).take(2).toList();
    }
    final seenExplanations = <String>{};
    excerpts = excerpts
        .where(
          (e) => seenExplanations.add(
            plainExplanation(e.quote).replaceAll(RegExp(r'\s+'), ''),
          ),
        )
        .take(2)
        .toList();
    final text = <String>[
      if (priorityDetails.isNotEmpty) ...[
        '먼저 확인할 내용입니다.',
        for (var i = 0; i < priorityDetails.length; i++)
          '${i + 1}. ${priorityDetails[i]}',
      ],
      if (historyQuestion && history.isEmpty)
        '선택 차량에 질문과 관련된 정비 기록이 없습니다. 정비 날짜와 작업 내용을 입력하면 확인할 수 있습니다.',
      if (historyQuestion && history.isNotEmpty) ...[
        '최근 정비 기록부터 정리했습니다. 자세한 내용은 아래 이력에서 확인할 수 있습니다.',
        for (final r in history.take(3))
          '${r.date} · ${r.part}: ${_recordOverview(r)}',
        '이 기록은 이전에 한 작업입니다. 현재 같은 고장이 있다는 뜻은 아닙니다.',
      ],
      if (excerpts.isNotEmpty) '책자에서 찾은 내용입니다.',
      if (evidence.any((e) => e.sourceRef?['textMethod'] == 'ocr')) '관련 배선도 페이지를 찾았습니다. 회로명과 부품 위치는 아래 도면에서 확인해 주세요. 검색용 문자인식에는 오독이 있을 수 있어 핀번호·배선색은 원본 그림에서 확인해야 합니다.',
      if (needsBooks &&
          evidence.isNotEmpty &&
          excerpts.isEmpty &&
          answerEvidence.isNotEmpty)
        '관련 책자는 찾았지만 질문에 바로 답할 수 있는 문장을 확인하지 못했습니다. 확인하려는 부품명과 작업을 조금 더 구체적으로 알려주세요.',
      if (priorities.isEmpty && history.isEmpty && evidence.isEmpty) '지금 정보만으로 원인을 특정하기 어렵습니다. 언제 증상이 생기는지, 어떤 경고등이 켜지는지, 소음이나 진동이 있는지 알려주세요.',
    ].join('\n\n');
    final explanations = excerpts
        .map((e) => plainExplanation(e.quote))
        .toList();
    final wordHelp = <String, String>{
      for (final entry in _glossary.entries)
        if (excerpts.any(
          (e) =>
              e.quote.contains(entry.key) ||
              plainExplanation(e.quote).contains(entry.key),
        ))
          entry.key: entry.value,
    };
    return OfflineReply(
      question: q,
      searchQuestion: resolved,
      vehicleId: vehicleId,
      text: text,
      priorities: priorities,
      history: history,
      evidence: evidence,
      excerpts: excerpts,
      notices: notices,
      explanations: explanations,
      wordHelp: wordHelp,
    );
  }
}
