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

/// Renders every screen with representative data, in both themes and at both
/// the desktop and the table-tablet width.
///
/// The widget gallery covers the components; this covers how the screens
/// compose them — the responsive grids, the wide tables, the split panes. Those
/// only misbehave at a particular width with a particular amount of content,
/// which is exactly what a release build will not tell you about and a
/// screenshot of one viewport will not show.
void main() {
  /* ------------------------------------------------------------ fixtures */

  final shift = {
    'id': 'A-2026-09-09',
    'label': 'Shift A · 09-Sep-2026',
    'shift_date': '2026-09-09',
    'status': 'Open',
    'resubmits': 0,
    'line_count': 24,
  };

  Map<String, dynamic> line(String id, String part, {num packed = 0, String status = 'Allocated'}) => {
        'id': id,
        'invoice_no': 'INV-77001',
        'part_no': part,
        'part_desc': 'Front Bumper Bracket LH — a long description to stretch the column',
        'uom': 'NOS',
        'vendor': 'DynaFast Fasteners',
        'grn_date': '2026-09-09',
        'grn_qty': 270,
        // FR-3.5 — a split line, so the screens render the marker and the sheet
        // count is a label total rather than a line count.
        'moq': 100,
        'label_count': 3,
        'packed': packed,
        'pending': 270 - packed,
        'pouches': 12,
        'boxes': 3,
        'txns': 1,
        'open_exceptions': status == 'Exception' ? 1 : 0,
        'running': 0,
        'allocations': 1,
        'label_copies': 1,
        'tables': ['T-01', 'T-02'],
        'member_ids': ['tm.ssingh'],
        'status': status,
        'my_share': 135,
        'split_reason': 'bulky line, dispatch cut-off',
      };

  final stats = {
    'lines': 24, 'linesPacked': 7, 'grn': 6040, 'packed': 2260, 'pending': 3780,
    'pouches': 86, 'boxes': 24, 'exc': 3, 'excOpen': 3, 'txns': 12,
  };

  final tableStat = {
    'table_no': 'T-01', 'member_id': 'tm.ssingh', 'member_name': 'Sandeep Singh',
    'status': 'Occupied', 'packed': 330, 'pending': 80, 'pouches': 17, 'boxes': 4,
    'txns': 2, 'lines': 2, 'allocated_lines': 3, 'completed_lines': 1,
    'allocated_grn': 700, 'allocated_packed': 330,
  };

  final memberStat = {
    'id': 'tm.ssingh', 'name': 'Sandeep Singh', 'emp_code': 'EMP-4412', 'table_no': 'T-01',
    'txns': 2, 'qty': 330, 'pouches': 17, 'boxes': 4, 'lines': 2,
    'last_submit': '2026-09-09T10:31:25.000Z',
  };

  final txn = {
    'id': 'TX0108', 'line_id': 'L0001', 'table_no': 'T-01', 'member_id': 'tm.ssingh',
    'member_name': 'Sandeep Singh', 'start_at': '2026-09-09T10:05:25.000Z',
    'submit_at': '2026-09-09T10:31:25.000Z', 'qty': 60, 'pouches': 5, 'boxes': 1,
    'status': 'Submitted', 'part_no': '67861-WSR', 'part_desc': 'Door Weatherstrip Rear',
    'invoice_no': 'INV-77002', 'uom': 'NOS', 'grn_qty': 140,
  };

  final exception = {
    'id': 'EX013', 'txn_id': 'TX0112', 'line_id': 'L0011', 'type': 'Excess Entry',
    'detail': 'Cumulative packed 130 exceeds GRN quantity 110 for 74410-BTR (INV-77003).',
    'remarks': '', 'created_at': '2026-09-09T11:51:00.000Z', 'resolved_at': null,
    'part_no': '74410-BTR', 'invoice_no': 'INV-77003', 'grn_qty': 110, 'uom': 'NOS',
  };

  final config = {
    'threshold': 50, 'hourly': 60, 'refresh': 60,
    'emails': ['rajesh.menon@vistarlogitek.com', 'spd.shiftreport@vistarlogitek.com'],
    'labelTpl': 'SPD Standard 100×60',
    'grnCols': ['Invoice No.', 'Part Number', 'Part Description', 'GRN Quantity', 'UOM', 'Vendor', 'GRN Date'],
    'grnColsOptional': ['MOQ'],
  };

  final user = {
    'id': 'sup.rmenon', 'name': 'Rajesh Menon', 'emp_code': 'EMP-1002', 'role': 'Supervisor',
    'email': 'rajesh.menon@vistarlogitek.com', 'device': 'SUP-DESK-01', 'active': true,
    'table_no': null, 'access': 'GRN upload · labels · allocation · review · final submission',
  };

  final lines = [
    GrnLine(line('L0001', '90210-ABX', packed: 270, status: 'Completed')),
    GrnLine(line('L0002', '90211-ABX', packed: 60, status: 'In Progress')),
    GrnLine(line('L0003', '82111-WHM', status: 'Exception')),
  ];

  final linesPage = LinesPage(
    lines: lines,
    invoices: const ['INV-77001', 'INV-77002'],
    vendors: const ['DynaFast Fasteners', 'Kranti Pressings'],
  );

  /* ------------------------------------------------- provider overrides */

  // Built once: an override is an immutable descriptor, so it is safe to share
  // across tests. The type is inferred because riverpod does not export it.
  final overrides = [
        repositoryProvider.overrideWithValue(_FakeRepo()),
        shiftsProvider.overrideWith((ref) async => [Shift(shift)]),
        dashboardProvider.overrideWith((ref) async => DashboardPage(
              shift: Shift(shift),
              stats: ShiftStats(stats),
              tables: [TableStat(tableStat)],
              members: [MemberStat(memberStat)],
              lines: lines,
              batchId: 'GRN-0909-01',
              hourlyCount: 3,
              refreshSeconds: 60,
              generatedAt: DateTime(2026, 9, 9, 12, 44),
            )),
        linesProvider.overrideWith((ref) async => linesPage),
        grnBatchesProvider.overrideWith((ref) async => [
              GrnBatch({
                'id': 'GRN-0909-01', 'file_name': 'GRN_SAP_EXPORT_09SEP_S1.xlsx',
                'shift_id': 'A-2026-09-09', 'shift_label': 'Shift A · 09-Sep-2026',
                'uploaded_at': '2026-09-09T08:12:40.000Z', 'uploaded_by_name': 'Rajesh Menon',
                'row_count': 24, 'rejected_count': 0, 'status': 'Imported',
              }),
            ]),
        tablesProvider.overrideWith((ref) async => [
              TableStat({...tableStat, 'lines': [line('L0001', '90210-ABX')]}),
              TableStat({...tableStat, 'table_no': 'T-08', 'member_name': null, 'status': 'Free', 'allocated_lines': 0, 'lines': []}),
            ]),
        allocationsProvider.overrideWith((ref) async => [
              Allocation({
                'id': 'AL051', 'line_id': 'L0001', 'table_no': 'T-01', 'qty': null,
                'reason': '', 'allocated_at': '2026-09-09T08:40:00.000Z',
                'allocated_by_name': 'Rajesh Menon', 'part_no': '90210-ABX',
                'invoice_no': 'INV-77001', 'grn_qty': 270,
              }),
            ]),
        labelLogProvider.overrideWith((ref) async => [
              LabelPrint({
                'part_no': '90210-ABX', 'invoice_no': 'INV-77001', 'copies': 1,
                'printed_at': '2026-09-09T08:25:00.000Z', 'printed_by_name': 'Rajesh Menon',
                'reason': '',
              }),
            ]),
        reviewProvider.overrideWith((ref) async => ReviewPage(
              shift: Shift(shift),
              stats: ShiftStats(stats),
              exceptions: [SpdException(exception)],
              tables: [TableStat(tableStat)],
              members: [MemberStat(memberStat)],
              canFinalise: false,
            )),
        hourlyProvider.overrideWith((ref) async => HourlyPage(
              reports: [
                HourlyReport({
                  'id': 'HR-03', 'shift_id': 'A-2026-09-09', 'shift_label': 'Shift A · 09-Sep-2026',
                  'generated_at': '2026-09-09T12:00:00.000Z', 'packed_qty': 3140,
                  'pending_qty': 3240, 'tables_summary': 'T-01–T-06 occupied',
                  'exceptions_count': 1, 'emailed_to': 'rajesh.menon@vistarlogitek.com',
                  'email_status': 'Sent', 'body_json': {'members': []},
                }),
              ],
              interval: 60,
              emails: const ['rajesh.menon@vistarlogitek.com'],
            )),
        misProvider.overrideWith((ref) async => MisPage(
              shift: Shift(shift),
              stats: ShiftStats(stats),
              dim: 'line',
              rows: [
                MisRow({
                  'key': 'L0001', 'invoice_no': 'INV-77001', 'part_no': '90210-ABX',
                  'part_desc': 'Front Bumper Bracket LH', 'grn_qty': 270, 'packed': 270,
                  'pending': 0, 'pouches': 12, 'boxes': 3, 'tables': ['T-01'],
                  'status': 'Completed', 'qty': 270, 'lines': 1, 'txns': 1,
                }),
              ],
              snapshots: [
                MisSnapshot({
                  'id': 'MIS-0909', 'shift_label': 'Shift A · 09-Sep-2026',
                  'generated_at': '2026-09-09T17:42:10.000Z', 'lines_packed': 7,
                  'pouches': 86, 'boxes': 24, 'packed_qty': 2260, 'pending_qty': 3780,
                  'provisional': false,
                }),
              ],
              provisional: true,
            )),
        facetsProvider.overrideWith((ref) async => Facets(
              invoices: const ['INV-77001'],
              vendors: const ['DynaFast Fasteners'],
              tables: const ['T-01', 'T-08'],
              members: const [{'id': 'tm.ssingh', 'name': 'Sandeep Singh'}],
            )),
        auditProvider.overrideWith((ref) async => AuditPage(
              entries: [
                AuditEntry({
                  'at': '2026-09-09T12:38:40.000Z', 'actor_name': 'Rajesh Menon',
                  'action': 'Packing Submit', 'reference': '67861-WSR',
                  'detail': 'INV-77002 · qty 40 · 4 pouches · 1 boxes · T-01 · 0m',
                  'before_value': 'Started', 'after_value': 'Submitted',
                }),
                AuditEntry({
                  'at': '2026-09-09T12:00:00.000Z', 'actor_name': null,
                  'action': 'Hourly Report', 'reference': 'HR-03', 'detail': 'Emailed',
                  'before_value': '—', 'after_value': 'sent',
                }),
              ],
              actions: const ['Packing Submit', 'Hourly Report'],
            )),
        usersProvider.overrideWith((ref) async => [SpdUser(user)]),
        configProvider.overrideWith((ref) async => SpdConfig(config)),
        notificationsProvider.overrideWith((ref) async => [
              {'severity': 'bad', 'text': '3 exceptions awaiting supervisor remarks'},
            ]),
        myQueueProvider.overrideWith((ref) async => MemberQueue(
              tableNo: 'T-01',
              shift: Shift(shift),
              locked: false,
              lines: lines,
              running: null,
              stats: MemberStat(memberStat),
              threshold: 50,
            )),
        myHistoryProvider.overrideWith((ref) async => [PackingTxn(txn)]),
  ];

  /* ---------------------------------------------------------- the screens */

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

  // 1440 is the supervisor's monitor; 800 is a table tablet, below the 980 and
  // 1100 breakpoints where the grids and split panes change shape.
  const widths = {'desktop': 1440.0, 'tablet': 800.0};

  for (final screen in screens.entries) {
    for (final w in widths.entries) {
      for (final light in [false, true]) {
        testWidgets('${screen.key} renders at ${w.key} in ${light ? 'light' : 'dark'}', (tester) async {
          tester.view.physicalSize = Size(w.value, 1600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(ProviderScope(
            overrides: overrides,
            child: MaterialApp(
              theme: buildTheme(light: light),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(26),
                  child: screen.value(),
                ),
              ),
            ),
          ));

          // let the overridden futures resolve
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

/// Only the two methods screens call on the repository directly, rather than
/// through a provider: the login roster and the per-tile label preview.
class _FakeRepo extends SpdRepository {
  _FakeRepo() : super(ApiClient(baseUrl: 'http://127.0.0.1:1/api'));

  @override
  Future<List<Map<String, dynamic>>> members() async =>
      [{'id': 'tm.ssingh', 'name': 'Sandeep Singh', 'emp_code': 'EMP-4412', 'table_no': 'T-01'}];

  @override
  Future<LabelPreview> labelPreview(String lineId) async => LabelPreview(
        line: GrnLine({
          'id': lineId, 'invoice_no': 'INV-77001', 'part_no': '90210-ABX',
          'part_desc': 'Front Bumper Bracket LH', 'uom': 'NOS', 'vendor': 'DynaFast Fasteners',
          'grn_date': '2026-09-09', 'grn_qty': 270, 'packed': 0, 'pending': 270,
          'tables': <String>[],
        }),
        template: 'SPD Standard 100×60',
        labels: [
          LabelUnit(
            index: 1, of: 1, qty: 270,
            payload: '90210-ABX|INV-77001|270',
            qr: List.generate(25, (r) => List.generate(25, (c) => (r + c).isEven)),
          ),
        ],
        alreadyPrinted: true,
      );
}
