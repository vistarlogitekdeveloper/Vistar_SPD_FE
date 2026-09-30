import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spd_frontend/core/api.dart';
import 'package:spd_frontend/core/theme.dart';
import 'package:spd_frontend/data/providers.dart';
import 'package:spd_frontend/data/repository.dart';
import 'package:spd_frontend/models/models.dart';
import 'package:spd_frontend/ui/admin/config_screen.dart';
import 'package:spd_frontend/ui/admin/users_screen.dart';
import 'package:spd_frontend/ui/member/my_history_screen.dart';
import 'package:spd_frontend/ui/member/my_work_screen.dart';
import 'package:spd_frontend/ui/member/pack_screen.dart';
import 'package:spd_frontend/ui/reports/audit_screen.dart';
import 'package:spd_frontend/ui/reports/mis_screen.dart';
import 'package:spd_frontend/ui/supervisor/allocation_screen.dart';
import 'package:spd_frontend/ui/supervisor/dashboard_screen.dart';
import 'package:spd_frontend/ui/supervisor/grn_upload_screen.dart';
import 'package:spd_frontend/ui/supervisor/hourly_screen.dart';
import 'package:spd_frontend/ui/supervisor/labels_screen.dart';
import 'package:spd_frontend/ui/supervisor/lines_screen.dart';
import 'package:spd_frontend/ui/supervisor/review_screen.dart';
import 'package:spd_frontend/ui/widgets/common.dart';

/// The two states `screen_render_test.dart` never reaches.
///
/// That file renders every screen with data, because its fake repository always
/// succeeds. But a screen has three states, and the other two are the ones
/// nobody looks at — the API is up on the machine where the screen was written.
/// A static scan can see that a screen declares a `loading:` and an `error:`
/// branch; only mounting them proves those branches render something rather
/// than throwing, or worse, drawing a blank rectangle with nothing in the
/// console to say why.
///
/// So: every screen, once with a repository that refuses everything, and once
/// with one that never answers.
void main() {
  final screens = <String, Widget Function()>{
    'DashboardScreen': () => const DashboardScreen(),
    'GrnUploadScreen': () => const GrnUploadScreen(),
    'LinesScreen': () => const LinesScreen(),
    'LabelsScreen': () => const LabelsScreen(),
    'AllocationScreen': () => const AllocationScreen(),
    'ReviewScreen': () => const ReviewScreen(),
    'HourlyScreen': () => const HourlyScreen(),
    'MisScreen': () => const MisScreen(),
    'AuditScreen': () => const AuditScreen(),
    'MyWorkScreen': () => const MyWorkScreen(),
    'PackScreen': () => const PackScreen(),
    'MyHistoryScreen': () => const MyHistoryScreen(),
    'UsersScreen': () => const UsersScreen(),
    'ConfigScreen': () => const ConfigScreen(),
  };

  Future<void> mount(WidgetTester tester, Widget screen, SpdRepository repo) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: _container(repo),
      child: MaterialApp(
        theme: buildTheme(light: false),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: screen,
          ),
        ),
      ),
    ));
    // The failure travels shifts -> selectedShift -> scope -> the screen's
    // own provider, a microtask turn each. pumpAndSettle cannot be used to wait
    // it out: SpdLoader breathes on a repeating animation and would time out.
    /* Long enough for every retry timer to have fired. Stopping earlier leaves
       one scheduled, and the test then fails on "A Timer is still pending"
       rather than on anything it was written to check — a failure that looks
       nothing like the assertion it hides. How *quickly* the failure is
       reported is a separate question, measured once below rather than
       fourteen times here. */
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('with the API down', () {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} says so, rather than showing nothing', (tester) async {
        await mount(tester, entry.value(), _DownRepo());

        expect(tester.takeException(), isNull,
            reason: '${entry.key} threw instead of rendering its error state');
        expect(find.byType(ErrorPanel), findsWidgets,
            reason: '${entry.key} renders no ErrorPanel when every call fails — '
                'a supervisor sees a blank panel and nothing to retry');
      });
    }

    testWidgets('the error carries the message the server gave (NFR-4.2)', (tester) async {
      await mount(tester, const DashboardScreen(), _DownRepo());
      expect(find.textContaining('No connection to the SPD server'), findsWidgets);
    });

    testWidgets('the error panel offers a retry', (tester) async {
      await mount(tester, const DashboardScreen(), _DownRepo());
      expect(find.text('Try again'), findsWidgets,
          reason: 'an error with no way out is a dead end');
    });
  });

  group('while the API is slow', () {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} shows a loader, not a blank', (tester) async {
        final repo = _SlowRepo();
        addTearDown(repo.release);

        // Deliberately only one pump: the point is the frame *before* the data
        // arrives, which is the frame a user on a slow link actually sees.
        tester.view.physicalSize = const Size(1440, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: _container(repo),
          child: MaterialApp(
            theme: buildTheme(light: false),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(26),
                child: entry.value(),
              ),
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull,
            reason: '${entry.key} threw while its data was still loading');
        expect(find.byType(SpdLoader), findsWidgets,
            reason: '${entry.key} draws a blank rectangle while loading');
      });
    }
  });

  group('how quickly the failure is reported', () {
    testWidgets('the error panel appears once the retries are spent, not a minute later',
        (tester) async {
      /* The defect this file exists for. Riverpod retries a failed provider ten
         times with a doubling backoff — about thirty-eight seconds — and holds
         the error behind the loader for all of it. Every screen already carries
         an ErrorPanel with a Try again button, built for exactly this moment,
         and none of them could reach it.

         spdRetry spends its budget at 600ms: two attempts, 200ms then 400ms.
         skipLoadingOnReload is what lets the screen show the error it is
         already holding at that point rather than waiting out a further cycle.
         Remove either and this test fails; the fourteen above do not, because
         they pump until everything has settled. */
      tester.view.physicalSize = const Size(1440, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: _container(_DownRepo()),
        child: MaterialApp(
          theme: buildTheme(light: false),
          home: const Scaffold(body: SingleChildScrollView(child: DashboardScreen())),
        ),
      ));

      var shownAt = 0;
      for (var i = 1; i <= 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (shownAt == 0 && find.byType(ErrorPanel).evaluate().isNotEmpty) shownAt = i * 100;
      }

      expect(shownAt, greaterThan(0), reason: 'the error was never shown at all');
      expect(shownAt, lessThanOrEqualTo(800),
          reason: 'the failure took ${shownAt}ms to reach the screen; the retry budget '
              'is spent at 600ms and the supervisor should be told then');
    });
  });
}

/* ---- harness ----------------------------------------------------------- */

/// A container carrying the app's own retry policy. ProviderScope cannot take
/// one, and Riverpod's default holds a failure behind the loader for about
/// thirty-eight seconds — which is both the defect this file was written to
/// catch and, left in place, a test that would have to wait that long to see it.
/// Typed on the repository rather than on a list of overrides, because
/// flutter_riverpod does not export the Override type.
ProviderContainer _container(SpdRepository repo) {
  final c = ProviderContainer(
    overrides: [repositoryProvider.overrideWithValue(repo)],
    retry: spdRetry,
  );
  // Disposing cancels the pending retry timers. Without it the test ends with
  // one still scheduled and fails on "A Timer is still pending", which looks
  // nothing like the assertion it hides.
  addTearDown(c.dispose);
  return c;
}

/* ---- fakes ------------------------------------------------------------- */

/// Refuses everything, the way the client behaves when the API is unreachable.
class _DownRepo extends SpdRepository {
  _DownRepo() : super(ApiClient(baseUrl: 'http://127.0.0.1:1/api'));

  Never _down() => throw ApiException('No connection to the SPD server');

  @override
  Future<List<Shift>> shifts() async => _down();
  @override
  Future<DashboardPage> dashboard(String shiftId) async => _down();
  @override
  Future<LinesPage> lines({required String shiftId, String invoice = '', String vendor = '', String status = '', String q = '', String table = '', String member = ''}) async => _down();
  @override
  Future<List<GrnBatch>> grnBatches({String? shiftId}) async => _down();
  @override
  Future<List<TableStat>> tables(String shiftId) async => _down();
  @override
  Future<List<Allocation>> allocations(String shiftId) async => _down();
  @override
  Future<List<LabelPrint>> labelLog(String shiftId) async => _down();
  @override
  Future<ReviewPage> review(String shiftId) async => _down();
  @override
  Future<HourlyPage> hourly(String shiftId) async => _down();
  @override
  Future<MisPage> mis({required String shiftId, String dim = 'line', String invoice = '', String table = '', String member = ''}) async => _down();
  @override
  Future<AuditPage> audit({String action = '', String q = '', int limit = 300}) async => _down();
  @override
  Future<List<SpdUser>> users() async => _down();
  @override
  Future<SpdConfig> config() async => _down();
  @override
  Future<MemberQueue> myQueue({required String shiftId, String? table, String? member}) async => _down();
  @override
  Future<List<PackingTxn>> myHistory({String? shiftId, String? member}) async => _down();
  @override
  Future<List<Map<String, dynamic>>> notifications(String shiftId) async => _down();
  @override
  Future<Facets> facets(String shiftId) async => _down();
  @override
  Future<LabelPreview> labelPreview(String lineId) async => _down();
}

/// Answers the shift list — so a shift is selected and the data providers
/// actually run — and then never answers anything else.
class _SlowRepo extends SpdRepository {
  _SlowRepo() : super(ApiClient(baseUrl: 'http://127.0.0.1:1/api'));

  final _pending = <Completer<dynamic>>[];

  /// A future that never completes, until the test tears down.
  Future<T> _hang<T>() {
    final c = Completer<T>();
    _pending.add(c);
    return c.future;
  }

  /// Completing the futures on teardown keeps the test runner from reporting
  /// them as pending timers on an otherwise passing test.
  void release() {
    for (final c in _pending) {
      if (!c.isCompleted) c.completeError(ApiException('test torn down'));
    }
    _pending.clear();
  }

  @override
  Future<List<Shift>> shifts() async => [
        Shift(const {
          'id': 'A-2026-09-09', 'label': 'Shift A · 09-Sep-2026',
          'shift_date': '2026-09-09', 'status': 'Open', 'resubmits': 0,
        }),
      ];

  @override
  Future<DashboardPage> dashboard(String shiftId) => _hang();
  @override
  Future<LinesPage> lines({required String shiftId, String invoice = '', String vendor = '', String status = '', String q = '', String table = '', String member = ''}) => _hang();
  @override
  Future<List<GrnBatch>> grnBatches({String? shiftId}) => _hang();
  @override
  Future<List<TableStat>> tables(String shiftId) => _hang();
  @override
  Future<List<Allocation>> allocations(String shiftId) => _hang();
  @override
  Future<List<LabelPrint>> labelLog(String shiftId) => _hang();
  @override
  Future<ReviewPage> review(String shiftId) => _hang();
  @override
  Future<HourlyPage> hourly(String shiftId) => _hang();
  @override
  Future<MisPage> mis({required String shiftId, String dim = 'line', String invoice = '', String table = '', String member = ''}) => _hang();
  @override
  Future<AuditPage> audit({String action = '', String q = '', int limit = 300}) => _hang();
  @override
  Future<List<SpdUser>> users() => _hang();
  @override
  Future<SpdConfig> config() => _hang();
  @override
  Future<MemberQueue> myQueue({required String shiftId, String? table, String? member}) => _hang();
  @override
  Future<List<PackingTxn>> myHistory({String? shiftId, String? member}) => _hang();
  @override
  Future<List<Map<String, dynamic>>> notifications(String shiftId) => _hang();
  @override
  Future<Facets> facets(String shiftId) => _hang();
  @override
  Future<LabelPreview> labelPreview(String lineId) => _hang();
}
