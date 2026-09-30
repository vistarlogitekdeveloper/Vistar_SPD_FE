import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../models/models.dart';
import 'repository.dart';

/// Overridden in `main()` with the instance loaded before the first frame, so
/// anything that has to be known *at* first paint — the theme — can be read
/// synchronously rather than flashing a default and correcting itself.
///
/// Nullable on purpose. Local storage can be unavailable: a private window, a
/// locked profile, a platform whose plugin did not register. Remembering a
/// theme is a convenience, and a console that shows a white screen on a table
/// tablet because it could not read one would be a poor trade.
final sharedPrefsProvider = Provider<SharedPreferences?>((ref) => null);

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
final repositoryProvider = Provider<SpdRepository>((ref) => SpdRepository(ref.watch(apiClientProvider)));

/* ------------------------------------------------------- UI value state --- */

/// A plain mutable value in the provider graph — the selected shift, the filter
/// on a screen, the light/dark flag.
///
/// Riverpod 3 retired `StateProvider`, and a `Notifier`'s own `state` is
/// `@protected`, so this exposes [set] and [update] as the supported way to
/// write one from a widget.
class UiValue<T> extends Notifier<T> {
  UiValue(this._initial);

  final T _initial;

  @override
  T build() => _initial;

  void set(T value) => state = value;

  void update(T Function(T current) fn) => state = fn(state);
}

NotifierProvider<UiValue<T>, T> uiValue<T>(T initial) =>
    NotifierProvider<UiValue<T>, T>(() => UiValue<T>(initial));

/* ------------------------------------------------------------- session --- */

class Session {
  const Session({this.user, this.token, this.loading = false, this.error});

  final SpdUser? user;
  final String? token;
  final bool loading;
  final String? error;

  bool get signedIn => user != null && token != null;

  Session copyWith({SpdUser? user, String? token, bool? loading, String? error, bool clearError = false}) =>
      Session(
        user: user ?? this.user,
        token: token ?? this.token,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class SessionNotifier extends Notifier<Session> {
  @override
  Session build() => const Session();

  Future<bool> signIn({required String userId, String? password, String? pin}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(repositoryProvider);
      final res = await repo.login(userId: userId, password: password, pin: pin);
      ref.read(apiClientProvider).setToken(res.token);
      state = Session(user: res.user, token: res.token);
      return true;
    } on ApiException catch (e) {
      state = Session(error: e.message);
      return false;
    }
  }

  Future<void> signOut() async {
    await ref.read(repositoryProvider).logout();
    ref.read(apiClientProvider).setToken(null);
    state = const Session();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session>(SessionNotifier.new);

/// The role the shell is *drawing*. Starts as the signed-in user's own role and
/// is changed by the top bar's "View as" picker. It never changes what the
/// server will accept — only what the console shows.
final viewRoleProvider = uiValue<String>('supervisor');

/// Light / dark, as in the prototype's theme toggle — but remembered.
///
/// A supervisor who works in a bright stores office should not have to re-pick
/// light every time the tablet reloads, so the choice is written to local
/// storage and read back before the first frame.
class ThemeNotifier extends Notifier<bool> {
  static const _key = 'spd.theme.light';

  @override
  bool build() => ref.read(sharedPrefsProvider)?.getBool(_key) ?? false;

  void toggle() => set(!state);

  void set(bool light) {
    if (light == state) return;
    state = light;
    // Fire-and-forget: a storage that refuses to write must not stop someone
    // changing the theme for this session.
    unawaited(ref.read(sharedPrefsProvider)?.setBool(_key, light) ?? Future.value());
  }
}

final themeLightProvider = NotifierProvider<ThemeNotifier, bool>(ThemeNotifier.new);

/* --------------------------------------------------------------- shifts --- */

final shiftsProvider = FutureProvider<List<Shift>>((ref) async {
  ref.watch(sessionProvider.select((s) => s.signedIn));
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).shifts();
});

/// The shift the whole console is scoped to. Null until the list loads, at
/// which point [selectedShiftProvider] falls back to the newest one.
final shiftIdProvider = uiValue<String?>(null);

final selectedShiftProvider = Provider<String?>((ref) {
  final explicit = ref.watch(shiftIdProvider);
  if (explicit != null) return explicit;
  final shifts = ref.watch(shiftsProvider).value;
  return shifts != null && shifts.isNotEmpty ? shifts.first.id : null;
});

/// The selected shift's own record, for the lock state and label.
final currentShiftProvider = Provider<Shift?>((ref) {
  final id = ref.watch(selectedShiftProvider);
  final shifts = ref.watch(shiftsProvider).value;
  if (id == null || shifts == null) return null;
  for (final s in shifts) {
    if (s.id == id) return s;
  }
  return null;
});

/* ---------------------------------------------------------- live floor --- */

/// Bumped after any write, and on every live tick. Providers watch it so one
/// increment refreshes the whole console — which is what keeps the sidebar
/// counts, the tiles and the tables agreeing after a submission.
final dataVersionProvider = uiValue<int>(0);

/// FR-11.4 — the dashboard refreshes without a page reload. The prototype had a
/// "Floor live" toggle that simulated members packing; here it is the real
/// thing: a poll of the API at the configured interval. It stays a toggle for
/// the same reason the prototype's was — a supervisor reading a table does not
/// want the rows moving under them.
class LiveNotifier extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    return false;
  }

  void toggle(int seconds) {
    _timer?.cancel();
    if (state) {
      state = false;
      _timer = null;
      return;
    }
    state = true;
    _timer = Timer.periodic(Duration(seconds: seconds.clamp(5, 3600)), (_) => bump());
  }

  /// Forces every shift-scoped provider to refetch.
  void bump() => ref.read(dataVersionProvider.notifier).update((v) => v + 1);
}

final liveProvider = NotifierProvider<LiveNotifier, bool>(LiveNotifier.new);

/// Call after any write so the console reflects it everywhere at once. Takes a
/// [WidgetRef] because every caller is a screen; the providers themselves reach
/// the notifier directly.
void invalidateAll(WidgetRef ref) => ref.read(dataVersionProvider.notifier).update((v) => v + 1);

/* ------------------------------------------------------- data families --- */

/// Runs [run] against the selected shift, once there is one.
///
/// Awaiting the shift list rather than reading its current value matters more
/// than it looks. Throwing "No shift selected yet" while the list was merely in
/// flight turned an ordinary cold start into an *error*, and because Riverpod
/// keeps the previous error on a provider that is reloading, that error then
/// stuck to every screen for the rest of the session. It also masked the real
/// one: when the API was genuinely down, the screens reported a missing shift
/// rather than the connection failure the server never got to give.
///
/// `.future` suspends until the list resolves and rethrows its own failure, so
/// loading reads as loading and a failure carries the message NFR-4.2 wants.
Future<T> _scoped<T>(Ref ref, Future<T> Function(SpdRepository repo, String shiftId) run) async {
  ref.watch(dataVersionProvider);
  final shifts = await ref.watch(shiftsProvider.future);
  final id = ref.watch(shiftIdProvider) ?? (shifts.isEmpty ? null : shifts.first.id);
  if (id == null) throw ApiException('No shift has been created yet');
  return run(ref.watch(repositoryProvider), id);
}

final dashboardProvider = FutureProvider<DashboardPage>((ref) => _scoped(ref, (r, s) => r.dashboard(s)));

class LinesFilter {
  const LinesFilter({this.q = '', this.invoice = '', this.vendor = '', this.status = ''});

  final String q, invoice, vendor, status;

  LinesFilter copyWith({String? q, String? invoice, String? vendor, String? status}) => LinesFilter(
        q: q ?? this.q,
        invoice: invoice ?? this.invoice,
        vendor: vendor ?? this.vendor,
        status: status ?? this.status,
      );
}

final linesFilterProvider = uiValue<LinesFilter>(const LinesFilter());

final linesProvider = FutureProvider<LinesPage>((ref) {
  final f = ref.watch(linesFilterProvider);
  return _scoped(ref, (r, s) => r.lines(
        shiftId: s, q: f.q, invoice: f.invoice, vendor: f.vendor, status: f.status,
      ));
});

final grnBatchesProvider = FutureProvider<List<GrnBatch>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).grnBatches();
});

final tablesProvider = FutureProvider<List<TableStat>>((ref) => _scoped(ref, (r, s) => r.tables(s)));

final allocationsProvider = FutureProvider<List<Allocation>>((ref) => _scoped(ref, (r, s) => r.allocations(s)));

final labelLogProvider = FutureProvider<List<LabelPrint>>((ref) => _scoped(ref, (r, s) => r.labelLog(s)));

final reviewProvider = FutureProvider<ReviewPage>((ref) => _scoped(ref, (r, s) => r.review(s)));

final hourlyProvider = FutureProvider<HourlyPage>((ref) => _scoped(ref, (r, s) => r.hourly(s)));

class MisFilter {
  const MisFilter({this.dim = 'line', this.invoice = '', this.table = '', this.member = ''});

  final String dim, invoice, table, member;

  MisFilter copyWith({String? dim, String? invoice, String? table, String? member}) => MisFilter(
        dim: dim ?? this.dim,
        invoice: invoice ?? this.invoice,
        table: table ?? this.table,
        member: member ?? this.member,
      );
}

final misFilterProvider = uiValue<MisFilter>(const MisFilter());

final misProvider = FutureProvider<MisPage>((ref) {
  final f = ref.watch(misFilterProvider);
  return _scoped(ref, (r, s) => r.mis(
        shiftId: s, dim: f.dim, invoice: f.invoice, table: f.table, member: f.member,
      ));
});

final facetsProvider = FutureProvider<Facets>((ref) => _scoped(ref, (r, s) => r.facets(s)));

class AuditFilter {
  const AuditFilter({this.action = '', this.q = ''});

  final String action, q;

  AuditFilter copyWith({String? action, String? q}) =>
      AuditFilter(action: action ?? this.action, q: q ?? this.q);
}

final auditFilterProvider = uiValue<AuditFilter>(const AuditFilter());

final auditProvider = FutureProvider<AuditPage>((ref) {
  final f = ref.watch(auditFilterProvider);
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).audit(action: f.action, q: f.q);
});

final usersProvider = FutureProvider<List<SpdUser>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).users();
});

final configProvider = FutureProvider<SpdConfig>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).config();
});

final notificationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) => _scoped(ref, (r, s) => r.notifications(s)));

/* ------------------------------------------------------- member screens --- */

/// When an Administrator previews the member screens, they do so against a
/// chosen table rather than a member's own session.
final previewTableProvider = uiValue<String>('T-01');

final myQueueProvider = FutureProvider<MemberQueue>((ref) {
  final session = ref.watch(sessionProvider);
  final asAdmin = session.user?.role != 'Member';
  final table = ref.watch(previewTableProvider);
  return _scoped(ref, (r, s) => r.myQueue(shiftId: s, table: asAdmin ? table : null));
});

final myHistoryProvider = FutureProvider<List<PackingTxn>>((ref) => _scoped(ref, (r, s) => r.myHistory(shiftId: s)));

/// The line the member has selected on the Pack screen, before Start.
final selectedPackLineProvider = uiValue<String?>(null);

/// Ticks once a second so the running packing timer counts up.
final packClockProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
);

/* -------------------------------------------------------------- retries --- */

/// How hard the app retries a failed read before telling the user.
///
/// Riverpod's default is ten attempts with a doubling backoff, which is about
/// thirty-eight seconds. For that whole time a screen sits on its loader with
/// the error held but not shown, so a Supervisor whose server is down watches a
/// spinner and is given nothing to act on — while every screen already carries
/// an ErrorPanel with a Try again button, built for exactly this moment.
///
/// Two quick attempts absorb a genuine blip. Past that the screen says what
/// happened and hands the retry back to the person, who knows things the client
/// does not: that the server is being restarted, or the site network is out.
///
/// A 4xx is never retried. A refused permission or a rejected quantity will be
/// refused identically the second time, and repeating it only delays the
/// message NFR-4.2 wants shown.
Duration? spdRetry(int retryCount, Object error) {
  if (error is Error) return null;
  if (error is ApiException) {
    final code = error.statusCode;
    if (code != null && code >= 400 && code < 500) return null;
  }
  if (retryCount >= 2) return null;
  return Duration(milliseconds: 200 * (retryCount + 1));
}
