import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:ui' show PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:vistar_event_tracker/vistar_event_tracker.dart'
    show EventType, TrackerConfig, VistarEventTracker, VistarEvents;

import 'api.dart' show resolveApiRoot;

/// Usage analytics for the SPD console, sent to the in-house event tracker and
/// read in the Platform Console under Analytics > Event tracker.
///
/// Off unless the build is given both:
///   --dart-define=ET_APP_ID=spd_app --dart-define=ET_WRITE_KEY=wk_...
/// (register the app in the Platform Console, Settings > Event tracker; the
/// write key only lets a client append events, so it may ship in the app).
/// Optional --dart-define=ET_BASE_URL=... sends a test build's events
/// somewhere other than the API host the console uses (by default, the host
/// of SPD_API, so a UAT build reports to UAT).
///
/// What is sent:
///   * screen views, by route pattern (`/lines`, `/my/pack`; any value in a
///     path is replaced by `:id` / `:ref`, see [routePattern])
///   * sign-in / sign-out; the user as `spd:<pseudonym>` (see [pseudonym]:
///     an SPD user id is the login id, made from the person's name), with
///     their role as the only trait
///   * named actions from successful API writes (see [_actions]):
///     `grn_uploaded`, `line_allocated`, `packing_submitted`,
///     `shift_finalised`, ...
///   * failed API calls (5xx or no connection), and client errors by TYPE
///     only (never the message, which can quote a server reply)
/// Never sent: request or response bodies, login ids, names, employee codes,
/// emails, PINs, part numbers, invoice numbers, vendor names, line / label /
/// batch / kit / table ids, quantities, remarks or any other record content.
///
/// NEVER IN THE WAY OF WORK. Nothing here is awaited by a screen, a packing
/// submission, a sign-in or a sign-out; start-up waits at most [_initBudget];
/// every call swallows its own failures; the queue is capped at [_maxQueue]
/// events (oldest dropped) and lives in shared preferences; sending is in the
/// background with the SDK's backoff.
abstract final class Telemetry {
  static const _appId = String.fromEnvironment('ET_APP_ID');
  static const _writeKey = String.fromEnvironment('ET_WRITE_KEY');
  static const _baseUrlOverride = String.fromEnvironment('ET_BASE_URL');
  static const _appVersion = String.fromEnvironment('APP_VERSION');
  static const _initBudget = Duration(seconds: 2);
  static const _maxQueue = 200;

  static bool get enabled => _appId != '' && _writeKey != '';

  static VistarEventTracker get _t => VistarEventTracker.instance;
  static bool get _on => enabled && _t.isInitialized;

  static String? _lastScreen;
  static Future<void>? _resetting;

  static String get _origin {
    if (_baseUrlOverride.isNotEmpty) return _baseUrlOverride;
    final u = Uri.parse(resolveApiRoot());
    return '${u.scheme}://${u.authority}';
  }

  static Future<void> init() async {
    if (!enabled) return;
    try {
      await _t
          .init(TrackerConfig(
            appId: _appId,
            writeKey: _writeKey,
            baseUrl: _origin,
            appVersion: _appVersion.isEmpty ? null : _appVersion,
            maxQueueSize: _maxQueue,
            // The SDK's own error capture sends the exception message and
            // stack, and a message here can quote a server reply (a part
            // number, an invoice). [_captureErrors] sends the type only.
            autoCaptureErrors: false,
          ))
          .timeout(_initBudget);
      _captureErrors();
    } catch (_) {
      // Analytics must never stop the console from starting.
    }
  }

  /// Client errors, by type only. Chains to whatever handled them before, so
  /// the app's own error handling is unchanged.
  static void _captureErrors() {
    if (!_on) return;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      _clientError(details.exception, fatal: false, library: details.library);
      previous?.call(details);
    };
    final dispatcher = PlatformDispatcher.instance;
    final previousAsync = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      _clientError(error, fatal: true);
      return previousAsync?.call(error, stack) ?? false;
    };
  }

  static void _clientError(Object e, {required bool fatal, String? library}) {
    try {
      error(VistarEvents.clientError, {
        'error': e.runtimeType.toString(),
        'library': ?library,
        'fatal': fatal,
      });
    } catch (_) {}
  }

  /// A screen, by its route pattern. Repeats are dropped, and so is the brand
  /// splash (two seconds of logo, not a screen anyone uses).
  static void screen(String location) {
    if (!_on) return;
    final name = routePattern(location);
    if (name == _lastScreen || name == '/splash') return;
    _lastScreen = name;
    _guard(() => _t.screen(name));
  }

  static void track(String name, [Map<String, dynamic>? properties]) {
    if (_on) _guard(() => _t.track(name, properties: properties));
  }

  static void error(String name, Map<String, dynamic> properties) {
    if (_on) _guard(() => _t.track(name, properties: properties, type: EventType.error));
  }

  static void _guard(void Function() fn) {
    try {
      fn();
    } catch (_) {
      // Analytics never surfaces as an app error.
    }
  }

  /// Fire and forget: the sign-in never waits for analytics.
  ///
  /// Called just BEFORE the session state changes. With no sign-out in flight
  /// the SDK sets the user synchronously (before its first await), so the
  /// screen the sign-in leads to is already attributed to them.
  static void signedIn({required String userId, String? role}) {
    if (!_on || userId.isEmpty) return;
    final id = 'spd:${pseudonym(userId)}';
    final traits = <String, dynamic>{
      if (role != null && role.isNotEmpty) 'role': role,
    };
    final pending = _resetting;
    if (pending == null) {
      _identify(id, traits);
      return;
    }
    // A sign-out just before (a floor tablet changing hands between table
    // members) resets the identity; let it finish so this one is not wiped.
    unawaited(() async {
      try {
        await pending.timeout(const Duration(seconds: 5), onTimeout: () {});
      } catch (_) {}
      _identify(id, traits);
    }());
  }

  static void _identify(String id, Map<String, dynamic> traits) {
    try {
      unawaited(_t.identify(id, traits: traits).catchError((Object _) {}));
    } catch (_) {}
  }

  /// Fire and forget: the sign-out never waits for analytics (the SDK's reset
  /// sends what is queued first, which can take a while on a poor network).
  static void signedOut() {
    _lastScreen = null;
    if (!_on) return;
    try {
      late final Future<void> done;
      done = _t.reset().catchError((Object _) {}).whenComplete(() {
        if (identical(_resetting, done)) _resetting = null;
      });
      _resetting = done;
    } catch (_) {}
  }

  /// The id the tracker knows a user by.
  ///
  /// An SPD user's id IS their login id (`sup.rmenon`, `tm.ssingh`: role
  /// prefix and name), and spd.users has no other key, so it is not sent.
  /// This is its 64-bit FNV-1a digest in hex: stable per user, so sessions and
  /// screens are counted per person, with no name in it. It is a pseudonym,
  /// not a secret: anyone holding the roster can recompute it, which is what
  /// lets an administrator look one up. The employee code is never used.
  static String pseudonym(String loginId) {
    final mask = (BigInt.one << 64) - BigInt.one;
    final prime = BigInt.parse('100000001b3', radix: 16);
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    for (final b in utf8.encode(loginId)) {
      h = ((h ^ BigInt.from(b)) * prime) & mask;
    }
    return h.toRadixString(16).padLeft(16, '0');
  }

  /// Every fixed segment of this console's screens and of the SPD API paths it
  /// calls (relative to SPD_API, `.../api/v1/spd`).
  static const _static = {
    // API mount
    'api', 'v1', 'spd',
    // screens
    'splash', 'login', 'dashboard', 'grn', 'lines', 'labels', 'allocation',
    'review', 'hourly', 'mis', 'audit', 'my', 'work', 'pack', 'history',
    'admin', 'users', 'config',
    // API
    'auth', 'members', 'logout', 'me', 'shifts', 'finalise', 'reopen',
    'batches', 'upload', 'errors.csv', 'adjust', 'preview', 'print', 'log',
    'sheet.pdf', 'tables', 'allocations', 'queue', 'start', 'submit',
    'exceptions', 'notifications', 'search', 'facets', 'generate', 'export',
    'xlsx', 'csv', 'pdf',
  };

  /// `/labels/L0042/preview?x=1` -> `/labels/:ref/preview`.
  ///
  /// Stricter than "replace anything with a digit": SPD's keys are typed or
  /// made from names, and some have no digit at all (a login id such as
  /// `tm.gk`, a table typed as `BENCH`). So only the segments in [_static]
  /// are kept; digits only or a UUID become `:id`; everything else (line,
  /// label, transaction, exception, allocation and hourly ids such as `L0042`,
  /// `TX0107`, `EX014`, `AL051`, `HR-04`; GRN batches `GRN-0909-01`; shifts
  /// `A-2026-09-09`; tables `T-07`; login ids; part or invoice numbers) becomes
  /// `:ref`. The query string is dropped.
  static String routePattern(String location) {
    final path = Uri.tryParse(location)?.path ?? location.split('?').first;
    return path.split('/').map((s) {
      if (s.isEmpty) return s;
      if (RegExp(r'^\d+$').hasMatch(s)) return ':id';
      if (RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-', caseSensitive: false).hasMatch(s)) return ':id';
      if (_static.contains(s)) return s;
      return ':ref';
    }).join('/');
  }

  /// Successful API writes worth naming, by method and path (ids stripped).
  /// First match wins; anything else (reads, exports, sign-in / sign-out,
  /// unknown paths) is not reported.
  static final List<(String, RegExp, String)> _actions = [
    // Shift and GRN intake (FR-1)
    ('POST', RegExp(r'^/shifts$'), 'shift_created'),
    ('POST', RegExp(r'^/grn/upload$'), 'grn_uploaded'),
    ('DELETE', RegExp(r'^/grn/batches/:(id|ref)$'), 'grn_batch_deleted'),
    // Lines and labels (FR-2, FR-3, BR-01)
    ('POST', RegExp(r'^/lines/:(id|ref)/adjust$'), 'line_qty_adjusted'),
    ('POST', RegExp(r'^/labels/:(id|ref)/print$'), 'label_printed'),
    // Allocation and tables (FR-4)
    ('POST', RegExp(r'^/allocations$'), 'line_allocated'),
    ('DELETE', RegExp(r'^/allocations/:(id|ref)$'), 'allocation_withdrawn'),
    ('POST', RegExp(r'^/tables$'), 'packing_table_created'),
    ('PATCH', RegExp(r'^/tables/:(id|ref)$'), 'table_member_assigned'),
    // Packing on the floor (FR-6, FR-7)
    ('POST', RegExp(r'^/my/start$'), 'packing_started'),
    ('POST', RegExp(r'^/my/submit$'), 'packing_submitted'),
    // Review and final submission (FR-9, FR-10)
    ('PATCH', RegExp(r'^/exceptions/:(id|ref)$'), 'exception_annotated'),
    ('POST', RegExp(r'^/shifts/:(id|ref)/finalise$'), 'shift_finalised'),
    ('POST', RegExp(r'^/shifts/:(id|ref)/reopen$'), 'shift_reopened'),
    // Reports (FR-8)
    ('POST', RegExp(r'^/hourly/generate$'), 'hourly_report_generated'),
    // Administration (FR-13)
    ('POST', RegExp(r'^/users$'), 'user_created'),
    ('PATCH', RegExp(r'^/users/:(id|ref)$'), 'user_updated'),
    ('PUT', RegExp(r'^/config$'), 'config_updated'),
  ];

  /// The business event for a successful API call, or null.
  static String? actionFor(String method, String path) {
    final pattern = routePattern(path);
    final m = method.toUpperCase();
    for (final (am, re, name) in _actions) {
      if (am == m && re.hasMatch(pattern)) return name;
    }
    return null;
  }
}

/// Reports named actions and failed calls from the console's one HTTP client
/// (core/api.dart). Adds no headers and changes nothing about the request or
/// its handling.
class TelemetryInterceptor extends Interceptor {
  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    // This client's validateStatus accepts anything below 500, so a 4xx
    // refusal (an over-pack, a duplicate batch, a wrong PIN) arrives HERE and
    // must not count: only a 2xx is an action that happened.
    final code = response.statusCode ?? 0;
    if (Telemetry.enabled && code >= 200 && code < 300) {
      String? name;
      try {
        final o = response.requestOptions;
        name = Telemetry.actionFor(o.method, o.path);
      } catch (_) {}
      if (name != null) Telemetry.track(name);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (Telemetry.enabled) {
      try {
        final status = err.response?.statusCode;
        // A 4xx is a decision the server made, and a cancel is the app's own.
        if ((status == null || status >= 500) && err.type != DioExceptionType.cancel) {
          Telemetry.error('api_error', {
            'endpoint': Telemetry.routePattern(err.requestOptions.path),
            'method': err.requestOptions.method,
            'status': ?status,
            'kind': err.type.name,
          });
        }
      } catch (_) {}
    }
    handler.next(err);
  }
}
