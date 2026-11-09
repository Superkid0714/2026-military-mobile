import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/data/offline_assistant.dart';
import 'package:military_maintenance/data/manual_rag.dart';
import 'package:military_maintenance/data/local_summary.dart';

const assistantSources = [
  MaintenanceEvidence(
    id: 'A',
    model: '렉스턴',
    part: '브레이크패드',
    symptoms: '',
    title: '시험 책자',
    location: 'PDF 7쪽',
    text: '브레이크 패드의 마모 상태를 확인한다. 균열이 있는지 확인한다.',
  ),
  MaintenanceEvidence(
    id: 'B',
    model: '렉스턴',
    part: '브레이크패드',
    symptoms: '',
    title: '시험 책자',
    location: 'PDF 8쪽',
    text: '브레이크 패드를 분리하기 전에 주변을 청소한다.',
  ),
];

AppStore assistantStore() {
  final s = AppStore(clock: () => DateTime(2026, 11, 4));
  s.vehicles = [
    for (final id in ['A', 'B'])
      Vehicle(
        id: id,
        model: '렉스턴 스포츠',
        year: 2020,
        distance: 20000,
        hours: 500,
        fuel: 2000,
        risk: 71,
        predictionReady: true,
      ),
  ];
  s.supportLibrary = const SupportLibrary(
    rules: [
      MaintenanceRule(
        id: 'R',
        vehicleId: 'A',
        part: '엔진오일',
        intervalKm: 10000,
        baselineKm: 10000,
        baselineDate: '2026-01-01',
        source: '시험 기준',
      ),
    ],
  );
  s.records = [
    for (final row in [
      ('A1', 'A', '2026-10-01'),
      ('A2', 'A', '2026-10-20'),
      ('B1', 'B', '2026-10-15'),
      ('FUTURE', 'A', '2026-12-01'),
    ])
      Maintenance(
        id: row.$1,
        vehicleId: row.$2,
        date: row.$3,
        part: '브레이크 패드',
        system: '제동',
        description: '브레이크 패드 소음 점검 및 수리',
        cost: 100,
        maintenanceType: '고장수리',
      ),
  ];
  return s;
}

void main() {
  late AppStore store;
  setUp(() => store = assistantStore());
  tearDown(() => store.dispose());
  OfflineAssistant assistant() => OfflineAssistant(
    search: (_) async => const ManualRagResult(assistantSources, 'hybrid'),
  );

  test('선택 차량의 실제 점검 순서와 과거 이력을 결합하고 다른 차량·미래 이력은 제외한다', () async {
    final r = await assistant().ask(store, 'A', '무엇부터 점검해야 해?');
    expect(r.priorities.map((r) => r.part), ['엔진오일', '브레이크패드', '차량 종합 점검']);
    expect(r.history.map((r) => r.id), ['A2', 'A1']);
    expect(r.evidence, isEmpty);
    expect(r.text, contains('마지막 교환 후 10,000 km'));
    expect(r.text, contains('고장수리가 2회'));
    expect(r.text, contains('\n\n'));
    expect(store.questions, isEmpty);
    expect(store.records, hasLength(4));
  });
  test('부품 질문에는 같은 부품 기록과 확인된 주기만 사용한다', () async {
    final r = await assistant().ask(store, 'A', '브레이크 패드를 먼저 점검할까?');
    expect(r.priorities.map((r) => r.part), ['브레이크패드']);
    expect(r.history, hasLength(2));
  });
  test('직전 부품 후속 질문을 이어가되 새 부품 질문에는 이전 부품을 섞지 않는다', () async {
    final r = await assistant().ask(
      store,
      'A',
      '그럼 주의사항은?',
      previousQuestion: '브레이크 패드 점검',
    );
    expect(r.searchQuestion, contains('브레이크 패드'));
    expect(
      OfflineAssistant.resolveQuestion('엔진오일 교환은?', '브레이크 패드 점검'),
      '엔진오일 교환은?',
    );
  });
  test('정비와 무관한 질문에는 책자 검색이나 차량 정보 표시를 하지 않는다', () async {
    var called = false;
    final a = OfflineAssistant(
      search: (_) async {
        called = true;
        return const ManualRagResult([], 'keyword');
      },
    );
    final r = await a.ask(store, 'A', '점심 메뉴 추천해줘');
    expect(called, false);
    expect(r.history, isEmpty);
    expect(r.priorities, isEmpty);
    expect(r.text, contains('차량 정비'));
  });
  test('검색 실패에도 로컬 점검 순서는 유지하고 추가 정보 안내를 표시한다', () async {
    final a = OfflineAssistant(
      search: (_) async => throw StateError('native unavailable'),
    );
    final r = await a.ask(store, 'A', '브레이크 패드를 먼저 점검할 때 주의사항은?');
    expect(r.priorities.first.part, '브레이크패드');
    expect(r.notices.join(), contains('검색 자료'));
  });
  test('요약 모델 실패는 책자 원문과 출처로 대체한다', () async {
    final a = OfflineAssistant(
      search: (_) async => const ManualRagResult(assistantSources, 'keyword'),
      summarize: (_, _) async => throw StateError('memory pressure'),
    );
    final r = await a.ask(store, 'A', '브레이크 패드 점검');
    expect(r.evidence, hasLength(2));
    expect(r.excerpts, isNotEmpty);
    expect(r.notices.join(), contains('원문'));
  });
  test('잘못된 인용·수치·지어낸 요약은 표시하지 않는다', () async {
    final a = OfflineAssistant(
      search: (_) async => const ManualRagResult(assistantSources, 'hybrid'),
      summarize: (_, _) async => const GroundedSummary(
        'extractive_summary',
        excerpts: [
          SummaryExcerpt('A', '고장 확률은 99%입니다.'),
          SummaryExcerpt('UNKNOWN', '브레이크 패드의 마모 상태를 확인한다.'),
        ],
      ),
    );
    final r = await a.ask(store, 'A', '브레이크 패드 점검');
    expect(
      r.excerpts.any((e) => e.citation == 'UNKNOWN' || e.quote.contains('99%')),
      false,
    );
  });
  test('유효한 원문 문장만 인용 답변에 포함한다', () async {
    final a = OfflineAssistant(
      search: (_) async => const ManualRagResult(assistantSources, 'hybrid'),
      summarize: (_, _) async => const GroundedSummary(
        'extractive_summary',
        excerpts: [SummaryExcerpt('A', '브레이크 패드의 마모 상태를 확인한다.')],
      ),
    );
    final r = await a.ask(store, 'A', '브레이크 패드 마모 점검');
    expect(r.excerpts.single.citation, 'A');
  });
  test('지원하지 않는 차종에는 렉스턴 책자를 적용한 답변을 만들지 않는다', () async {
    store.vehicles = [
      const Vehicle(
        id: 'OTHER',
        model: '다른 차종',
        year: 2020,
        distance: 100,
        hours: 10,
        fuel: 10,
        risk: 0,
      ),
    ];
    final r = await assistant().ask(store, 'OTHER', '브레이크 패드 점검');
    expect(r.evidence, isEmpty);
    expect(r.notices.join(), contains('선택 차량에 맞는 책자'));
  });
  test('정비 이력 질문에는 날짜와 작업을 직접 설명하고 책자는 검색하지 않는다', () async {
    var searches = 0;
    final a = OfflineAssistant(
      search: (_) async {
        searches++;
        return const ManualRagResult([], 'keyword');
      },
    );
    final r = await a.ask(store, 'A', '최근 정비 이력을 알려줘');
    expect(searches, 0);
    expect(r.text, contains('2026-10-20'));
    expect(r.text, contains('브레이크 패드 소음 점검 및 수리'));
    expect(
      r.text.indexOf('2026-10-20'),
      lessThan(r.text.indexOf('2026-10-01')),
    );
    expect(r.notices, isEmpty);
  });
  test('주의사항 질문에 단순 현상 설명을 주의 답변으로 사용하지 않는다', () async {
    const sources = [
      MaintenanceEvidence(
        id: 'DEF',
        model: '렉스턴',
        part: '',
        symptoms: '',
        title: '시험 책자',
        location: 'PDF 1쪽',
        text: '브레이크 제동이 계속된다는 것은 제동 장치가 작동한다는 의미이다.',
      ),
    ];
    final a = OfflineAssistant(
      search: (_) async => const ManualRagResult(sources, 'keyword'),
    );
    final r = await a.ask(store, 'A', '브레이크 점검 주의사항은?');
    expect(r.excerpts, isEmpty);
    expect(r.priorities, isEmpty);
    expect(r.text, contains('구체적으로'));
    expect(r.text, isNot(contains('원인을 특정')));
  });
  test('주의 문장은 쉬운 말과 원문을 함께 보관하며 금지·부정 의미를 보존한다', () async {
    const quote = '브레이크 패드를 탈거할 때 호스가 손상되지 않도록 주의한다.';
    const sources = [
      MaintenanceEvidence(
        id: 'WARN',
        model: '렉스턴',
        part: '브레이크패드',
        symptoms: '',
        title: '시험 책자',
        location: 'PDF 2쪽',
        text: quote,
      ),
    ];
    final a = OfflineAssistant(
      search: (_) async => const ManualRagResult(sources, 'keyword'),
    );
    final r = await a.ask(store, 'A', '브레이크 패드 분리 시 주의사항은?');
    expect(r.excerpts.single.quote, quote);
    expect(r.explanations.single, '브레이크 패드를 분리할 때 호스가 손상되지 않도록 주의합니다.');
    expect(r.wordHelp['탈거'], '부품을 분리하는 것');
    expect(
      OfflineAssistant.plainExplanation('분리한 부품을 다시 장착하지 않는다.'),
      '분리한 부품을 다시 설치하지 않습니다.',
    );
  });
  test('제동 질문은 새시 책자를 우선하고 엔진 브레이크와 복합 질문은 구분한다', () {
    expect(OfflineAssistant.preferredManual('브레이크 패드 점검 주의사항'), '새시');
    expect(OfflineAssistant.preferredManual('엔진 브레이크 작동'), '엔진');
    expect(OfflineAssistant.preferredManual('오일 필터 분리'), '엔진');
    expect(OfflineAssistant.preferredManual('엔진과 브레이크를 함께 점검'), '');
  });
  test('주의사항 표현을 검색어로 정리해 주의 문장을 찾는다', () async {
    String? query;
    final a = OfflineAssistant(
      search: (q) async {
        query = q;
        return const ManualRagResult([], 'keyword');
      },
    );
    final r = await a.ask(store, 'A', '브레이크 패드 점검 주의사항은?');
    expect(query, contains('주의'));
    expect(query, isNot(contains('주의사항')));
    expect(r.searchQuestion, '브레이크 패드 점검 주의사항은?');
  });
  test('모델 설명의 운용 수치는 실제 저장된 분석 입력값에서만 가져온다', () async {
    store.predictions['A'] = {
      'features': {'distanceKm': 20000, 'monthlyDistanceKm': 1500},
    };
    final r = await assistant().ask(store, 'A', '점수를 설명해줘');
    expect(r.text, contains('누적 거리는 20,000 km'));
    expect(r.text, contains('관측 월의 운행 거리는 1,500 km'));
    expect(r.text, contains('특정 부품의 고장을 확정'));
  });
  test('같은 주의 문장이 여러 출처에 있어도 쉬운 설명에는 한 번만 표시한다', () async {
    const text = '브레이크 피스톤의 고무 부 트가 손상되지 않도록 주의한다.';
    const sources = [
      MaintenanceEvidence(
        id: 'D1',
        model: '렉스턴',
        part: '',
        symptoms: '',
        title: '시험 자료',
        location: '1쪽',
        text: text,
      ),
      MaintenanceEvidence(
        id: 'D2',
        model: '렉스턴',
        part: '',
        symptoms: '',
        title: '시험 자료',
        location: '2쪽',
        text: text,
      ),
    ];
    final a = OfflineAssistant(
      search: (_) async => const ManualRagResult(sources, 'keyword'),
    );
    final r = await a.ask(store, 'A', '브레이크 점검 주의사항');
    expect(r.excerpts, hasLength(1));
    expect(r.explanations.single, contains('고무 부트'));
    expect(r.wordHelp['고무 부트'], contains('고무 덮개'));
    expect(r.excerpts.single.quote, text);
  });
  test('용어 뜻은 책자 검색 없이 바로 설명하며 PDF 단어 분리는 표시에서만 정리한다', () async {
    final a = OfflineAssistant(
      search: (_) async => throw StateError('must not search'),
    );
    final r = await a.ask(store, 'A', '탈거가 무슨 뜻이야?');
    expect(r.text, '탈거: 부품을 분리하는 것입니다.');
    expect(r.evidence, isEmpty);
    expect(
      OfflineAssistant.plainExplanation('오일 필 터의 바 이패스 밸브를 탈거한다.'),
      '오일 필터의 바이패스 밸브를 분리합니다.',
    );
  });
  test('대상 차량·입력 길이 오류는 보류한다', () async {
    expect(() => assistant().ask(store, 'UNKNOWN', '점검'), throwsArgumentError);
    expect(() => assistant().ask(store, 'A', ''), throwsArgumentError);
    expect(() => assistant().ask(store, 'A', '가' * 501), throwsArgumentError);
  });
}
