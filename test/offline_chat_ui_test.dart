import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:military_maintenance/data/store.dart';
import 'package:military_maintenance/data/manual_rag.dart';
import 'package:military_maintenance/data/offline_assistant.dart';
import 'package:military_maintenance/ui/chat.dart';
import 'package:military_maintenance/ui/components.dart';

import 'analysis_visualization_test.dart' show prepare;
import 'data_tools_test.dart' show tapWithIo;
import 'offline_assistant_test.dart' show assistantSources;

Future<AppStore> mountChat(
  WidgetTester tester,
  OfflineAssistant assistant, {
  bool compact = false,
}) async {
  final store = await prepare(tester);
  if (compact) tester.view.physicalSize = const Size(600, 800);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeProvider.overrideWith((ref) => store),
        offlineAssistantProvider.overrideWithValue(assistant),
      ],
      child: MaterialApp(
        theme: ThemeData(
          fontFamily: 'Pretendard',
          colorScheme: ColorScheme.fromSeed(seedColor: green),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(compact ? 1.6 : 1)),
          child: child!,
        ),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: ChatScreen(vehicleId: 'MOCK-RX-0001'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  OfflineAssistant assistant() => OfflineAssistant(
    search: (_) async => const ManualRagResult(assistantSources, 'keyword'),
  );

  testWidgets('음성으로 받은 문장을 입력칸에 두고 사용자가 전송할 수 있다', (tester) async {
    const channel = MethodChannel('maintenance/offline_speech');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'listen');
      return '브레이크 상태를 어떻게 확인해?';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final store = await mountChat(tester, assistant());
    await tester.tap(find.byTooltip('음성 입력'));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('assistant-question')),
    );
    expect(input.controller!.text, '브레이크 상태를 어떻게 확인해?');
    expect(store.questions, isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('assistant-send')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('질문을 보내면 로컬 점검 답변과 선택 차량 질문 이력을 저장한다', (tester) async {
    final store = await mountChat(tester, assistant());
    final button = find.byKey(const ValueKey('assistant-send'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('assistant-question')),
      '무엇부터 점검해야 해?',
    );
    await tester.pump();
    await tapWithIo(
      tester,
      button,
      completed: () =>
          store.questions.any((q) => q['question'] == '무엇부터 점검해야 해?'),
    );
    expect(find.text('점검 순서와 이유'), findsOneWidget);
    expect(store.questions.first['vehicleId'], 'MOCK-RX-0001');
    expect(tester.takeException(), isNull);
  });
  testWidgets('책자 출처를 열면 인용한 원문을 확인할 수 있다', (tester) async {
    final store = await mountChat(tester, assistant());
    await tester.enterText(
      find.byKey(const ValueKey('assistant-question')),
      '브레이크 패드 마모 점검',
    );
    await tester.pump();
    await tapWithIo(
      tester,
      find.byKey(const ValueKey('assistant-send')),
      completed: () => store.questions.isNotEmpty,
    );
    final source = find.text('출처: PDF 7쪽');
    await tester.scrollUntilVisible(
      source,
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(source);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('책자에서 가져온 글 보기'));
    await tester.pumpAndSettle();
    expect(find.text(assistantSources.first.text), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('진행 중에는 차량 변경과 중복 전송을 막고 완료 후 전환하면 대화를 비운다', (tester) async {
    final wait = Completer<ManualRagResult>();
    final store = await mountChat(
      tester,
      OfflineAssistant(search: (_) => wait.future),
    );
    await tester.enterText(
      find.byKey(const ValueKey('assistant-question')),
      '브레이크 점검',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('assistant-send')))
          .onPressed,
      isNull,
    );
    final dropdown = find.byType(DropdownButtonFormField<String>);
    expect(
      tester.widget<DropdownButtonFormField<String>>(dropdown).onChanged,
      isNull,
    );
    wait.complete(const ManualRagResult([], 'keyword'));
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && store.questions.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    tester.widget<DropdownButtonFormField<String>>(dropdown).onChanged!(
      'MOCK-RX-0002',
    );
    await tester.pumpAndSettle();
    expect(find.text('추천 질문'), findsOneWidget);
    expect(store.questions.first['vehicleId'], 'MOCK-RX-0001');
    expect(tester.takeException(), isNull);
  });
  testWidgets('600×800 큰 글자에서 오프라인 안내와 입력·전송을 사용할 수 있다', (tester) async {
    final store = await mountChat(tester, assistant(), compact: true);
    await tester.enterText(
      find.byKey(const ValueKey('assistant-question')),
      '무엇부터 점검해?',
    );
    await tester.pump();
    await tapWithIo(
      tester,
      find.byKey(const ValueKey('assistant-send')),
      completed: () => store.questions.isNotEmpty,
    );
    expect(find.byKey(const ValueKey('assistant-question')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
