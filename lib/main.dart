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
import 'ui/field_work.dart';
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

Future<void> _finishOnboarding(
  BuildContext context,
  AppStore store,
  OnboardingAction action,
) async {
  switch (action) {
    case OnboardingAction.examples:
      if (store.presentationVehicles.isEmpty) {
        await store.loadPresentationFleet();
      } else if (!store.dashboardExampleView) {
        await store.setDashboardExampleView(true);
      }
    case OnboardingAction.register:
      if (store.dashboardExampleView) {
        await store.setDashboardExampleView(false);
      }
    case OnboardingAction.home:
      break;
  }
  await store.completeOnboarding();
  if (context.mounted) {
    context.go(switch (action) {
      OnboardingAction.examples => ExampleGuide.location(0, ''),
      OnboardingAction.register => '/setup',
      OnboardingAction.home => '/',
    });
  }
}

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/welcome',
      builder: (context, state) => OnboardingScreen(
        onComplete: (action) => _finishOnboarding(
          context,
          ProviderScope.containerOf(context).read(storeProvider),
          action,
        ),
      ),
    ),
    ShellRoute(
      builder: (context, state, child) => AppShell(
        location: state.uri.path,
        guideStep: ExampleGuide.stepFor(state.uri),
        child: child,
      ),
      routes: [
        GoRoute(
          path: '/field-work',
          builder: (context, state) => const FieldWorkScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(path: '/more', builder: (context, state) => const MoreScreen()),
        GoRoute(
          path: '/vehicles',
          builder: (context, state) => VehiclesScreen(
            key: ValueKey(state.uri.toString()),
            homeScope: state.uri.queryParameters['scope'] == 'home',
          ),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  VehicleDetailScreen(id: state.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: '/inspection-due',
          builder: (context, state) => const DueInspectionsScreen(),
        ),
        GoRoute(
          path: '/analysis',
          builder: (context, state) => const AnalysisScreen(),
        ),
        GoRoute(
          path: '/records',
          builder: (context, state) => RecordsScreen(
            key: ValueKey(state.uri.toString()),
            thisMonth: state.uri.queryParameters['period'] == 'month',
            showCost: state.uri.queryParameters['view'] == 'cost',
            showPriorities: state.uri.queryParameters['view'] != 'history',
          ),
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
          path: '/operations',
          builder: (context, state) =>
              const DataToolsScreen(operationsOnly: true),
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
          builder: (context, state) => const SetupScreen(),
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
      fontFamily: 'Pretendard',
      scaffoldBackgroundColor: surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandFill,
        primary: green,
        primaryContainer: brandTint,
        onPrimaryContainer: green,
        surface: Colors.white,
        onSurface: ink,
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
          backgroundColor: brandFill,
          foregroundColor: ink,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(
            fontFamily: 'Pretendard',
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
  const AppShell({
    required this.location,
    required this.child,
    this.guideStep,
    super.key,
  });

  final int? guideStep;
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
      return OnboardingScreen(
        onComplete: (action) => _finishOnboarding(context, store, action),
      );
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
                    if (wide) SizedBox(width: 180, child: _sidebar()),
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
                                ListenableBuilder(
                                  listenable: appRouter.routerDelegate,
                                  builder: (context, _) {
                                    final route = appRouter
                                        .routerDelegate
                                        .currentConfiguration
                                        .lastOrNull;
                                    final canGoBack =
                                        route is ImperativeRouteMatch;
                                    final parent = switch (widget.location) {
                                      '/' ||
                                      '/front-map' ||
                                      '/records' ||
                                      '/chat' ||
                                      '/more' => null,
                                      '/vision' => '/front-map',
                                      '/entry' || '/operations' => '/records',
                                      '/inspection-due' => '/',
                                      final path
                                          when path.startsWith('/vehicles/') =>
                                        '/vehicles',
                                      final path
                                          when path.startsWith('/records/') =>
                                        '/records',
                                      _ => '/more',
                                    };
                                    if (!canGoBack && parent == null) {
                                      return const SizedBox.shrink();
                                    }
                                    return TextButton.icon(
                                      onPressed: canGoBack
                                          ? () => context.pop()
                                          : () => context.go(parent!),
                                      icon: const Icon(
                                        Icons.arrow_back,
                                        size: 20,
                                      ),
                                      label: const Text('뒤로'),
                                    );
                                  },
                                ),
                                if (!wide)
                                  IconButton(
                                    onPressed: () =>
                                        scaffoldKey.currentState!.openDrawer(),
                                    icon: const Icon(Icons.menu),
                                    tooltip: '메뉴 열기',
                                  ),
                                const Spacer(),
                                if (compact &&
                                    MediaQuery.textScalerOf(context)
                                            .scale(12) <=
                                        18)
                                  Text(
                                    dateTimeLabel(
                                      ref.watch(currentTimeProvider),
                                    ),
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
                                    child: widget.guideStep == null
                                        ? widget.child
                                        : Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              ExampleGuide(
                                                step: widget.guideStep!,
                                                vehicleId:
                                                    store
                                                        .presentationVehicles
                                                        .firstOrNull
                                                        ?.id ??
                                                    '',
                                              ),
                                              const SizedBox(height: 8),
                                              Expanded(child: widget.child),
                                            ],
                                          ),
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
    const items = [
      ('홈', '/', Icons.home_outlined),
      ('사진 점검', '/front-map', Icons.photo_camera_outlined),
      ('기록', '/records', Icons.assignment_outlined),
      ('정비 질문', '/chat', Icons.chat_bubble_outline),
      ('더 보기', '/more', Icons.grid_view_outlined),
    ];
    final selectedPath = switch (widget.location) {
      '/' || '/inspection-due' => '/',
      '/front-map' || '/vision' => '/front-map',
      '/records' || '/entry' || '/operations' => '/records',
      '/chat' => '/chat',
      _ => '/more',
    };
    return Material(
      color: const Color(0xFF171B19),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Column(
                children: [
                  DesignIcon('1:135', 'img', size: 54),
                  SizedBox(height: 9),
                  Text(
                    '00 수송부',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 13),
                  Divider(height: 1, color: Color(0xFF343D37)),
                ],
              ),
            ),
            for (final (label, path, icon) in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  minTileHeight: 52,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  horizontalTitleGap: 8,
                  minLeadingWidth: 22,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  leading: Icon(icon, size: 22),
                  title: Text(label, style: const TextStyle(fontSize: 14)),
                  selected: selectedPath == path,
                  selectedTileColor: const Color(0xFF213A2B),
                  selectedColor: brandAccent,
                  textColor: const Color(0xFFE5EBE7),
                  iconColor: const Color(0xFFB1C0B6),
                  onTap: () {
                    scaffoldKey.currentState?.closeDrawer();
                    context.go(path);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
