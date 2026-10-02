import '../core/format.dart';

/* ============================================================================
   Typed views over the API's JSON. Every model keeps the raw map so a field the
   backend adds later is reachable without a round of plumbing, but the fields
   the screens actually read are named and coerced once, here — which is what
   stops `grn_qty` being a String in one widget and a num in the next.
   ========================================================================== */

class SpdUser {
  SpdUser(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id']}';
  String get name => '${raw['name'] ?? ''}';
  String get empCode => '${raw['emp_code'] ?? ''}';
  String get role => '${raw['role'] ?? ''}';
  String get email => '${raw['email'] ?? ''}';
  String get device => '${raw['device'] ?? ''}';
  String? get tableNo => raw['table_no'] as String?;
  bool get active => raw['active'] != false;
  String get access => '${raw['access'] ?? ''}';

  /// The nav/route key the app uses for this role.
  String get roleKey => switch (role) {
        'Supervisor' => 'supervisor',
        'Member' => 'member',
        'Administrator' => 'admin',
        'Management' => 'viewer',
        _ => 'viewer',
      };
}

class Shift {
  Shift(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id']}';
  String get label => '${raw['label'] ?? ''}';
  String get date => '${raw['shift_date'] ?? ''}'.split('T').first;
  String get status => '${raw['status'] ?? 'Open'}';
  bool get finalised => status == 'Finalised';
  String? get finalByName => raw['final_by_name'] as String?;
  dynamic get finalAt => raw['final_at'];
  int get resubmits => intOf(raw['resubmits']);

  /// What the shift picker shows: "Shift A · 09-Sep-2026 · Open".
  String get pickerLabel => '$label · $status';
}

class GrnLine {
  GrnLine(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id']}';
  String get invoiceNo => '${raw['invoice_no'] ?? ''}';
  String get partNo => '${raw['part_no'] ?? ''}';
  String get partDesc => '${raw['part_desc'] ?? ''}';
  String get uom => '${raw['uom'] ?? ''}';
  String get vendor => '${raw['vendor'] ?? ''}';
  String get grnDate => '${raw['grn_date'] ?? ''}';
  num get grnQty => numOf(raw['grn_qty']);

  /// FR-3.5 — the pack size the line's labels are split by, when the GRN
  /// export carried one.
  num? get moq => raw['moq'] == null ? null : numOf(raw['moq']);

  /// FR-3.5 — how many labels this line prints. The server derives it from the
  /// one implementation of the split rather than the console recomputing it,
  /// because a count that disagrees with the sheet is how label stock is
  /// ordered short.
  int get labelCount => raw['label_count'] == null ? 1 : intOf(raw['label_count']);
  num get packed => numOf(raw['packed']);
  num get pending => numOf(raw['pending']);
  int get pouches => intOf(raw['pouches']);
  int get boxes => intOf(raw['boxes']);
  int get txns => intOf(raw['txns']);
  int get allocationCount => intOf(raw['allocations']);
  String get status => '${raw['status'] ?? 'Pending'}';

  /// BR-01's third term — the quantity written off as never coming.
  ///
  /// It is deliberately not folded into [packed]: 95 packed and 5 short is not
  /// 100 packed, and the member's productivity is the work they did. Only
  /// [pending] sees the sum, and the server is the one that computes it.
  num get adjusted => numOf(raw['adjusted']);
  int get adjustmentCount => intOf(raw['adjustments']);
  bool get hasWriteOff => adjusted != 0;

  /// FR-3.1 — what the label prints for packer and packing date.
  ///
  /// Both are only known once the line has been allocated: the packer is
  /// whoever staffs the tables it went to, and the date is the shift's. The
  /// server sends them with the line detail and the label preview, so an
  /// unallocated line gives null and the label prints a dash.
  String? get packer {
    final v = raw['packer'];
    return v == null || '$v'.isEmpty ? null : '$v';
  }

  String? get packedOn {
    final v = raw['packed_on'];
    return v == null || '$v'.isEmpty ? null : '$v';
  }

  /// The member's own share of a split line, when there is one (BR-04).
  num? get myShare => raw['my_share'] == null ? null : numOf(raw['my_share']);

  List<String> get tables =>
      (raw['tables'] as List?)?.map((e) => '$e').toList() ?? const [];

  String get tablesLabel => tables.isEmpty ? '—' : tables.join(', ');
}

class PackingTxn {
  PackingTxn(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id']}';
  String get lineId => '${raw['line_id']}';
  String get tableNo => '${raw['table_no'] ?? ''}';
  String get memberId => '${raw['member_id'] ?? ''}';
  String get memberName => '${raw['member_name'] ?? ''}';
  dynamic get startAt => raw['start_at'];
  dynamic get submitAt => raw['submit_at'];
  num get qty => numOf(raw['qty']);
  int get pouches => intOf(raw['pouches']);
  int get boxes => intOf(raw['boxes']);
  String get status => '${raw['status'] ?? ''}';
  bool get running => status == 'Started';

  String get partNo => '${raw['part_no'] ?? ''}';
  String get partDesc => '${raw['part_desc'] ?? ''}';
  String get invoiceNo => '${raw['invoice_no'] ?? ''}';
  String get uom => '${raw['uom'] ?? ''}';
  num get grnQty => numOf(raw['grn_qty']);

  Duration? get elapsed => between(startAt, submitAt);
}

class SpdException {
  SpdException(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id']}';
  String get lineId => '${raw['line_id'] ?? ''}';
  String get type => '${raw['type'] ?? ''}';
  String get detail => '${raw['detail'] ?? ''}';
  String get remarks => '${raw['remarks'] ?? ''}';
  dynamic get createdAt => raw['created_at'];
  bool get resolved => raw['resolved_at'] != null;

  String get partNo => '${raw['part_no'] ?? ''}';
  String get invoiceNo => '${raw['invoice_no'] ?? ''}';
  num get grnQty => numOf(raw['grn_qty']);
  String get uom => '${raw['uom'] ?? ''}';

  /// BR-03 — an exception with neither a remark nor a resolution blocks the
  /// Supervisor's final submission.
  bool get blocksFinalisation => !resolved && remarks.isEmpty;
}

class TableStat {
  TableStat(this.raw);
  final Map<String, dynamic> raw;

  String get tableNo => '${raw['table_no']}';
  String? get memberId => raw['member_id'] as String?;
  String? get memberName => raw['member_name'] as String?;
  String get status => '${raw['status'] ?? 'Free'}';
  num get packed => numOf(raw['packed']);
  num get pending => numOf(raw['pending']);
  int get pouches => intOf(raw['pouches']);
  int get boxes => intOf(raw['boxes']);
  int get txns => intOf(raw['txns']);
  int get lines => intOf(raw['lines']);
  int get allocatedLines => intOf(raw['allocated_lines']);
  num get allocatedGrn => numOf(raw['allocated_grn']);
  num get allocatedPacked => numOf(raw['allocated_packed']);

  List<GrnLine> get allocatedLineRows =>
      (raw['lines'] is List ? raw['lines'] as List : const [])
          .map((e) => GrnLine(Map<String, dynamic>.from(e as Map)))
          .toList();

  int get progressPct => pct(allocatedPacked, allocatedGrn);
}

class MemberStat {
  MemberStat(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id']}';
  String get name => '${raw['name'] ?? ''}';
  String get empCode => '${raw['emp_code'] ?? ''}';
  String? get tableNo => raw['table_no'] as String?;
  int get txns => intOf(raw['txns']);
  num get qty => numOf(raw['qty']);
  int get pouches => intOf(raw['pouches']);
  int get boxes => intOf(raw['boxes']);
  int get lines => intOf(raw['lines']);
  dynamic get lastSubmit => raw['last_submit'];
}

class ShiftStats {
  ShiftStats(this.raw);
  final Map<String, dynamic> raw;

  factory ShiftStats.empty() => ShiftStats(const {});

  int get lines => intOf(raw['lines']);
  int get linesPacked => intOf(raw['linesPacked']);
  num get grn => numOf(raw['grn']);
  num get packed => numOf(raw['packed']);
  num get pending => numOf(raw['pending']);
  int get pouches => intOf(raw['pouches']);
  int get boxes => intOf(raw['boxes']);
  int get exc => intOf(raw['exc']);
  int get excOpen => intOf(raw['excOpen']);
  int get txns => intOf(raw['txns']);

  int get completionPct => pct(packed, grn);
}

class GrnBatch {
  GrnBatch(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id']}';
  String get fileName => '${raw['file_name'] ?? ''}';
  String get shiftLabel => '${raw['shift_label'] ?? ''}';
  dynamic get uploadedAt => raw['uploaded_at'];
  String get uploadedByName => '${raw['uploaded_by_name'] ?? ''}';
  int get rowCount => intOf(raw['row_count']);
  int get rejectedCount => intOf(raw['rejected_count']);
  String get status => '${raw['status'] ?? ''}';
}

class Allocation {
  Allocation(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id']}';
  String get lineId => '${raw['line_id']}';
  String get tableNo => '${raw['table_no']}';
  num? get qty => raw['qty'] == null ? null : numOf(raw['qty']);
  String get reason => '${raw['reason'] ?? ''}';
  dynamic get allocatedAt => raw['allocated_at'];
  String get allocatedByName => '${raw['allocated_by_name'] ?? ''}';
  String get partNo => '${raw['part_no'] ?? ''}';
  String get invoiceNo => '${raw['invoice_no'] ?? ''}';
  num get grnQty => numOf(raw['grn_qty']);
}

/// One table's share of a line, as the allocation dialog builds it.
///
/// A null [qty] means the table works the line without a stated share — which
/// is what a whole-line allocation has always sent, and what several tables
/// hold when they share a queue.
class TableShare {
  const TableShare(this.tableNo, [this.qty]);
  final String tableNo;
  final num? qty;
}

/// BR-01 — one write-off against a line's outstanding quantity.
///
/// A positive [qty] closes the remainder out, a negative one restores it: the
/// log is append-only, so a write-off entered against the wrong line is undone
/// by its opposite rather than deleted.
class QtyAdjustment {
  QtyAdjustment(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id']}';
  String get lineId => '${raw['line_id']}';
  num get qty => numOf(raw['qty']);
  String get reason => '${raw['reason'] ?? ''}';
  dynamic get createdAt => raw['created_at'];
  String get createdByName => '${raw['created_by_name'] ?? ''}';

  /// True when this entry gave quantity back rather than writing it off.
  bool get isRestore => qty < 0;
}

class HourlyReport {
  HourlyReport(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id']}';
  String get shiftLabel => '${raw['shift_label'] ?? ''}';
  dynamic get generatedAt => raw['generated_at'];
  num get packed => numOf(raw['packed_qty']);
  num get pending => numOf(raw['pending_qty']);
  String get tablesSummary => '${raw['tables_summary'] ?? ''}';
  int get exceptionsCount => intOf(raw['exceptions_count']);
  String get emailedTo => '${raw['emailed_to'] ?? ''}';
  String get emailStatus => '${raw['email_status'] ?? ''}';

  Map<String, dynamic> get body =>
      raw['body_json'] is Map ? Map<String, dynamic>.from(raw['body_json'] as Map) : const {};

  List<Map<String, dynamic>> get members =>
      (body['members'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? const [];
}

class MisSnapshot {
  MisSnapshot(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id']}';
  String get shiftLabel => '${raw['shift_label'] ?? ''}';
  dynamic get generatedAt => raw['generated_at'];
  int get linesPacked => intOf(raw['lines_packed']);
  int get pouches => intOf(raw['pouches']);
  int get boxes => intOf(raw['boxes']);
  num get packed => numOf(raw['packed_qty']);
  num get pending => numOf(raw['pending_qty']);
  bool get provisional => raw['provisional'] == true;
}

class MisRow {
  MisRow(this.raw);
  final Map<String, dynamic> raw;

  String get key => '${raw['key'] ?? ''}';
  String get label => '${raw['label'] ?? raw['key'] ?? ''}';
  String get invoiceNo => '${raw['invoice_no'] ?? ''}';
  String get partNo => '${raw['part_no'] ?? ''}';
  String get partDesc => '${raw['part_desc'] ?? ''}';
  String? get memberName => raw['member_name'] as String?;
  String? get tableNo => raw['table_no'] as String?;
  num get grnQty => numOf(raw['grn_qty']);
  num get packed => numOf(raw['packed']);
  num get pending => numOf(raw['pending']);
  num get qty => numOf(raw['qty']);
  int get pouches => intOf(raw['pouches']);
  int get boxes => intOf(raw['boxes']);
  int get lines => intOf(raw['lines']);
  int get txns => intOf(raw['txns']);
  String get status => '${raw['status'] ?? ''}';
  List<String> get tables => (raw['tables'] as List?)?.map((e) => '$e').toList() ?? const [];
}

class AuditEntry {
  AuditEntry(this.raw);
  final Map<String, dynamic> raw;

  dynamic get at => raw['at'];
  String? get actorName => raw['actor_name'] as String?;
  String get action => '${raw['action'] ?? ''}';
  String get reference => '${raw['reference'] ?? ''}';
  String get detail => '${raw['detail'] ?? ''}';
  String get before => '${raw['before_value'] ?? ''}';
  String get after => '${raw['after_value'] ?? ''}';

  bool get bySystem => actorName == null;
}

class LabelPrint {
  LabelPrint(this.raw);
  final Map<String, dynamic> raw;

  String get partNo => '${raw['part_no'] ?? ''}';
  String get invoiceNo => '${raw['invoice_no'] ?? ''}';
  int get copies => intOf(raw['copies']);
  dynamic get printedAt => raw['printed_at'];
  String get printedByName => '${raw['printed_by_name'] ?? ''}';
  String get reason => '${raw['reason'] ?? ''}';
}

/// FR-13.2 — the Admin-editable parameters.
class SpdConfig {
  SpdConfig(this.raw);
  final Map<String, dynamic> raw;

  factory SpdConfig.empty() => SpdConfig(const {
        'threshold': 50,
        'hourly': 60,
        'refresh': 60,
        'emails': <String>[],
        'labelTpl': 'SPD Standard 100×60',
        'grnCols': <String>[],
        'grnColsOptional': <String>[],
      });

  int get threshold => intOf(raw['threshold']);
  int get hourly => intOf(raw['hourly']);
  int get refresh => intOf(raw['refresh']);
  String get labelTpl => '${raw['labelTpl'] ?? ''}';
  List<String> get emails => (raw['emails'] as List?)?.map((e) => '$e').toList() ?? const [];
  List<String> get grnCols => (raw['grnCols'] as List?)?.map((e) => '$e').toList() ?? const [];

  /// NFR-6.1 — columns read when the export carries them and ignored when it
  /// does not, MOQ being the first of them (FR-3.5). Held separately from
  /// [grnCols] because a required MOQ would reject every export produced
  /// before the split rule existed.
  List<String> get grnColsOptional =>
      (raw['grnColsOptional'] as List?)?.map((e) => '$e').toList() ?? const [];
}

/// The live warning the pack screen shows as a quantity is typed (FR-7.2).
class SubmitHint {
  SubmitHint(this.raw);
  final Map<String, dynamic> raw;

  String get tone => '${raw['tone'] ?? 'info'}';
  String get title => '${raw['title'] ?? ''}';
  String get message => '${raw['message'] ?? ''}';
}
