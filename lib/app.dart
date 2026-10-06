import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/telemetry.dart';
import 'core/theme.dart';
import 'data/providers.dart';
import 'ui/admin/config_screen.dart';
import 'ui/admin/users_screen.dart';
import 'ui/login_screen.dart';
import 'ui/member/my_history_screen.dart';
import 'ui/member/my_work_screen.dart';
import 'ui/member/pack_screen.dart';
import 'ui/reports/audit_screen.dart';
import 'ui/reports/mis_screen.dart';
import 'ui/shell.dart';
import 'ui/splash_screen.dart';
import 'ui/supervisor/allocation_screen.dart';
import 'ui/supervisor/dashboard_screen.dart';
import 'ui/supervisor/grn_upload_screen.dart';
import 'ui/supervisor/hourly_screen.dart';
import 'ui/supervisor/labels_screen.dart';
import 'ui/supervisor/lines_screen.dart';
import 'ui/supervisor/review_screen.dart';

/// The nav entry a role lands on, matching the prototype's `NAV[role][0]`.
String homeFor(String roleKey) => switch (roleKey) {
      'member' => '/my/work',
      'admin' => '/admin/users',
      _ => '/dashboard',
    };

/// FR-13.3 — screens each role may not reach. The server enforces the same
/// boundary; this only keeps a role from navigating somewhere it would be
/// refused, so the refusal never has to be explained twice.
const _blocked = <String, List<String>>{
  'member': ['/dashboard', '/grn', '/lines', '/labels', '/allocation', '/review', '/hourly', '/mis', '/audit', '/admin'],
  'viewer': ['/grn', '/lines', '/labels', '/allocation', '/review', '/hourly', '/audit', '/admin', '/my'],
  // A Supervisor has no member screens of their own — the API refuses a
  // Start/Submit from them, so the console must not offer the route either.
  'supervisor': ['/admin/users', '/admin/config', '/my'],
  // An Administrator reaches everything, including the operational screens, so
  // the "View as" preview in the top bar can walk those layouts.
  'admin': <String>[],
};

class SpdApp extends ConsumerStatefulWidget {
  const SpdApp({super.key});

  @override
  ConsumerState<SpdApp> createState() => _SpdAppState();
}

class _SpdAppState extends ConsumerState<SpdApp> {
  late final GoRouter _router;
  final _authChanged = _Bumper();

  @override
  void initState() {
    super.initState();

    // listenManual, not ref.listen: this subscription lives for the router's
    // lifetime rather than one build pass.
    ref.listenManual(sessionProvider, (prev, next) {
      if (prev?.signedIn != next.signedIn) _authChanged.bump();
    });
    ref.listenManual(viewRoleProvider, (prev, next) {
      if (prev != next) _authChanged.bump();
    });

    _router = _withScreenViews(GoRouter(
      initialLocation: '/splash',
      refreshListenable: _authChanged,
      redirect: (context, state) {
        final loc = state.matchedLocation;
        if (loc == '/splash') return null;

        final session = ref.read(sessionProvider);
        final goingToLogin = loc == '/login';
        if (!session.signedIn) return goingToLogin ? null : '/login';

        final role = ref.read(viewRoleProvider);
        if (goingToLogin) return homeFor(role);

        final blocked = _blocked[role] ?? const <String>[];
        if (blocked.any((b) => loc == b || loc.startsWith('$b/'))) return homeFor(role);
        return null;
      },
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        ShellRoute(
          builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
          routes: [
            GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
            GoRoute(path: '/grn', builder: (_, _) => const GrnUploadScreen()),
            GoRoute(path: '/lines', builder: (_, _) => const LinesScreen()),
            GoRoute(path: '/labels', builder: (_, _) => const LabelsScreen()),
            GoRoute(path: '/allocation', builder: (_, _) => const AllocationScreen()),
            GoRoute(path: '/review', builder: (_, _) => const ReviewScreen()),
            GoRoute(path: '/hourly', builder: (_, _) => const HourlyScreen()),
            GoRoute(path: '/mis', builder: (_, _) => const MisScreen()),
            GoRoute(path: '/audit', builder: (_, _) => const AuditScreen()),
            GoRoute(path: '/my/work', builder: (_, _) => const MyWorkScreen()),
            GoRoute(path: '/my/pack', builder: (_, _) => const PackScreen()),
            GoRoute(path: '/my/history', builder: (_, _) => const MyHistoryScreen()),
            GoRoute(path: '/admin/users', builder: (_, _) => const UsersScreen()),
            GoRoute(path: '/admin/config', builder: (_, _) => const ConfigScreen()),
          ],
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sessionProvider);
    // buildTheme() also sets Brand.isLight, and runs before the subtree below
    // rebuilds, so every screen reads the palette for the mode being applied.
    final light = ref.watch(themeLightProvider);
    return MaterialApp.router(
      title: 'Vistar SPD · Pre-Packing Automation',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(light: light),
      routerConfig: _router,
      // Brand tokens are read as plain values rather than through
      // Theme.of(context), so a screen that never touches the inherited theme
      // would keep painting the old palette. Re-keying the subtree on the mode
      // forces every screen to rebuild against the palette now in effect.
      builder: (context, child) => KeyedSubtree(
        key: ValueKey(light),
        child: AmbientBackground(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// Reports each screen the router shows to usage analytics (by route
/// pattern; see Telemetry.screen). The router lives as long as the app.
GoRouter _withScreenViews(GoRouter router) {
  if (!Telemetry.enabled) return router;
  // The delegate, not the route-information provider: it also hears the
  // location changes a redirect makes (sign-in landing on the role's home).
  void report() {
    try {
      Telemetry.screen(router.routerDelegate.currentConfiguration.uri.toString());
    } catch (_) {
      // No configuration yet; the next change reports.
    }
  }

  router.routerDelegate.addListener(report);
  // The listener only hears changes: report the starting screen too.
  WidgetsBinding.instance.addPostFrameCallback((_) => report());
  return router;
}

/// Bridges Riverpod state into GoRouter's refresh mechanism.
class _Bumper extends ChangeNotifier {
  void bump() => notifyListeners();
}
