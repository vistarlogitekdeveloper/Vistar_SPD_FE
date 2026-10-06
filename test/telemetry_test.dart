import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spd_frontend/core/telemetry.dart';

void main() {
  const uuid = '7f3c2a10-1b2c-4d5e-8f90-a1b2c3d4e5f6';

  test('screen names are the console routes, unchanged', () {
    for (final r in [
      '/login', '/dashboard', '/grn', '/lines', '/labels', '/allocation', '/review', '/hourly',
      '/mis', '/audit', '/my/work', '/my/pack', '/my/history', '/admin/users', '/admin/config',
    ]) {
      expect(Telemetry.routePattern(r), r);
    }
    expect(Telemetry.routePattern('/lines?invoice=INV-2207&vendor=Acme'), '/lines');
  });

  test("SPD's own keys never survive: line, label, txn, exception, allocation, hourly, batch, shift, table", () {
    expect(Telemetry.routePattern('/labels/L0042/preview'), '/labels/:ref/preview');
    expect(Telemetry.routePattern('/labels/L0042/print'), '/labels/:ref/print');
    expect(Telemetry.routePattern('/lines/L0042/adjust'), '/lines/:ref/adjust');
    expect(Telemetry.routePattern('/allocations/AL051'), '/allocations/:ref');
    expect(Telemetry.routePattern('/exceptions/EX014'), '/exceptions/:ref');
    expect(Telemetry.routePattern('/hourly/HR-04'), '/hourly/:ref');
    expect(Telemetry.routePattern('/hourly/TX0107'), '/hourly/:ref');
    expect(Telemetry.routePattern('/grn/batches/GRN-0909-01'), '/grn/batches/:ref');
    expect(Telemetry.routePattern('/shifts/A-2026-09-09/finalise'), '/shifts/:ref/finalise');
    expect(Telemetry.routePattern('/tables/T-07'), '/tables/:ref');
    expect(Telemetry.routePattern('/tables/BENCH'), '/tables/:ref');
    expect(Telemetry.routePattern('/tables/bench'), '/tables/:ref');
    expect(Telemetry.routePattern('/lines/42'), '/lines/:id');
    expect(Telemetry.routePattern('/lines/$uuid'), '/lines/:id');
  });

  test('login ids, employee codes, part and invoice numbers never survive', () {
    expect(Telemetry.routePattern('/users/sup.rmenon'), '/users/:ref');
    expect(Telemetry.routePattern('/users/tm.gk'), '/users/:ref');
    expect(Telemetry.routePattern('/users/EMP-4412'), '/users/:ref');
    expect(Telemetry.routePattern('/lines/PRT%2F8812-A'), '/lines/:ref');
    expect(Telemetry.routePattern('/lines/INV-2026-00118'), '/lines/:ref');
    expect(Telemetry.routePattern('https://api.example.com/api/v1/spd/users/sup.rmenon'), '/api/v1/spd/users/:ref');
    expect(Telemetry.routePattern('/export/mis/xlsx'), '/export/mis/xlsx');
  });

  test('the user is a pseudonym of the login id, never the id itself', () {
    // 64-bit FNV-1a, so an administrator can recompute it from the roster.
    expect(Telemetry.pseudonym('sup.rmenon'), '5832c78babf02db4');
    expect(Telemetry.pseudonym('tm.ssingh'), 'fdf46d8e39bc132a');
    expect(Telemetry.pseudonym('sup.rmenon'), isNot(contains('rmenon')));
    expect(Telemetry.pseudonym('tm.ssingh'), isNot(Telemetry.pseudonym('tm.pnair')));
  });

  test('the pre-packing journey is named from successful writes', () {
    expect(Telemetry.actionFor('POST', '/shifts'), 'shift_created');
    expect(Telemetry.actionFor('POST', '/grn/upload'), 'grn_uploaded');
    expect(Telemetry.actionFor('DELETE', '/grn/batches/GRN-0909-01'), 'grn_batch_deleted');
    expect(Telemetry.actionFor('POST', '/lines/L0042/adjust'), 'line_qty_adjusted');
    expect(Telemetry.actionFor('POST', '/labels/L0042/print'), 'label_printed');
    expect(Telemetry.actionFor('POST', '/allocations'), 'line_allocated');
    expect(Telemetry.actionFor('DELETE', '/allocations/AL051'), 'allocation_withdrawn');
    expect(Telemetry.actionFor('POST', '/tables'), 'packing_table_created');
    expect(Telemetry.actionFor('PATCH', '/tables/T-07'), 'table_member_assigned');
    expect(Telemetry.actionFor('post', '/my/start'), 'packing_started');
    expect(Telemetry.actionFor('POST', '/my/submit'), 'packing_submitted');
    expect(Telemetry.actionFor('PATCH', '/exceptions/EX014'), 'exception_annotated');
    expect(Telemetry.actionFor('POST', '/shifts/A-2026-09-09/finalise'), 'shift_finalised');
    expect(Telemetry.actionFor('POST', '/shifts/A-2026-09-09/reopen'), 'shift_reopened');
    expect(Telemetry.actionFor('POST', '/hourly/generate'), 'hourly_report_generated');
    expect(Telemetry.actionFor('POST', '/users'), 'user_created');
    expect(Telemetry.actionFor('PATCH', '/users/tm.gk'), 'user_updated');
    expect(Telemetry.actionFor('PUT', '/config'), 'config_updated');
  });

  test('reads, exports, sign-in / sign-out and unknown paths are not reported', () {
    expect(Telemetry.actionFor('GET', '/lines'), isNull);
    expect(Telemetry.actionFor('GET', '/lines/L0042'), isNull);
    expect(Telemetry.actionFor('GET', '/my/queue'), isNull);
    expect(Telemetry.actionFor('GET', '/my/preview'), isNull);
    expect(Telemetry.actionFor('GET', '/labels/sheet.pdf'), isNull);
    expect(Telemetry.actionFor('GET', '/export/mis/xlsx'), isNull);
    expect(Telemetry.actionFor('GET', '/auth/members'), isNull);
    expect(Telemetry.actionFor('POST', '/auth/login'), isNull);
    expect(Telemetry.actionFor('POST', '/auth/logout'), isNull);
    expect(Telemetry.actionFor('POST', '/grn/errors.csv'), isNull);
    expect(Telemetry.actionFor('DELETE', '/users/tm.gk'), isNull);
    expect(Telemetry.actionFor('POST', '/somewhere/new'), isNull);
  });

  test('off without ET_APP_ID and ET_WRITE_KEY (the default build); calls are safe', () async {
    expect(Telemetry.enabled, isFalse);
    await Telemetry.init();
    Telemetry.screen('/dashboard');
    Telemetry.track('packing_submitted');
    Telemetry.error('api_error', {'endpoint': '/my/submit', 'method': 'POST'});
    Telemetry.signedIn(userId: 'tm.ssingh', role: 'Member');
    Telemetry.signedOut();
  });

  test('the interceptor changes nothing about a request or its outcome', () async {
    // This client's validateStatus: below 500 is a response, not an error.
    final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid', validateStatus: (s) => s != null && s < 500))
      ..httpClientAdapter = _Answer()
      ..interceptors.add(TelemetryInterceptor());
    final ok = await dio.post<dynamic>('/my/submit', data: {'txnId': 'TX0107', 'qty': 12});
    expect(ok.statusCode, 200);
    expect((ok.data as Map)['ok'], isTrue);
    final refused = await dio.post<dynamic>('/allocations', data: {'lineId': 'L0042'});
    expect(refused.statusCode, 409);
    await expectLater(
      dio.post<dynamic>('/shifts/A-2026-09-09/finalise'),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 503)),
    );
  });
}

/// 200 for a submission, 409 for an allocation, 503 for anything else; no
/// network.
class _Answer implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final status = switch (options.path) {
      '/my/submit' => 200,
      '/allocations' => 409,
      _ => 503,
    };
    return ResponseBody.fromString(
      jsonEncode({'ok': status == 200}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
