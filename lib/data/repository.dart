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

  /* The console no longer calls `/auth/members` or `/auth/tables`.

     Both are pre-authentication by necessity — they filled the sign-in
     screen's two pickers, so they answered before anyone had a token, which
     meant the staff roster and the whole seating plan were readable by anyone
     who could load the login page. The pickers are gone: a member types their
     own ID, the server resolves their table from the Supervisor's seating,
     and who is at the bench is asked afterwards (see [shiftOperators]).

     The endpoints themselves are left standing. Something older may still be
     pointed at them, and retiring a public route is a decision for whoever
     can see every client, not for the one that stopped calling it. */

  /// [tableNo] is the table a Table Member says they are on for this shift.
  /// Omitted, the server resolves one from the Supervisor's seating (or the
  /// standing plan), which is what the builds before this change relied on.
  /// Sent, it has to be a table this member is actually assigned to — the
  /// server refuses anything else rather than taking the console's word for it.
  Future<({String token, SpdUser user})> login({
    required String userId,
    String? password,
    String? pin,
    String? tableNo,
  }) async {
    final res = await api.post('/auth/login', body: {
      'userId': userId,
      if (password != null && password.isNotEmpty) 'password': password,
      if (pin != null && pin.isNotEmpty) 'pin': pin,
      if (tableNo != null && tableNo.isNotEmpty) 'tableNo': tableNo,
    });
    return (token: '${res['token']}', user: SpdUser(_m(res['user'])));
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } on ApiException {
      // Signing out locally must succeed even if the server is unreachable.
    }
  }

  /* ----------------------------------------------------------- shifts --- */

  Future<List<Shift>> shifts() async => _list((await api.get('/shifts'))['shifts'], Shift.new);

  /// Starts a new shift. Every data provider is scoped to one, so without this
  /// the console can only ever work on shifts that already exist — which, after
  /// the seeded pair, means it cannot be used on a new day at all.
  Future<Shift> createShift({
    required String id,
    required String label,
    required String shiftDate,
  }) async {
    final res = await api.post('/shifts', body: {
      'id': id,
      'label': label,
      'shiftDate': shiftDate,
    });
    return Shift(_m(res['shift']));
  }

  /* -------------------------------------------------------------- GRN --- */

  Future<List<GrnBatch>> grnBatches({String? shiftId}) async =>
      _list((await api.get('/grn/batches', query: {'shiftId': shiftId}))['batches'], GrnBatch.new);

  /// FR-1.6 — discards a mis-imported batch. The server refuses once anything
  /// has been packed against it, so this is only ever the correction of an
  /// upload nobody has worked from yet.
  Future<void> deleteGrnBatch(String id) => api.delete('/grn/batches/$id');

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


  /* ------------------------------------------------------ part master --- */

  /// What the part master holds: the counts a supervisor reads to know the
  /// upload worked, and a sample to eyeball.
  Future<({Map<String, dynamic> summary, List<Map<String, dynamic>> sample})>
      partMaster() async {
    final res = await api.get('/masters/parts');
    return (
      summary: _m(res['summary']),
      sample: (res['sample'] as List).map(_m).toList(),
    );
  }

  /// Replace the part master from a workbook.
  ///
  /// Replace, not merge: the master states the whole catalogue, so a part
  /// dropped from the file has been dropped from the catalogue. Returns the
  /// counts and any rejected rows, in the same shape the GRN import uses.
  Future<Map<String, dynamic>> uploadPartMaster({
    required String filename,
    required Uint8List bytes,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    return _m(await api.upload('/masters/parts', form));
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
      adjustments: _list(res['adjustments'], QtyAdjustment.new),
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
          ),
      ],
      alreadyPrinted: res['alreadyPrinted'] == true,
      printedOn: res['printedOn'] as String?,
    );
  }

  Future<List<LabelPrint>> labelLog(String shiftId) async =>
      _list((await api.get('/labels/log', query: {'shiftId': shiftId}))['prints'], LabelPrint.new);

  Future<bool> printLabel({required String lineId, int copies = 1, String reason = ''}) async {
    final res = await api.post('/labels/$lineId/print', body: {'copies': copies, 'reason': reason});
    return res['reprint'] == true;
  }

  /// FR-3.2 — the printable sheet, for one line, one invoice, one table or a
  /// whole shift.
  ///
  /// The scope is not a convenience. Every piece gets its own pouch, so a
  /// shift runs to tens of thousands of labels and the server refuses a sheet
  /// that large — an invoice is both what prints and what gets carried to the
  /// bench.
  Future<Uint8List> labelSheetPdf({
    String? shiftId,
    String? lineId,
    String invoice = '',
    String table = '',
  }) =>
      api.download('/labels/sheet.pdf', query: {
        'shiftId': shiftId,
        'lineId': lineId,
        if (invoice.isNotEmpty) 'invoice': invoice,
        if (table.isNotEmpty) 'table': table,
      });

  /* ------------------------------------------------------ allocations --- */

  Future<List<TableStat>> tables(String shiftId) async =>
      _list((await api.get('/tables', query: {'shiftId': shiftId}))['tables'], TableStat.new);

  Future<List<Allocation>> allocations(String shiftId) async =>
      _list((await api.get('/allocations', query: {'shiftId': shiftId}))['allocations'], Allocation.new);

  /// FR-4.1 — puts a line on one table or on several, in one call.
  ///
  /// A line goes to as many tables as the work needs and a table takes as many
  /// lines, so an invoice can be spread across the floor and a table can be
  /// working three invoices at once. What BR-04 still insists on is that a line
  /// never reaches a second table by accident: the first is a plain choice,
  /// and everything after it — whether named in this call or added to a line
  /// already placed — has to carry a reason, which the server enforces.
  ///
  /// A null `qty` means *this table works this line, quantity unstated*, which
  /// is the shared-queue case and what a single whole-line allocation has
  /// always sent.
  Future<void> allocate({
    required String lineId,
    required List<TableShare> tables,
    String reason = '',
  }) =>
      api.post('/allocations', body: {
        'lineId': lineId,
        'tables': [
          for (final t in tables) {'tableNo': t.tableNo, if (t.qty != null) 'qty': t.qty},
        ],
        'reason': reason,
      });

  /// BR-01 — closes out a remainder nobody will pack, or restores one.
  ///
  /// Pending is GRN minus packed and is computed, so there is no remaining
  /// quantity to edit; what this records is the third term, with the reason it
  /// happened. A negative quantity undoes an earlier write-off, because the
  /// log is append-only.
  Future<void> adjustQty(String lineId, {required num qty, required String reason}) =>
      api.post('/lines/$lineId/adjust', body: {'qty': qty, 'reason': reason});

  Future<void> withdrawAllocation(String id) => api.delete('/allocations/$id');

  /// Adds a packing table to the master (FR-13.1). Allocation can only offer
  /// the tables that exist, so a floor that gained a bench had no way to say so.
  Future<void> createTable({required String tableNo, String? memberId, int sortOrder = 0}) =>
      api.post('/tables', body: {
        'tableNo': tableNo,
        'memberId': memberId,
        'sortOrder': sortOrder,
      });

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

  /* --------------------------------------------------------- seating --- */

  /// Who is on which table for a shift, plus the roster to choose from.
  ///
  /// `seated` false means the rows are the standing plan rather than a
  /// decision anyone has made about today — the screen says so rather than
  /// implying the Supervisor has already been round the floor.
  Future<({
    Map<String, dynamic> shift,
    bool seated,
    List<Map<String, dynamic>> members,
    List<Map<String, dynamic>> tables,
  })> shiftAssignments(String shiftId) async {
    final res = await api.get('/shifts/$shiftId/assignments');
    return (
      shift: _m(res['shift']),
      seated: res['seated'] == true,
      members: (res['members'] as List).map(_m).toList(),
      tables: (res['tables'] as List).map(_m).toList(),
    );
  }

  /// Replace the seating for a shift.
  ///
  /// The whole set at once, because rotation is a rearrangement: two members
  /// swapping tables is one intent, and sending it as two edits would put both
  /// of them on one table halfway through, which the server refuses.
  Future<void> saveShiftAssignments(
    String shiftId,
    List<({String tableNo, String? memberId})> assignments,
  ) async {
    await api.put('/shifts/$shiftId/assignments', body: {
      'assignments': [
        for (final a in assignments)
          {'tableNo': a.tableNo, 'memberId': a.memberId},
      ],
    });
  }

  /* ----------------------------------------------------- part master --- */

  /// FR-3.5 — the master itself: part number, description, MOQ, and nothing
  /// else. [q] matches either the code or the description, because a
  /// storeman looking for a snap ring has the words rather than the code.
  Future<({List<Map<String, dynamic>> parts, int total, int shown})> partMasterList({
    String q = '',
    int limit = 200,
  }) async {
    final res = await api.get('/masters/parts/list', query: {'q': q, 'limit': limit});
    return (
      parts: (res['parts'] as List? ?? const []).map(_m).toList(),
      total: (res['total'] as num? ?? 0).toInt(),
      shown: (res['shown'] as num? ?? 0).toInt(),
    );
  }

  /// Every GRN line that has carried this part: which invoice, when, how
  /// much arrived and how many pouches the MOQ made of it.
  ///
  /// Matched the way the splitter matches — the SAP material minus its last
  /// two characters, falling back to the material as given — so the answer
  /// describes the same lines the pouch counts came from.
  Future<({
    Map<String, dynamic> part,
    List<Map<String, dynamic>> lines,
    Map<String, dynamic> totals,
  })> partMasterLines(String partNo) async {
    final res = await api.get('/masters/parts/${Uri.encodeComponent(partNo)}/lines');
    return (
      part: _m(res['part']),
      lines: (res['lines'] as List? ?? const []).map(_m).toList(),
      totals: _m(res['totals']),
    );
  }

  /* ------------------------------------------------------- operators --- */

  /// Who is standing at each table this shift, by name, keyed by table number.
  ///
  /// A different question from [shiftAssignments], which answers which
  /// *account* is seated where. Two or three people share a bench on a heavy
  /// shift and most of them have no login at all, so these are typed in at the
  /// table rather than picked from the user list.
  Future<Map<String, List<String>>> shiftOperators(String shiftId) async {
    final res = await api.get('/shifts/$shiftId/operators');
    final raw = _m(res['operators']);
    return {
      for (final e in raw.entries)
        e.key: [for (final n in (e.value as List? ?? const [])) '$n'],
    };
  }

  /// FR-3.5 — give one part an MOQ, from the row where the gap was noticed.
  ///
  /// The master arrives as a spreadsheet, which is right for four thousand
  /// parts and wrong for the one a Supervisor is looking at. The server
  /// writes the part number exactly as given — not the stripped family code —
  /// so sibling variants are left alone, and re-splits that part in Open
  /// shifts. Returns how many lines changed.
  Future<int> setPartMoq(String partNo, num moq) async {
    final res = await api.put('/masters/parts/${Uri.encodeComponent(partNo)}/moq',
        body: {'moq': moq});
    return (res['resplit'] as num? ?? 0).toInt();
  }

  /* ------------------------------------------------------- part photos --- */

  /// FR-3.6 — what has been photographed for a part, metadata only. Keyed by
  /// the part number exactly as the GRN carries it, not the master's family
  /// code (migration 235), so a part the master has never heard of can still
  /// have photographs.
  Future<List<PartPhoto>> partPhotos(String partNo) async {
    final res = await api.get('/masters/parts/${Uri.encodeComponent(partNo)}/photos');
    return _list(res['photos'], (m) => PartPhoto(partNo: '${res['partNo']}', raw: m));
  }

  /// One photograph's bytes. Fetched rather than handed to Image.network
  /// because the route wants the bearer token, which an image tag never sends.
  Future<Uint8List> partPhotoBytes(String partNo, String id) =>
      api.download('/masters/parts/${Uri.encodeComponent(partNo)}/photos/${Uri.encodeComponent(id)}');

  /// Adds photographs to a part; never replaces what is there. Returns how
  /// many the server stored.
  Future<int> uploadPartPhotos(
    String partNo,
    List<({String filename, String mime, Uint8List bytes})> photos,
  ) async {
    final form = FormData();
    for (final p in photos) {
      final [type, sub] = p.mime.split('/');
      // The content type is set explicitly: without it Dio sends
      // application/octet-stream and the server refuses anything not image/*.
      form.files.add(MapEntry(
        'photos',
        MultipartFile.fromBytes(p.bytes, filename: p.filename, contentType: DioMediaType(type, sub)),
      ));
    }
    final res = await api.upload('/masters/parts/${Uri.encodeComponent(partNo)}/photos', form);
    return (res['photos'] as List? ?? const []).length;
  }

  /// A Supervisor's correction; the server refuses a Member.
  Future<void> deletePartPhoto(String partNo, String id) =>
      api.delete('/masters/parts/${Uri.encodeComponent(partNo)}/photos/${Uri.encodeComponent(id)}');

  /// Replace the names at one table, and give back what the server stored —
  /// which is not always what was sent: blanks are dropped and a name entered
  /// twice in two different cases is folded into one.
  Future<List<String>> saveTableOperators(
    String shiftId,
    String tableNo,
    List<String> names,
  ) async {
    final res = await api.put(
      '/shifts/$shiftId/tables/$tableNo/operators',
      body: {'names': names},
    );
    return [for (final n in (res['names'] as List? ?? const [])) '$n'];
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
      pendingGrns: ((res['pendingGrns'] as List?) ?? const []).map(_m).toList(),
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

  /// The organisation's settings, with the server's own limits riding along.
  ///
  /// `limits` is not configuration and is never saved back — it is what the
  /// container will do in one request, which the ID Labels screen needs so it
  /// can scope a sheet to something the server will actually render instead of
  /// offering a button that always fails. It is folded into the same object
  /// the screens already read rather than threaded through as a second model.
  Future<SpdConfig> config() async {
    final res = await api.get('/config');
    return SpdConfig({
      ..._m(res['config']),
      if (res['limits'] != null) '_limits': _m(res['limits']),
    });
  }

  Future<SpdConfig> saveConfig(Map<String, dynamic> patch) async {
    final res = await api.put('/config', body: patch);
    return SpdConfig({
      ..._m(res['config']),
      if (res['limits'] != null) '_limits': _m(res['limits']),
    });
  }

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
  LineDetail({
    required this.line,
    required this.txns,
    required this.exceptions,
    required this.allocations,
    this.adjustments = const [],
  });
  final GrnLine line;
  final List<PackingTxn> txns;
  final List<SpdException> exceptions;
  final List<Allocation> allocations;

  /// BR-01 — every write-off against this line, with the reason each carried.
  final List<QtyAdjustment> adjustments;
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
  });
  final int index;
  final int of;
  final num qty;
  final String payload;
  final List<List<bool>> qr;

  bool get isSplit => of > 1;
  String get marker => '$index of $of';
}

class LabelPreview {
  LabelPreview({
    required this.line,
    required this.template,
    required this.labels,
    required this.alreadyPrinted,
    this.printedOn,
  });
  final GrnLine line;
  final String template;
  final List<LabelUnit> labels;
  final bool alreadyPrinted;

  /// 'YYYY-MM-DD' — the date a print pressed now would carry, in the floor's
  /// time zone. The server stamps the sheet with the same when it is built.
  final String? printedOn;

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
    required this.pendingGrns,
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

  /// Every GRN still carrying unpacked quantity, oldest first — and across
  /// shifts, not just the one on screen. A GRN left unfinished yesterday is
  /// exactly the one that needs chasing today, and a shift-scoped figure is
  /// the one view that would never show it.
  final List<Map<String, dynamic>> pendingGrns;

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
