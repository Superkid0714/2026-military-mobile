import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/local_summary.dart';
import 'package:military_maintenance/data/adaptive_runtime.dart';
import 'package:military_maintenance/data/store.dart';

void main() {
  test('빠른 원문 요약은 OCR 수치와 정비 주기를 자동 답변하지 않는다', () {
    final e = MaintenanceEvidence(
      id: 'OCR',
      model: '가상차',
      part: '배선',
      symptoms: '',
      title: '가상 도면',
      location: '시험 1쪽',
      text: '가상 와이퍼 모터를 분리한다.',
      sourceRef: {'textMethod': 'ocr'},
    );
    expect(LocalSummary.directExtract('와이퍼 모터 분리', [e]).excerpts, isEmpty);
    expect(
      LocalSummary.directExtract('교체 주기는?', [e]).reason,
      'cycle_values_use_registered_rules',
    );
  });
  test('상위 두 근거 밖에 있는 질문 관련 문장을 선택하고 다른 부품 문장은 제외한다', () {
    MaintenanceEvidence e(String id, String text) => MaintenanceEvidence(
      id: id,
      model: '가상차',
      part: '시험필터',
      symptoms: '',
      title: '가상 원문',
      location: '가상 1쪽',
      text: text,
    );
    final evidence = [
      e('WRONG', '가상펌프 어셈블리를 탈거한다.'),
      e('OTHER', '가상 덮개의 오염을 확인한다.'),
      e('RIGHT', '가상필터를 탈거한다. 부품을 확인한다. 가상필터 분리시 잠금핀이 파손되지 않도록 주의한다.'),
    ];
    const question = '가상필터 분리시 파손에 주의할 부품은?';
    final selected = LocalSummary.selectEvidence(question, evidence);
    expect(selected.first.id, 'RIGHT');
    final context = LocalSummary.sources(selected);
    final allowed = LocalSummary.candidates(context, question: question);
    expect(
      allowed.map((c) => c.quote),
      contains('가상필터 분리시 잠금핀이 파손되지 않도록 주의한다.'),
    );
    expect(allowed.any((c) => c.quote.contains('가상펌프')), isFalse);
    expect(
      LocalSummary.validate(
        jsonEncode({
          'excerpts': [
            {'id': 'WRONG', 'quote': '가상펌프 어셈블리를 탈거한다.'},
          ],
        }),
        context,
        question: question,
      ).mode,
      'retrieval_only',
    );
  });
  test('질문형 어미를 정규화해 위치 설명보다 닦는 방법을 고른다', () {
    final allowed = LocalSummary.candidates({
      'E1': '시험 렌즈는 덮개 아래에 위치한다. 시험 렌즈를 깨끗한 천으로 닦는다.',
      'E2': '다른 부품은 지정된 위치에 보관한다.',
    }, question: '시험 렌즈는 어떻게 닦나요');
    expect(allowed.map((e) => e.quote).toList(), ['시험 렌즈를 깨끗한 천으로 닦는다.']);
  });

  test('긴 질문은 조용히 자르거나 모델을 실행하지 않고 원문으로 전환한다', () async {
    final runtime = AdaptiveRuntime();
    final result = await LocalSummary.summarize(runtime, '가' * 121, const []);
    expect(result.mode, 'retrieval_only');
    expect(result.reason, 'question_exceeds_local_summary_budget');
    runtime.dispose();
  });
  const sources = {
    'E1': '엔진을 정지하고 충분히 냉각한 뒤 작업한다. 오일필터를 분리한다.',
    'E2': '오염물이 들어가지 않도록 막는다.',
  };
  String response(String id, String quote) => jsonEncode({
    'excerpts': [
      {'id': id, 'quote': quote},
    ],
  });
  test('줄바꿈만 정규화한 문장 후보를 만들고 숫자 머리글과 무응답을 처리한다', () {
    final context = {
      'E1': LocalSummary.canonical(
        r'가상 지침 2023.05\r\n필터를 분리한다. 확인 후 안전하게 조립한다.',
      ),
      'E2': '작업 후 누유를 점검한다.',
    };
    final allowed = LocalSummary.candidates(context);
    expect(allowed.map((s) => s.quote), contains('확인 후 안전하게 조립한다.'));
    expect(allowed.any((s) => LocalSummary.numeric.hasMatch(s.quote)), isFalse);
    expect(
      LocalSummary.validate(response('E1', '확인 후 안전하게 조립한다.'), context).mode,
      'extractive_summary',
    );
    expect(
      LocalSummary.validate('{"excerpts":[]}', context).reason,
      'no_supported_excerpt',
    );
  });
  test('출처에 있는 완전한 문장만 인용 요약으로 채택한다', () {
    final r = LocalSummary.validate(response('E1', '오일필터를 분리한다.'), sources);
    expect(r.mode, 'extractive_summary');
    expect(r.excerpts.single.citation, 'E1');
  });
  test('존재하는 인용 ID라도 근거 밖 설명·번역·부분 절은 거부한다', () {
    for (final pair in [
      ('E1', '필터 교환으로 고장이 예방된다.'),
      ('E1', '충분히 냉각한 뒤 작업한다.'),
      ('E3', '오일필터를 분리한다.'),
    ]) {
      expect(
        LocalSummary.validate(response(pair.$1, pair.$2), sources).mode,
        'retrieval_only',
      );
    }
    expect(
      LocalSummary.validate(
        response('E1', '엔진을 정지하고 충분히 냉각한 뒤 작업한다.'),
        sources,
      ).mode,
      'extractive_summary',
    );
  });
  test('출처에 있어도 숫자·교환 기간 수치는 요약에서 채택하지 않는다', () {
    for (final quote in ['매 1000km마다 교환한다.', '매 육 개월마다 교환한다.']) {
      expect(
        LocalSummary.validate(response('E1', quote), {
          'E1': quote,
          'E2': sources['E2']!,
        }).reason,
        'numeric_statement',
      );
    }
    expect(LocalSummary.cycleQuestion.hasMatch('가혹 교환 주기는?'), isTrue);
  });
  test('형식 손상·추가 자유 설명·중복·너무 긴 문장은 원문으로 전환한다', () {
    for (final raw in [
      '요약입니다.',
      '{"excerpts":[]}',
      jsonEncode({
        'excerpts': [
          {'id': 'E1', 'quote': '오일필터를 분리한다.'},
        ],
        'answer': '자유 설명',
      }),
    ]) {
      expect(LocalSummary.validate(raw, sources).mode, 'retrieval_only');
    }
    expect(LocalSummary.excerpt('가' * 400), isEmpty);
  });
}
