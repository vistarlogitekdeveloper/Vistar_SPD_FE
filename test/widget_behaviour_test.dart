import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spd_frontend/core/api.dart';
import 'package:spd_frontend/core/theme.dart';
import 'package:spd_frontend/data/providers.dart';
import 'package:spd_frontend/data/repository.dart';
import 'package:spd_frontend/models/models.dart';
import 'package:spd_frontend/ui/widgets/common.dart';
import 'package:spd_frontend/ui/widgets/label_card.dart';
import 'package:spd_frontend/ui/widgets/line_detail.dart';
import 'package:spd_frontend/ui/widgets/pdf_preview_dialog.dart';

/// What `widget_gallery_test.dart` cannot tell you.
///
/// The gallery proves every widget *mounts*. That catches the assert-only
/// failures a release build hides, and nothing else — a `GradButton` whose
/// `onPressed` never reaches its gesture detector renders pixel for pixel like
/// one that works, a `SpdTable` that overflows its row padding looks correct
/// until the viewport narrows, and the modals and toasts the audit found
/// untouched are the parts a supervisor actually operates.
///
/// So this file presses things, narrows the viewport, and opens the dialogs.
void main() {
  /* ---- harness -------------------------------------------------------- */

  Future<void> pumpIn(WidgetTester tester, Widget child,
      {bool light = false, double width = 1440, double height = 900}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(light: light),
      home: Scaffold(body: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(16), child: child))),
    ));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Overflow is reported through FlutterError during paint, which the test
  /// binding records — so this is what proves a layout actually fits.
  void expectNoOverflow(WidgetTester tester, String what) {
    final err = tester.takeException();
    expect(err, isNull, reason: '$what: $err');
  }

  /* ===================================================================== */
  /* 1. the callbacks reach the gesture detector                           */
  /* ===================================================================== */

  group('a dropped callback renders identically — so press everything', () {
    testWidgets('GradButton fires, and stays inert when disabled', (tester) async {
      var taps = 0;
      await pumpIn(tester, GradButton(label: 'Submit', onPressed: () => taps++));
      await tester.tap(find.text('Submit'));
      expect(taps, 1);

      await pumpIn(tester, const GradButton(label: 'Submit'));
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(taps, 1, reason: 'a null onPressed must not somehow fire');
      expectNoOverflow(tester, 'GradButton disabled');
    });

    testWidgets('GhostButton fires', (tester) async {
      var taps = 0;
      await pumpIn(tester, GhostButton(label: 'Excel', onPressed: () => taps++));
      await tester.tap(find.text('Excel'));
      expect(taps, 1);
    });

    testWidgets('IconTile fires', (tester) async {
      var taps = 0;
      await pumpIn(tester, IconTile(icon: Icons.refresh_rounded, onTap: () => taps++));
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      expect(taps, 1);
    });

    testWidgets('SpdChip fires', (tester) async {
      var taps = 0;
      await pumpIn(tester, SpdChip('Invoice No.', onTap: () => taps++));
      await tester.tap(find.text('Invoice No.'));
      expect(taps, 1);
    });

    testWidgets('DropZone fires — the GRN upload has no other entry point', (tester) async {
      var taps = 0;
      await pumpIn(tester, DropZone(
        title: 'Drop the GRN export', subtitle: 'or click to browse', onTap: () => taps++));
      await tester.tap(find.text('Drop the GRN export'));
      expect(taps, 1);
    });

    testWidgets('FilterBar shows Reset only when it does something', (tester) async {
      var resets = 0;
      await pumpIn(tester, FilterBar(
        onReset: () => resets++,
        children: const [Field(label: 'Search', bottom: 0, child: TextField())],
      ));
      expect(find.text('Reset'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      expect(resets, 1);

      await pumpIn(tester, const FilterBar(
        children: [Field(label: 'Search', bottom: 0, child: TextField())]));
      expect(find.text('Reset'), findsNothing,
          reason: 'a Reset with no handler is a button that lies');
    });

    testWidgets('SpdDropdown reports the chosen value', (tester) async {
      String? chosen;
      await pumpIn(tester, SpdDropdown<String>(
        value: 'a',
        items: const [
          DropdownMenuItem(value: 'a', child: Text('All invoices')),
          DropdownMenuItem(value: 'b', child: Text('INV-77001')),
        ],
        onChanged: (v) => chosen = v,
      ));
      await tester.tap(find.text('All invoices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('INV-77001').last);
      await tester.pumpAndSettle();
      expect(chosen, 'b');
    });

    testWidgets('an SpdRow drill-down fires for the row that was tapped', (tester) async {
      final tapped = <String>[];
      await pumpIn(tester, SpdTable(
        columns: const [SpdCol('Invoice')],
        rows: [
          SpdRow([cell('INV-77001')], onTap: () => tapped.add('INV-77001')),
          SpdRow([cell('INV-77002')], onTap: () => tapped.add('INV-77002')),
        ],
      ));
      await tester.tap(find.text('INV-77002'));
      expect(tapped, ['INV-77002']);
    });
  });

  /* ===================================================================== */
  /* 2. SpdTable — the layout that broke three different ways              */
  /* ===================================================================== */

  group('SpdTable', () {
    final wideColumns = [
      for (var i = 0; i < 10; i++) SpdCol('Column $i', width: 200),
    ];

    testWidgets('shrink-wraps inside an unbounded parent', (tester) async {
      // A Flexible inside a shrink-wrapping Column throws only under an assert,
      // so a release build renders this and `flutter run` does not.
      await pumpIn(tester, Column(children: [
        const Text('above'),
        SpdTable(
          columns: const [SpdCol('Invoice'), SpdCol('Qty', right: true)],
          rows: [for (var i = 0; i < 20; i++) SpdRow([cell('INV-$i'), monoCell('$i')])],
        ),
        const Text('below'),
      ]));
      expectNoOverflow(tester, 'unbounded SpdTable');
      expect(find.text('below'), findsOneWidget);
    });

    testWidgets('fills and scrolls when its height is bounded', (tester) async {
      await pumpIn(tester, SizedBox(
        height: 300,
        child: SpdTable(
          maxHeight: 300,
          columns: const [SpdCol('Invoice')],
          rows: [for (var i = 0; i < 60; i++) SpdRow([cell('INV-$i')])],
        ),
      ));
      expectNoOverflow(tester, 'bounded SpdTable');
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('scrolls sideways rather than overflowing when columns exceed the viewport',
        (tester) async {
      await pumpIn(tester, SpdTable(
        columns: wideColumns,
        rows: [SpdRow([for (var i = 0; i < 10; i++) cell('cell $i')])],
      ), width: 700);
      expectNoOverflow(tester, 'over-wide SpdTable');

      final scrollables = find.byType(Scrollable).evaluate();
      expect(scrollables.any((e) => (e.widget as Scrollable).axisDirection == AxisDirection.right),
          isTrue, reason: 'the table must offer a horizontal scroll, not clip the columns');
    });

    testWidgets('accounts for the row padding when deciding whether columns fit', (tester) async {
      // Each row carries EdgeInsets.symmetric(horizontal: 16). Columns summing
      // to exactly the viewport width therefore do *not* fit, and treating them
      // as if they did overflowed by precisely 32px.
      await pumpIn(tester, SizedBox(
        width: 600,
        child: SpdTable(
          columns: const [SpdCol('A', width: 300), SpdCol('B', width: 300)],
          rows: [SpdRow([cell('a'), cell('b')])],
        ),
      ), width: 640);
      expectNoOverflow(tester, 'columns summing to exactly the width');
    });

    testWidgets('shows the empty message rather than a bare frame', (tester) async {
      await pumpIn(tester, const SpdTable(
        columns: [SpdCol('Invoice')], rows: [], emptyMessage: 'No records match the filter.'));
      expect(find.text('No records match the filter.'), findsOneWidget);
    });
  });

  /* ===================================================================== */
  /* 3. narrow viewports — where the 0.4px overflows live                  */
  /* ===================================================================== */

  group('nothing overflows on a tablet or a phone', () {
    final specimens = <String, Widget>{
      'PageHeader': const PageHeader(
        crumb: 'Overview ·',
        accent: 'Live Dashboard',
        title: 'SPD pre-packing dashboard',
        blurb: 'A blurb long enough to need a second line on a narrow screen.',
        actions: [GhostButton(label: 'Refresh'), GradButton(label: 'Finalise shift')],
      ),
      'KpiCard': const KpiCard(
        icon: Icons.storage_rounded, value: '6,040',
        caption: 'Total GRN quantity across every invoice in the shift',
        extra: DeltaChip('37%')),
      'AlertBox': const AlertBox(
        tone: AlertTone.bad,
        title: 'Warning — exceeds GRN quantity',
        message: 'Cumulative packed would be 160 against a GRN quantity of 140.'),
      'BarRow': const BarRow(
        label: Text('T-01 · Sandeep Singh'),
        value: '330 qty · 2 lines · Occupied', percent: 60),
      'FilterBar': FilterBar(onReset: () {}, children: const [
        Field(label: 'Search', bottom: 0, child: TextField()),
        Field(label: 'Invoice', bottom: 0, child: TextField()),
        Field(label: 'Status', bottom: 0, child: TextField()),
      ]),
      'EmailPreview': const EmailPreview(
        subject: 'Hourly Status · Shift A · 09-Sep-2026',
        meta: 'To: spd-supervisors@vistarlogitek.com, mis@vistarlogitek.com',
        content: Text('body')),
      'ResponsiveGrid g4': const ResponsiveGrid(columns: 4, children: [
        KpiCard(icon: Icons.storage_rounded, value: '6,040', caption: 'GRN'),
        KpiCard(icon: Icons.check_rounded, value: '2,260', caption: 'Packed'),
        KpiCard(icon: Icons.pending_rounded, value: '3,780', caption: 'Pending'),
        KpiCard(icon: Icons.warning_rounded, value: '1', caption: 'Exceptions'),
      ]),
      'SplitPane': const SplitPane(main: Text('main'), side: Text('side')),
      'KeyValues': const KeyValues([
        ('GRN batch', 'GRN-0909-01'),
        ('Uploaded by', 'Rajesh Menon · 09-Sep-2026 08:12'),
      ]),
    };

    for (final entry in specimens.entries) {
      for (final width in [768.0, 390.0]) {
        testWidgets('${entry.key} at ${width.toInt()}px', (tester) async {
          await pumpIn(tester, entry.value, width: width, height: 900);
          expectNoOverflow(tester, '${entry.key} at ${width.toInt()}px');
        });
      }
    }
  });

  /* ===================================================================== */
  /* 4. the value mappings                                                 */
  /* ===================================================================== */

  group('mappings', () {
    test('every status the API returns has a deliberate tone', () {
      const mapped = {
        'Completed': PillTone.ok,
        'In Progress': PillTone.amber,
        'Allocated': PillTone.info,
        'Pending': PillTone.neutral,
        'Exception': PillTone.bad,
        'Free': PillTone.neutral,
        'Occupied': PillTone.amber,
        'Submitted': PillTone.ok,
        'Started': PillTone.info,
        'Open': PillTone.info,
        'Finalised': PillTone.violet,
      };
      mapped.forEach((status, tone) => expect(Brand.statusTone(status), tone, reason: status));
      expect(Brand.statusTone('Something New'), PillTone.neutral,
          reason: 'an unknown status must render, not throw');
    });

    test('AlertTone.parse falls back to info rather than throwing', () {
      expect(AlertTone.parse('bad'), AlertTone.bad);
      expect(AlertTone.parse('warn'), AlertTone.warn);
      expect(AlertTone.parse('ok'), AlertTone.ok);
      expect(AlertTone.parse('nonsense'), AlertTone.info);
    });

    testWidgets('ProgressBar clamps instead of overflowing its track', (tester) async {
      for (final percent in [-40, 0, 37, 100, 260]) {
        await pumpIn(tester, SizedBox(width: 300, child: ProgressBar(percent: percent)));
        expectNoOverflow(tester, 'ProgressBar at $percent%');
        final f = tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox));
        expect(f.widthFactor, inInclusiveRange(0.0, 1.0), reason: 'at $percent%');
      }
    });

    testWidgets('RingProgress survives the same range', (tester) async {
      for (final percent in [-40, 0, 100, 260]) {
        await pumpIn(tester, RingProgress(percent: percent, label: 'Packed'));
        expectNoOverflow(tester, 'RingProgress at $percent%');
      }
    });

    testWidgets('StatusPill puts the status on screen with its mapped tone', (tester) async {
      await pumpIn(tester, const StatusPill('Exception'));
      expect(find.text('Exception'), findsOneWidget);
      expect(tester.widget<Pill>(find.byType(Pill)).tone, PillTone.bad);
    });
  });

  /* ===================================================================== */
  /* 5. the surfaces the gallery never touched                             */
  /* ===================================================================== */

  group('modals and toasts', () {
    testWidgets('Toast appears, carries its message, and clears itself', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(light: false),
        home: Scaffold(body: Builder(builder: (context) => GradButton(
          label: 'go',
          onPressed: () => Toast.ok(context, 'Submitted', 'TX0131 recorded against T-05'),
        ))),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('TX0131 recorded against T-05'), findsOneWidget);

      // It must also go away on its own; a toast that leaks stays over the UI.
      await tester.pump(const Duration(milliseconds: 4500));
      await tester.pump();
      expect(find.text('Submitted'), findsNothing);
    });

    testWidgets('a bad Toast lingers longer than an ok one', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(light: false),
        home: Scaffold(body: Builder(builder: (context) => GradButton(
          label: 'go',
          onPressed: () => Toast.bad(context, 'Refused', 'Exceeds the GRN quantity'),
        ))),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 4500));
      expect(find.text('Refused'), findsOneWidget,
          reason: 'an error must outlast the 4.2s an acknowledgement gets');
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();
      expect(find.text('Refused'), findsNothing);
    });

    testWidgets('showSpdModal renders its title, body and actions, and closes', (tester) async {
      var closed = false;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(light: false),
        home: Scaffold(body: Builder(builder: (context) => GradButton(
          label: 'open',
          onPressed: () => showSpdModal<void>(
            context,
            title: 'Print label',
            subtitle: '90210-ABX · INV-77001',
            content: (context, setModalState) => const Text('modal body'),
            actions: (context, _) => [
              GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
              GradButton(label: 'Print', onPressed: () { closed = true; Navigator.pop(context); }),
            ],
          ),
        ))),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Print label'), findsOneWidget);
      expect(find.text('90210-ABX · INV-77001'), findsOneWidget);
      expect(find.text('modal body'), findsOneWidget);

      await tester.tap(find.text('Print'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(find.text('modal body'), findsNothing);
    });

    testWidgets('setModalState rebuilds the modal in place', (tester) async {
      // The dialog is a StatefulBuilder, so a screen that calls setModalState
      // expects the body to rebuild without the dialog being torn down.
      var n = 0;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(light: false),
        home: Scaffold(body: Builder(builder: (context) => GradButton(
          label: 'open',
          onPressed: () => showSpdModal<void>(
            context,
            title: 'Reprint',
            content: (context, setModalState) => GhostButton(
              label: 'count $n', onPressed: () => setModalState(() => n++)),
          ),
        ))),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('count 0'), findsOneWidget);
      await tester.tap(find.text('count 0'));
      await tester.pumpAndSettle();
      expect(find.text('count 1'), findsOneWidget);
    });

    testWidgets('a non-dismissible modal ignores a tap on the barrier', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(light: false),
        home: Scaffold(body: Builder(builder: (context) => GradButton(
          label: 'open',
          onPressed: () => showSpdModal<void>(
            context,
            title: 'Finalise shift',
            dismissible: false,
            content: (context, _) => const Text('this decision needs an answer'),
          ),
        ))),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('this decision needs an answer'), findsOneWidget);
    });
  });

  /* ===================================================================== */
  /* 6. LabelCard — what a supervisor approves before committing stock     */
  /* ===================================================================== */

  group('LabelCard', () {
    LabelUnit unit(num qty, {int index = 1, int of = 1, int qrSize = 25}) => LabelUnit(
          index: index, of: of, qty: qty,
          payload: '90210-ABX|INV-77001|$qty',
          qr: List.generate(qrSize, (r) => List.generate(qrSize, (c) => (r + c).isEven)),
          barcode: List.filled(60, 2),
        );

    LabelPreview preview({List<LabelUnit>? labels, num grnQty = 270, num? moq}) => LabelPreview(
          line: GrnLine({
            'id': 'L001', 'invoice_no': 'INV-77001', 'part_no': '90210-ABX',
            'part_desc': 'Front Bumper Bracket LH', 'uom': 'NOS',
            'vendor': 'DynaFast Fasteners', 'grn_date': '2026-09-09',
            'grn_qty': grnQty, 'moq': moq,
          }),
          template: 'SPD Standard 100×60',
          labels: labels ?? [unit(grnQty)],
          alreadyPrinted: false,
        );

    testWidgets('prints the fields FR-3.1 requires', (tester) async {
      await pumpIn(tester, LabelCard(preview: preview()));
      expectNoOverflow(tester, 'LabelCard');
      for (final text in ['90210-ABX', 'Front Bumper Bracket LH', 'INV-77001']) {
        expect(find.textContaining(text), findsWidgets, reason: 'the label omits $text');
      }
      expect(find.textContaining('270'), findsWidgets, reason: 'the GRN quantity is missing');
    });

    testWidgets('renders in light theme and at a narrow width', (tester) async {
      await pumpIn(tester, LabelCard(preview: preview(), width: 260), light: true, width: 390);
      expectNoOverflow(tester, 'LabelCard narrow');
    });

    testWidgets('survives an empty QR and barcode rather than blanking the screen', (tester) async {
      // The server is the only source of these; a failed preview must degrade.
      await pumpIn(tester, LabelCard(preview: LabelPreview(
        line: preview().line, template: 'x',
        labels: [LabelUnit(index: 1, of: 1, qty: 270, payload: 'x', qr: const [], barcode: const [])],
        alreadyPrinted: false,
      )));
      expectNoOverflow(tester, 'LabelCard with no codes');
      expect(find.textContaining('90210-ABX'), findsWidgets);
    });

    testWidgets('survives a preview carrying no labels at all', (tester) async {
      await pumpIn(tester, LabelCard(preview: LabelPreview(
        line: preview().line, template: 'x', labels: const [], alreadyPrinted: false)));
      expectNoOverflow(tester, 'LabelCard with no labels');
      expect(find.textContaining('90210-ABX'), findsWidgets);
    });

    /* FR-3.5 — the split. */

    testWidgets('a split label shows its own quantity, not the line total', (tester) async {
      // MOQ 300 against a GRN quantity of 350: the second label holds 50, and a
      // label that showed 350 would have someone pack the wrong pouch.
      await pumpIn(tester, LabelCard(
        preview: preview(grnQty: 350, moq: 300, labels: [unit(300, index: 1, of: 2), unit(50, index: 2, of: 2)]),
        unit: unit(50, index: 2, of: 2),
      ));
      expectNoOverflow(tester, 'split LabelCard');
      expect(find.textContaining('50'), findsWidgets);
      expect(find.textContaining('2 of 2'), findsOneWidget);
      // FR-3.1 still wants the GRN quantity present, alongside the pack's share.
      expect(find.textContaining('GRN 350'), findsOneWidget);
    });

    testWidgets('an unsplit label shows no marker', (tester) async {
      await pumpIn(tester, LabelCard(preview: preview()));
      expect(find.textContaining('1 of 1'), findsNothing,
          reason: 'a line that was never split must look exactly as it did before MOQ existed');
      expect(find.textContaining('GRN 270'), findsNothing);
    });
  });

  /* ===================================================================== */
  /* 7. showLineDetail — the drill-down, over a fake repository            */
  /* ===================================================================== */

  group('showLineDetail', () {
    Widget host(SpdRepository repo) => ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: buildTheme(light: false),
            home: Scaffold(body: Consumer(builder: (context, ref, _) => GradButton(
              label: 'open', onPressed: () => showLineDetail(context, ref, 'L001')))),
          ),
        );

    testWidgets('lists the transactions with their captured times', (tester) async {
      await tester.pumpWidget(host(_FakeRepo()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('90210-ABX'), findsWidgets);
      expect(find.text('TX0101'), findsOneWidget);
      expect(find.text('TX0102'), findsOneWidget);
      expect(find.text('running'), findsOneWidget,
          reason: 'a started transaction shows as running, not as a blank duration');
      expect(find.textContaining('Open exception'), findsOneWidget);
      expect(find.textContaining('Split allocation'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('TX0101'), findsNothing);
    });

    testWidgets('a failed fetch becomes a toast, not a blank modal', (tester) async {
      await tester.pumpWidget(host(_FailingRepo()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Could not open the line'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      await tester.pump(const Duration(milliseconds: 6500));
      await tester.pump();
    });
  });

  group('showPdfPreviewDialog', pdfPreviewTests);
}

/* ---- fakes ------------------------------------------------------------- */

class _FakeRepo extends SpdRepository {
  _FakeRepo() : super(ApiClient(baseUrl: 'http://127.0.0.1:1/api'));

  @override
  Future<LineDetail> line(String id) async => LineDetail(
        line: GrnLine({
          'id': id, 'invoice_no': 'INV-77001', 'part_no': '90210-ABX',
          'part_desc': 'Front Bumper Bracket LH', 'uom': 'NOS',
          'vendor': 'DynaFast Fasteners', 'grn_date': '2026-09-09',
          'grn_qty': 270, 'packed': 120, 'pending': 150, 'status': 'In Progress',
          'tables': ['T-01', 'T-02'],
        }),
        txns: [
          PackingTxn(const {
            'id': 'TX0101', 'line_id': 'L001', 'table_no': 'T-01', 'member_name': 'Sandeep Singh',
            'start_at': '2026-09-09T09:05:00.000Z', 'submit_at': '2026-09-09T09:36:00.000Z',
            'qty': 120, 'pouches': 5, 'boxes': 1, 'status': 'Submitted',
          }),
          PackingTxn(const {
            'id': 'TX0102', 'line_id': 'L001', 'table_no': 'T-02', 'member_name': 'Priya Nair',
            'start_at': '2026-09-09T10:02:00.000Z', 'submit_at': null,
            'qty': 0, 'pouches': 0, 'boxes': 0, 'status': 'Started',
          }),
        ],
        exceptions: [
          SpdException(const {
            'id': 'EX011', 'txn_id': 'TX0101', 'line_id': 'L001', 'type': 'Excess Entry',
            'detail': 'Packed 160 against a GRN quantity of 140', 'remarks': '',
            'resolved_at': null,
          }),
        ],
        allocations: [
          Allocation(const {
            'id': 'AL051', 'line_id': 'L001', 'table_no': 'T-01', 'qty': 140,
            'reason': 'Split across two tables to meet the dispatch cut-off',
          }),
        ],
      );
}

class _FailingRepo extends SpdRepository {
  _FailingRepo() : super(ApiClient(baseUrl: 'http://127.0.0.1:1/api'));

  @override
  Future<LineDetail> line(String id) async =>
      throw ApiException('No connection to the SPD server');
}

/* ========================================================================= */
/* 8. showPdfPreviewDialog — the reason print stopped going straight to the OS */
/* ========================================================================= */

/// The `printing` plugin rasterises through a platform channel that a widget
/// test has no implementation for, so the preview pane itself cannot render
/// here. The chrome around it can, and that is the part that carries the
/// requirement: a Supervisor must see the sheet named and framed before any
/// printer is offered, and be able to back out without committing label stock.
void pdfPreviewTests() {
  const channel = MethodChannel('net.nfet.printing');

  setUp(() {
    // `printingInfo` is null-checked by the plugin, so the handler has to
    // answer it with a capability map rather than nothing. canRaster is false
    // because there is no rasteriser here — which is precisely why this test
    // covers the chrome and not the rendered page.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'printingInfo') {
        return <String, dynamic>{
          'directPrint': false, 'dynamicLayout': false, 'canPrint': true,
          'canConvertHtml': false, 'canShare': false, 'canRaster': false,
        };
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('frames the sheet and reports "not printed" when dismissed', (tester) async {
    bool? printed;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(light: false),
      home: Scaffold(body: Builder(builder: (context) => GradButton(
        label: 'preview',
        onPressed: () async {
          printed = await showPdfPreviewDialog(
            context,
            title: 'Label sheet',
            subtitle: '3 labels · SPD Standard 100×60',
            fileName: 'spd-labels-0909.pdf',
            bytes: Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46]),   // %PDF
          );
        },
      ))),
    ));

    await tester.tap(find.text('preview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Label sheet'), findsOneWidget);
    expect(find.text('3 labels · SPD Standard 100×60'), findsOneWidget,
        reason: 'the Supervisor must be told what they are about to commit stock to');

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Label sheet'), findsNothing);
    expect(printed, isFalse, reason: 'backing out must not be reported as a print');
  });
}
