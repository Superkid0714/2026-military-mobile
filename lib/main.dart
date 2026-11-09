import 'ui/onboarding.dart';
import 'ui/maintenance_loading.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/store.dart';
import 'data/clock.dart';
import 'data/adaptive_runtime.dart';
import 'ui/components.dart';
import 'ui/management.dart';
import 'ui/workflow_home.dart';
import 'ui/entry.dart';
import 'ui/vision.dart';
import 'data/front_inspection.dart';
import 'ui/front_inspection.dart';
import 'ui/support.dart';
import 'ui/data_tools.dart';
import 'ui/manual_search.dart';
import 'ui/chat.dart';
import 'ui/setup.dart';
import 'rag_device_probe.dart';
import 'optional_model_device_probe.dart';
import 'vision_device_probe.dart';
import 'flow_device_probe.dart';
import 'system_pilot_device_probe.dart';
import 'rag_utility_device_probe.dart';
import 'memory_warning_device_probe.dart';
import 'ml_device_probe.dart';
import 'pdf_reference_device_probe.dart';
import 'manual_rag_device_probe.dart';
import 'offline_chat_device_probe.dart';

@pragma('vm:entry-point')
void offlineChatDeviceProbe() {
  runOfflineChatDeviceProbe();
}

@pragma('vm:entry-point')
void manualRagDeviceProbe() {
  runManualRagDeviceProbe();
}

@pragma('vm:entry-point')
void pdfReferenceDeviceProbe() {
  runPdfReferenceDeviceProbe();
}

@pragma('vm:entry-point')
void mlDeviceProbe() {
  runMlDeviceProbe();
}

@pragma('vm:entry-point')
void memoryWarningDeviceProbe() {
  runMemoryWarningDeviceProbe();
}

@pragma('vm:entry-point')
void ragUtilityDeviceProbe() {
  runRagUtilityDeviceProbe();
}

@pragma('vm:entry-point')
void systemPilotDeviceProbe() {
  runSystemPilotDeviceProbe();
}

@pragma('vm:entry-point')
void flowDeviceProbe() {
  runFlowDeviceProbe();
}

@pragma('vm:entry-point')
void visionDeviceProbe() {
  runVisionDeviceProbe();
}

@pragma('vm:entry-point')
void optionalModelDeviceProbe() {
  runOptionalModelDeviceProbe();
}

@pragma('vm:entry-point')
void ragDeviceProbe() {
  runRagDeviceProbe();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MilitaryApp()));
}

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/welcome',
      builder: (context, state) => OnboardingScreen(
        onComplete: () async {
          await ProviderScope.containerOf(context)
              .read(storeProvider)
              .completeOnboarding();
          if (context.mounted) context.go('/');
        },
      ),
    ),
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/vehicles',
          builder: (context, state) => const VehiclesScreen(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  VehicleDetailScreen(id: state.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: '/analysis',
          builder: (context, state) => const AnalysisScreen(),
        ),
        GoRoute(
          path: '/records',
          builder: (context, state) => const RecordsScreen(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  RecordDetailScreen(id: state.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: '/entry',
          builder: (context, state) {
            final recordId = state.uri.queryParameters['record'];
            final inspectionId = state.uri.queryParameters['inspection'];
            if (inspectionId != null &&
                !ProviderScope.containerOf(context)
                    .read(storeProvider)
                    .inspections
                    .any((i) => i.id == inspectionId)) {
              return empty('점검 기록을 찾을 수 없습니다. 차량 점검 기록에서 다시 선택해 주세요.');
            }
            if (recordId != null &&
                !ProviderScope.containerOf(context)
                    .read(storeProvider)
                    .records
                    .any((r) => r.id == recordId)) {
              return empty('정비 기록을 찾을 수 없습니다.');
            }
            return EntryScreen(
              key: ValueKey(state.uri.toString()),
              vehicleId: state.uri.queryParameters['vehicle'],
              recordId: state.uri.queryParameters['record'],
              inspectionId: state.uri.queryParameters['inspection'],
              initialPart: state.uri.queryParameters['part'],
              initialMaintenance:
                  state.uri.queryParameters['type'] != 'operation',
            );
          },
        ),
        GoRoute(
          path: '/data-tools',
          builder: (context, state) => const DataToolsScreen(),
        ),
        GoRoute(
          path: '/ai-history',
          builder: (context, state) => AiHistoryScreen(
            key: ValueKey(state.uri.toString()),
            vehicleId: state.uri.queryParameters['vehicle'],
          ),
        ),
        GoRoute(
          path: '/setup',
          builder: (context, state) => SetupScreen(
            key: ValueKey(state.uri.toString()),
            vehicleId: state.uri.queryParameters['vehicle'],
          ),
        ),
        GoRoute(
          path: '/support',
          builder: (context, state) => SupportScreen(
            key: ValueKey(state.uri.toString()),
            vehicleId: state.uri.queryParameters['vehicle'],
            part: state.uri.queryParameters['part'],
            inspectionId: state.uri.queryParameters['inspection'],
          ),
        ),
        GoRoute(
          path: '/manual-search',
          builder: (context, state) => ManualSearchScreen(
            key: ValueKey(state.uri.toString()),
            initialQuery: state.uri.queryParameters['query'] ?? '',
          ),
        ),
        GoRoute(
          path: '/plans',
          builder: (context, state) => MaintenancePlanScreen(
            key: ValueKey(state.uri.toString()),
            vehicleId: state.uri.queryParameters['vehicle'],
          ),
        ),
        GoRoute(
          path: '/front-map',
          builder: (context, state) => FrontMapScreen(
            key: ValueKey(state.uri.toString()),
            vehicleId: state.uri.queryParameters['vehicle'],
            initialArea: state.uri.queryParameters['area'] == 'engineBay'
                ? FrontInspectionArea.engineBay
                : FrontInspectionArea.exterior,
          ),
        ),
        GoRoute(
          path: '/vision',
          builder: (context, state) => VisionScreen(
            key: ValueKey(state.uri.toString()),
            vehicleId: state.uri.queryParameters['vehicle'],
            sessionId: state.uri.queryParameters['session'],
            inspectionArea: state.uri.queryParameters['front'] != '1'
                ? null
                : state.uri.queryParameters['area'] == 'engineBay'
                ? FrontInspectionArea.engineBay
                : FrontInspectionArea.exterior,
            part: state.uri.queryParameters['part'],
          ),
        ),
        GoRoute(
          path: '/chat',
          builder: (context, state) => ChatScreen(
            key: ValueKey(state.uri.toString()),
            vehicleId: state.uri.queryParameters['vehicle'],
          ),
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => context.go('/'),
        child: const Text('종합 현황으로 돌아가기'),
      ),
    ),
  ),
);

class MilitaryApp extends StatelessWidget {
  const MilitaryApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: '정비온',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansKR',
      scaffoldBackgroundColor: surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
        primary: green,
        surface: Colors.white,
      ),
      dividerColor: line,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(
            fontFamily: 'NotoSansKR',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: muted,
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    ),
    routerConfig: appRouter,
  );
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.location, required this.child, super.key});
  final String location;
  final Widget child;
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.read(adaptiveRuntimeProvider).initialize();
      final store = ref.read(storeProvider);
      if (!store.ready) store.initialize(populatePresentation: true);
    });
  }

  @override
  void didHaveMemoryPressure() {
    ref.read(adaptiveRuntimeProvider).memoryPressure();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      assert(() {
        debugPrint(
          'MaintenanceUiPressure event=lifecycle_paused action=queued_release',
        );
        return true;
      }());
      ref.read(adaptiveRuntimeProvider).manager.release();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  final scaffoldKey = GlobalKey<ScaffoldState>();
  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final runtime = ref.watch(adaptiveRuntimeProvider);
    if (store.ready && !store.onboardingCompleted) {
      return OnboardingScreen(onComplete: store.completeOnboarding);
    }
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 1000, compact = c.maxWidth >= 700;
        return Scaffold(
          key: scaffoldKey,
          drawer: wide ? null : Drawer(width: 230, child: _sidebar()),
          body: Stack(
            children: [
              SafeArea(
                child: Row(
                  children: [
                    if (wide) SizedBox(width: 216, child: _sidebar()),
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            constraints: const BoxConstraints(minHeight: 64),
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 28 : 12,
                              vertical: 8,
                            ),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(bottom: BorderSide(color: line)),
                            ),
                            child: Row(
                              children: [
                                if (!wide)
                                  IconButton(
                                    onPressed: () =>
                                        scaffoldKey.currentState!.openDrawer(),
                                    icon: const Icon(Icons.menu),
                                    tooltip: '메뉴 열기',
                                  ),
                                const Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '정비온',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      SizedBox(height: 5),
                                      SizedBox(
                                        width: 52,
                                        child: Divider(
                                          color: green,
                                          thickness: 2,
                                          height: 2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (compact &&
                                    MediaQuery.textScalerOf(context).scale(12) <= 18)
                                  Text(
                                    day(ref.watch(currentTimeProvider)),
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: !store.ready
                                ? Center(
                                    child: store.error == null
                                        ? const MaintenanceLoading(
                                            detail: '차량 기록과 정비 정보를 준비하고 있어요.',
                                            immediate: true,
                                          )
                                        : Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(store.error!),
                                              TextButton(
                                                onPressed: () =>
                                                    store.initialize(
                                                      populatePresentation:
                                                          true,
                                                    ),
                                                child: const Text('다시 시도'),
                                              ),
                                            ],
                                          ),
                                  )
                                : Padding(
                                    padding: EdgeInsets.all(compact ? 24 : 14),
                                    child: widget.child,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (runtime.installingMessage != null) ...[
                const Positioned.fill(
                  child: ModalBarrier(
                    dismissible: false,
                    color: Color(0xF5FFFFFF),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: MaintenanceLoading(
                        detail: runtime.installingMessage!,
                        immediate: true,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sidebar() {
    final items = [
      ('종합 현황', '/', '바로 하기'),
      ('사진 점검', '/vision', '바로 하기'),
      ('기록 입력', '/entry', '바로 하기'),
      ('정비 질문', '/chat', '바로 하기'),
      ('차량 목록', '/vehicles', '차량과 기록'),
      ('정비 기록', '/records', '차량과 기록'),
      ('연간 정비계획', '/plans', '차량과 기록'),
      ('정비 분석', '/analysis', '차량과 기록'),
      ('지난 분석 결과', '/ai-history', '차량과 기록'),
      ('부품별 정비', '/support', '도구와 설정'),
      if (ref.watch(adaptiveRuntimeProvider).modelInfo['corpusDatabasePath']
          is String)
        ('책자 검색', '/manual-search', '도구와 설정'),
      ('차량 등록·설정', '/setup', '도구와 설정'),
      ('백업·자료 가져오기', '/data-tools', '도구와 설정'),
    ];
    return Container(
      color: ink,
      child: Column(
        children: [
          const SizedBox(height: 16),
          const DesignIcon('1:135', 'img', size: 48),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '정비참모부 관리단',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i == 0 || items[i].$3 != items[i - 1].$3)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 18, 8, 10),
                      child: Text(
                        items[i].$3,
                        style: const TextStyle(
                          color: Color(0xFF8B95A1),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  _navigationItem(items[i].$1, items[i].$2),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              '정비온 v${ref.watch(adaptiveRuntimeProvider).modelInfo['appVersion'] ?? '0.9.0'}',
              style: const TextStyle(color: Color(0xFF8B95A1), fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navigationItem(String label, String path) {
    final location = widget.location;
    final selected = path == '/'
        ? location == '/'
        : location.startsWith(path) || (path == '/vision' && location == '/front-map');
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? green : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (scaffoldKey.currentState?.isDrawerOpen ?? false) {
              Navigator.pop(context);
            }
            context.go(path);
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 20,
                  color: selected ? Colors.white : Colors.transparent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFB6C0C2),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
