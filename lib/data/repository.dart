import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../models/models.dart';

/// One place that knows the API's shape. Screens call these methods and get
/// models back; nothing above this file handles a raw JSON map.
class SpdRepository {
  SpdRepository(this.api);

  final ApiClient api;

  Map<String, dynamic> _m(dynamic v) => Map<String, dynamic>.from(v as Map);
  List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) make) =>
      (v as List? ?? const []).map((e) => make(_m(e))).toList();

  /* ------------------------------------------------------------- auth --- */

  /// FR-5.1 — the member roster the login picker draws, available before sign-in.
  Future<List<Map<String, dynamic>>> members() async {
    final res = await api.get('/auth/members');
    return (res['members'] as List).map(_m).toList();
  }

  Future<({String token, SpdUser user})> login({
    required String userId,
    String? password,
    String? pin,
  }) async {
    final res = await api.post('/auth/login', body: {
      'userId': userId,
      if (password != null && password.isNotEmpty) 'password': password,
      if (pin != null && pin.isNotEmpty) 'pin': pin,
    });
    return (token: '${res['token']}', user: SpdUser(_m(res['user'])));
  }

  Future<SpdUser> me() async => SpdUser(_m((await api.get('/auth/me'))['user']));

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } on ApiException {
      // Signing out locally must succeed even if the server is unreachable.
    }
  }

  /* ----------------------------------------------------------- shifts --- */

  Future<List<Shift>> shifts() async => _list((await api.get('/shifts'))['shifts'], Shift.new);

  /* -------------------------------------------------------------- GRN --- */

  Future<List<GrnBatch>> grnBatches({String? shiftId}) async =>
      _list((await api.get('/grn/batches', query: {'shiftId': shiftId}))['batches'], GrnBatch.new);

  /// FR-1.1. Returns the import outcome including the row/column errors of
  /// FR-1.3; a BR-08 duplicate surfaces as an [ApiException] with
  /// `isDuplicateBatch` set, which the screen turns into the confirm dialog.
  Future<GrnImportResult> uploadGrn({
    required String shiftId,
    required String filename,
    required Uint8List bytes,
    bool confirm = false,
    String reason = '',
  }) async {
    final form = FormData.fromMap({
      'shiftId': shiftId,
      'confirm': confirm.toString(),
      'reason': reason,
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await api.upload('/grn/upload', form);
    return GrnImportResult(_m(res));
  }


  /* ------------------------------------------------------------ lines --- */

  Future<LinesPage> lines({
    required String shiftId,
    String invoice = '',
    String vendor = '',
    String status = '',
    String q = '',
    String table = '',
    String member = '',
  }) async {
    final res = await api.get('/lines', query: {
      'shiftId': shiftId,
      'invoice': invoice,
      'vendor': vendor,
      'status': status,
      'q': q,
      'table': table,
      'member': member,
    });
    return LinesPage(
      lines: _list(res['lines'], GrnLine.new),
      invoices: (res['invoices'] as List? ?? const []).map((e) => '$e').toList(),
      vendors: (res['vendors'] as List? ?? const []).map((e) => '$e').toList(),
    );
  }

  Future<LineDetail> line(String id) async {
    final res = await api.get('/lines/$id');
    return LineDetail(
      line: GrnLine(_m(res['line'])),
      txns: _list(res['txns'], PackingTxn.new),
      exceptions: _list(res['exceptions'], SpdException.new),
      allocations: _list(res['allocations'], Allocation.new),
    );
  }

  /* ----------------------------------------------------------- labels --- */

  Future<LabelPreview> labelPreview(String lineId) async {
    final res = await api.get('/labels/$lineId/preview');
    return LabelPreview(
      line: GrnLine(_m(res['line'])),
      template: '${res['template']}',
      labels: [
        for (final l in (res['labels'] as List? ?? const []))
          LabelUnit(
            index: (l['index'] as num?)?.toInt() ?? 1,
            of: (l['of'] as num?)?.toInt() ?? 1,
            qty: (l['qty'] as num?) ?? 0,
            payload: '${l['payload']}',
            qr: (l['qr'] as List).map((row) => (row as List).map((c) => c == 1).toList()).toList(),
            barcode: (l['barcode'] as List).map((e) => (e as num).toInt()).toList(),
          ),
      ],
      alreadyPrinted: res['alreadyPrinted'] == true,
    );
  }

  Future<List<LabelPrint>> labelLog(String shiftId) async =>
      _list((await api.get('/labels/log', query: {'shiftId': shiftId}))['prints'], LabelPrint.new);

  Future<bool> printLabel({required String lineId, int copies = 1, String reason = ''}) async {
    final res = await api.post('/labels/$lineId/print', body: {'copies': copies, 'reason': reason});
    return res['reprint'] == true;
  }

  Future<Uint8List> labelSheetPdf({String? shiftId, String? lineId}) =>
      api.download('/labels/sheet.pdf', query: {'shiftId': shiftId, 'lineId': lineId});

  /* ------------------------------------------------------ allocations --- */

  Future<List<TableStat>> tables(String shiftId) async =>
      _list((await api.get('/tables', query: {'shiftId': shiftId}))['tables'], TableStat.new);

  Future<List<Allocation>> allocations(String shiftId) async =>
      _list((await api.get('/allocations', query: {'shiftId': shiftId}))['allocations'], Allocation.new);

  Future<void> allocate({
    required String lineId,
    required String tableNo,
    String? splitWith,
    num? qty1,
    num? qty2,
    String reason = '',
  }) =>
      api.post('/allocations', body: {
        'lineId': lineId,
        'tableNo': tableNo,
        if (splitWith != null && splitWith.isNotEmpty) 'splitWith': splitWith,
        'qty1': ?qty1,
        'qty2': ?qty2,
        'reason': reason,
      });

  Future<void> withdrawAllocation(String id) => api.delete('/allocations/$id');

  Future<void> assignTableMember({required String tableNo, String? memberId}) =>
      api.patch('/tables/$tableNo', body: {'memberId': memberId});

  /* ---------------------------------------------------------- packing --- */

  Future<MemberQueue> myQueue({required String shiftId, String? table, String? member}) async {
    final res = await api.get('/my/queue', query: {'shiftId': shiftId, 'table': table, 'member': member});
    return MemberQueue(
      tableNo: '${res['tableNo']}',
      shift: Shift(_m(res['shift'])),
      locked: res['locked'] == true,
      lines: _list(res['lines'], GrnLine.new),
      running: res['running'] == null ? null : PackingTxn(_m(res['running'])),
      stats: MemberStat(_m(res['stats'])),
      threshold: (res['threshold'] as num?)?.toInt() ?? 50,
    );
  }

  Future<PackingTxn> startPacking({required String lineId, String? tableNo, String? memberId}) async {
    final res = await api.post('/my/start', body: {
      'lineId': lineId,
      'tableNo': ?tableNo,
      'memberId': ?memberId,
    });
    return PackingTxn(_m(res['txn']));
  }

  Future<SubmitResult> submitPacking({
    required String txnId,
    required int qty,
    int pouches = 0,
    int boxes = 0,
    String? memberId,
  }) async {
    final res = await api.post('/my/submit', body: {
      'txnId': txnId,
      'qty': qty,
      'pouches': pouches,
      'boxes': boxes,
      'memberId': ?memberId,
    });
    return SubmitResult(
      txn: PackingTxn(_m(res['txn'])),
      line: GrnLine(_m(res['line'])),
      exception: res['exception'] == null ? null : SpdException(_m(res['exception'])),
    );
  }

  Future<SubmitHint?> submitHint({required String lineId, required int qty}) async {
    final res = await api.get('/my/preview', query: {'lineId': lineId, 'qty': qty});
    return res['hint'] == null ? null : SubmitHint(_m(res['hint']));
  }

  Future<List<PackingTxn>> myHistory({String? shiftId, String? member}) async =>
      _list((await api.get('/my/history', query: {'shiftId': shiftId, 'member': member}))['txns'], PackingTxn.new);

  /* ----------------------------------------------------------- review --- */

  Future<ReviewPage> review(String shiftId) async {
    final res = await api.get('/review', query: {'shiftId': shiftId});
    return ReviewPage(
      shift: Shift(_m(res['shift'])),
      stats: ShiftStats(_m(res['stats'])),
      exceptions: _list(res['exceptions'], SpdException.new),
      tables: _list(res['tables'], TableStat.new),
      members: _list(res['members'], MemberStat.new),
      canFinalise: res['canFinalise'] == true,
    );
  }

  Future<void> annotateException({required String id, required String remarks, bool resolve = false}) =>
      api.patch('/exceptions/$id', body: {'remarks': remarks, 'resolve': resolve});

  Future<String> finaliseShift(String shiftId) async {
    final res = await api.post('/shifts/$shiftId/finalise');
    return '${res['misId']}';
  }

  Future<Shift> reopenShift({required String shiftId, required String reason}) async {
    final res = await api.post('/shifts/$shiftId/reopen', body: {'reason': reason});
    return Shift(_m(res['shift']));
  }

  /* -------------------------------------------------------- dashboard --- */

  Future<DashboardPage> dashboard(String shiftId) async {
    final res = await api.get('/dashboard', query: {'shiftId': shiftId});
    return DashboardPage(
      shift: Shift(_m(res['shift'])),
      stats: ShiftStats(_m(res['stats'])),
      tables: _list(res['tables'], TableStat.new),
      members: _list(res['members'], MemberStat.new),
      lines: _list(res['lines'], GrnLine.new),
      batchId: res['batchId'] as String?,
      hourlyCount: (res['hourlyCount'] as num?)?.toInt() ?? 0,
      refreshSeconds: (res['refreshSeconds'] as num?)?.toInt() ?? 60,
      generatedAt: DateTime.now(),
    );
  }

  Future<List<Map<String, dynamic>>> notifications(String shiftId) async =>
      ((await api.get('/notifications', query: {'shiftId': shiftId}))['notifications'] as List).map(_m).toList();

  Future<List<GrnLine>> search({required String shiftId, required String q}) async =>
      _list((await api.get('/search', query: {'shiftId': shiftId, 'q': q}))['results'], GrnLine.new);

  Future<Facets> facets(String shiftId) async {
    final res = await api.get('/facets', query: {'shiftId': shiftId});
    return Facets(
      invoices: (res['invoices'] as List).map((e) => '$e').toList(),
      vendors: (res['vendors'] as List).map((e) => '$e').toList(),
      tables: (res['tables'] as List).map((e) => '$e').toList(),
      members: (res['members'] as List).map(_m).toList(),
    );
  }

  /* --------------------------------------------------------- reports ---- */

  Future<HourlyPage> hourly(String shiftId) async {
    final res = await api.get('/hourly', query: {'shiftId': shiftId});
    return HourlyPage(
      reports: _list(res['reports'], HourlyReport.new),
      interval: (res['interval'] as num?)?.toInt() ?? 60,
      emails: (res['emails'] as List? ?? const []).map((e) => '$e').toList(),
    );
  }

  Future<HourlyReport> generateHourly(String shiftId) async {
    final res = await api.post('/hourly/generate', body: {'shiftId': shiftId});
    return HourlyReport(_m(res['report']));
  }

  Future<HourlyReport> hourlyDetail(String id) async =>
      HourlyReport(_m((await api.get('/hourly/$id'))['report']));

  Future<MisPage> mis({
    required String shiftId,
    String dim = 'line',
    String invoice = '',
    String table = '',
    String member = '',
  }) async {
    final res = await api.get('/mis', query: {
      'shiftId': shiftId, 'dim': dim, 'invoice': invoice, 'table': table, 'member': member,
    });
    return MisPage(
      shift: Shift(_m(res['shift'])),
      stats: ShiftStats(_m(res['stats'])),
      dim: '${res['dim']}',
      rows: _list(res['rows'], MisRow.new),
      snapshots: _list(res['snapshots'], MisSnapshot.new),
      provisional: res['provisional'] == true,
    );
  }

  Future<Uint8List> export({
    required String key,
    required String format,
    Map<String, dynamic> query = const {},
  }) =>
      api.download('/export/$key/$format', query: query);

  /* ----------------------------------------------------------- admin ---- */

  Future<List<SpdUser>> users() async => _list((await api.get('/users'))['users'], SpdUser.new);

  Future<void> createUser(Map<String, dynamic> body) => api.post('/users', body: body);

  Future<void> updateUser(String id, Map<String, dynamic> body) => api.patch('/users/$id', body: body);

  Future<SpdConfig> config() async => SpdConfig(_m((await api.get('/config'))['config']));

  Future<SpdConfig> saveConfig(Map<String, dynamic> patch) async =>
      SpdConfig(_m((await api.put('/config', body: patch))['config']));

  Future<AuditPage> audit({String action = '', String q = '', int limit = 300}) async {
    final res = await api.get('/audit', query: {'action': action, 'q': q, 'limit': limit});
    return AuditPage(
      entries: _list(res['entries'], AuditEntry.new),
      actions: (res['actions'] as List? ?? const []).map((e) => '$e').toList(),
    );
  }
}

/* -------------------------------------------------- response value types --- */

class GrnImportResult {
  GrnImportResult(this.raw);
  final Map<String, dynamic> raw;

  String get batchId => '${raw['batchId']}';
  int get imported => (raw['imported'] as num?)?.toInt() ?? 0;
  int get rejected => (raw['rejected'] as num?)?.toInt() ?? 0;
  List<Map<String, dynamic>> get errors =>
      (raw['errors'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

class LinesPage {
  LinesPage({required this.lines, required this.invoices, required this.vendors});
  final List<GrnLine> lines;
  final List<String> invoices;
  final List<String> vendors;
}

class LineDetail {
  LineDetail({required this.line, required this.txns, required this.exceptions, required this.allocations});
  final GrnLine line;
  final List<PackingTxn> txns;
  final List<SpdException> exceptions;
  final List<Allocation> allocations;
}

/// FR-3.5 — one printed label. A line with an MOQ of 300 and a GRN quantity of
/// 350 yields two of these, 300 and 50, each with its own quantity and QR.
class LabelUnit {
  LabelUnit({
    required this.index,
    required this.of,
    required this.qty,
    required this.payload,
    required this.qr,
    required this.barcode,
  });
  final int index;
  final int of;
  final num qty;
  final String payload;
  final List<List<bool>> qr;
  final List<int> barcode;

  bool get isSplit => of > 1;
  String get marker => '$index of $of';
}

class LabelPreview {
  LabelPreview({
    required this.line,
    required this.template,
    required this.labels,
    required this.alreadyPrinted,
  });
  final GrnLine line;
  final String template;
  final List<LabelUnit> labels;
  final bool alreadyPrinted;

  /// The first label, for the callers that only ever show one.
  LabelUnit get first => labels.first;
}

class MemberQueue {
  MemberQueue({
    required this.tableNo,
    required this.shift,
    required this.locked,
    required this.lines,
    required this.running,
    required this.stats,
    required this.threshold,
  });
  final String tableNo;
  final Shift shift;
  final bool locked;
  final List<GrnLine> lines;
  final PackingTxn? running;
  final MemberStat stats;
  final int threshold;

  List<GrnLine> get openLines => lines.where((l) => l.pending > 0).toList();
}

class SubmitResult {
  SubmitResult({required this.txn, required this.line, required this.exception});
  final PackingTxn txn;
  final GrnLine line;
  final SpdException? exception;
}

class ReviewPage {
  ReviewPage({
    required this.shift,
    required this.stats,
    required this.exceptions,
    required this.tables,
    required this.members,
    required this.canFinalise,
  });
  final Shift shift;
  final ShiftStats stats;
  final List<SpdException> exceptions;
  final List<TableStat> tables;
  final List<MemberStat> members;
  final bool canFinalise;
}

class DashboardPage {
  DashboardPage({
    required this.shift,
    required this.stats,
    required this.tables,
    required this.members,
    required this.lines,
    required this.batchId,
    required this.hourlyCount,
    required this.refreshSeconds,
    required this.generatedAt,
  });
  final Shift shift;
  final ShiftStats stats;
  final List<TableStat> tables;
  final List<MemberStat> members;
  final List<GrnLine> lines;
  final String? batchId;
  final int hourlyCount;
  final int refreshSeconds;
  final DateTime generatedAt;
}

class Facets {
  Facets({required this.invoices, required this.vendors, required this.tables, required this.members});
  final List<String> invoices;
  final List<String> vendors;
  final List<String> tables;
  final List<Map<String, dynamic>> members;
}

class HourlyPage {
  HourlyPage({required this.reports, required this.interval, required this.emails});
  final List<HourlyReport> reports;
  final int interval;
  final List<String> emails;
}

class MisPage {
  MisPage({
    required this.shift,
    required this.stats,
    required this.dim,
    required this.rows,
    required this.snapshots,
    required this.provisional,
  });
  final Shift shift;
  final ShiftStats stats;
  final String dim;
  final List<MisRow> rows;
  final List<MisSnapshot> snapshots;
  final bool provisional;
}

class AuditPage {
  AuditPage({required this.entries, required this.actions});
  final List<AuditEntry> entries;
  final List<String> actions;
}
