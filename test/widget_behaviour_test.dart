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
import 'package:spd_frontend/ui/widgets/operator_prompt.dart';
import 'package:spd_frontend/ui/widgets/pdf_preview_dialog.dart';
import 'package:spd_frontend/ui/supervisor/allocation_screen.dart' show showAllocateDialog;
import 'package:spd_frontend/ui/supervisor/lines_screen.dart' show showAdjustQtyDialog;

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

    /* The invoice filter on a real shift. Material's menu grew to fit its
       items and was bounded only by the window, so four hundred invoices
       opened a list the height of the screen, over the table it was filtering,
       with nothing to do but drag. These are the three things that fixed it. */

    /// A dropdown of [n] invoices, mounted and opened.
    Future<void> openInvoices(WidgetTester tester, int n, {void Function(String?)? onPick}) async {
      await pumpIn(tester, SpdDropdown<String>(
        value: '',
        items: [
          const DropdownMenuItem(value: '', child: Text('All invoices')),
          for (var i = 0; i < n; i++)
            DropdownMenuItem(value: 'INV-$i', child: Text('INV-${1000 + i}/2026-27')),
        ],
        onChanged: onPick ?? (_) {},
      ));
      await tester.tap(find.text('All invoices'));
      await tester.pumpAndSettle();
    }

    testWidgets('a long SpdDropdown is bounded and scrolls', (tester) async {
      await openInvoices(tester, 400);

      /* The panel's own list, named through the ListView rather than as "the
         last Scrollable on screen" — the harness wraps every widget it pumps
         in a SingleChildScrollView, so that phrase means two different things
         depending on paint order. */
      final position = tester.state<ScrollableState>(find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      )).position;

      final box = tester.getRect(find.byType(ListView));
      expect(box.height, lessThanOrEqualTo(320),
          reason: '400 invoices opened a ${box.height}px list — it has to be bounded');
      expect(box.bottom, lessThanOrEqualTo(900),
          reason: 'the panel ran off the bottom of the 900px viewport');

      // And it is a real scroller rather than a clipped column: there is more
      // below the fold, and the last invoice can be reached, which is the
      // whole complaint.
      expect(position.maxScrollExtent, greaterThan(0));
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('INV-1399/2026-27'), findsOneWidget);
    });

    testWidgets('a long SpdDropdown can be searched', (tester) async {
      String? chosen;
      await openInvoices(tester, 400, onPick: (v) => chosen = v);

      expect(find.byType(TextField), findsOneWidget,
          reason: 'past a glanceable list, reading becomes hunting without a filter');
      await tester.enterText(find.byType(TextField), '1207');
      await tester.pumpAndSettle();

      expect(find.text('INV-1207/2026-27'), findsOneWidget);
      expect(find.text('INV-1208/2026-27'), findsNothing);

      await tester.tap(find.text('INV-1207/2026-27'));
      await tester.pumpAndSettle();
      expect(chosen, 'INV-207');
    });

    testWidgets('a short SpdDropdown is not given a search box', (tester) async {
      await openInvoices(tester, 4);
      expect(find.byType(TextField), findsNothing,
          reason: 'five rows do not need filtering, and the box would be in the way');
    });

    testWidgets('choosing the null row is not the same as dismissing', (tester) async {
      /* The seating panel's "— unassigned —" is a real choice: it empties a
         table. Returning the value bare made it indistinguishable from
         pressing Escape, so clearing a table silently did nothing. */
      var calls = 0;
      String? chosen = 'tm.anita';
      await pumpIn(tester, SpdDropdown<String?>(
        value: 'tm.anita',
        items: const [
          DropdownMenuItem<String?>(value: null, child: Text('— unassigned —')),
          DropdownMenuItem<String?>(value: 'tm.anita', child: Text('Anita Varma')),
        ],
        onChanged: (v) { calls++; chosen = v; },
      ));

      await tester.tap(find.text('Anita Varma').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('— unassigned —').last);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(chosen, isNull);

      /* Whereas dismissing really does report nothing. Opened by the closed
         field, which still reads "Anita Varma": nothing here feeds the chosen
         value back in, exactly as the seating panel does not until it saves. */
      await tester.tap(find.text('Anita Varma').first);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(calls, 1, reason: 'a dismissal must not be reported as a choice');
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
      expect(find.text('INV-19'), findsOneWidget,
          reason: 'a short table still belongs to the page and draws in full');
    });

    testWidgets('a shift of GRN lines does not lay out every row', (tester) async {
      /* The one that made the app feel broken after an import.

         An unbounded ListView has to shrinkWrap, and shrinkWrap means laying
         out every child to measure the total height — so nothing is lazy. A
         real shift is 1,532 lines: 18,907ms to first paint and 1,965ms every
         time the pointer crossed a row. Past sixty rows the table now takes
         its own bounded scroller, which costs 316ms and 25ms.

         Measured here as "is the last row in the tree", because that is the
         thing that silently regresses — a stray maxHeight, or the threshold
         being raised past a screen that needs it, and the table is eagerly
         laying out a shift again with nothing to show for it. */
      await pumpIn(tester, SpdTable(
        columns: const [SpdCol('Invoice'), SpdCol('Qty', right: true)],
        rows: [for (var i = 0; i < 1532; i++) SpdRow([cell('INV-$i'), monoCell('$i')])],
      ));
      expect(find.text('INV-0'), findsOneWidget);
      expect(find.text('INV-1531'), findsNothing,
          reason: 'row 1,531 is three hundred screens down — building it is the bug');
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

  group('SpdLoader', () {
    testWidgets('centres in the visible space below the filters, not just under them', (tester) async {
      /* Every screen is a scrolling column, which gives the loader no height
         of its own; it used to sit directly under the filter card at the top of
         an empty page. 300px of header and filters in a 900px viewport leaves
         the space from 316 down, and the mark belongs in the middle of that. */
      await pumpIn(tester, const Column(children: [
        SizedBox(height: 300),
        SpdLoader(size: 48),
      ]));
      await tester.pump();
      final mark = tester.getCenter(find.byType(SMark));
      expect(mark.dy, closeTo((316 + 900 - 24) / 2, 2), reason: 'the mark is at ${mark.dy}');
      expect(mark.dx, closeTo(1440 / 2, 1));
    });

    testWidgets('fill: false takes only its own height, for a wait inside a card', (tester) async {
      await pumpIn(tester, const Column(children: [SpdLoader(size: 40, fill: false), Text('after')]));
      expect(tester.getTopLeft(find.text('after')).dy, lessThan(16 + 40 * 1.06 + 2));
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
        );

    // packed_on is the shift's date, which the sticker must NOT print: the date
    // on it is the day Print is pressed (printedOn, from the server).
    GrnLine grn({num grnQty = 270, num? moq, String? packer = 'Rajesh Menon'}) => GrnLine({
          'id': 'L001', 'invoice_no': 'INV-77001', 'part_no': '90210-ABX',
          'part_desc': 'Front Bumper Bracket LH', 'uom': 'NOS',
          'vendor': 'DynaFast Fasteners', 'grn_date': '2026-09-09',
          'grn_qty': grnQty, 'moq': moq, 'packed_on': '2026-09-10', 'packer': packer,
        });

    LabelPreview preview({List<LabelUnit>? labels, num grnQty = 270, num? moq, String? packer = 'Rajesh Menon'}) =>
        LabelPreview(
          line: grn(grnQty: grnQty, moq: moq, packer: packer),
          template: 'SPD 2-up 100×25',
          labels: labels ?? [unit(grnQty)],
          alreadyPrinted: false,
          printedOn: '2026-10-28',
        );

    /// The QR's own box: the only square SizedBox on the sticker.
    final qrBox = find.descendant(
      of: find.byType(LabelCard),
      matching: find.byWidgetPredicate((w) => w is SizedBox && w.width != null && w.width == w.height),
    );

    testWidgets('prints what the floor asked for, and nothing else', (tester) async {
      /* The 50 × 25 mm sample — part number, description, pouch quantity,
         date, QR — with the invoice and the packer added. The vendor and the
         GRN date are not printed. */
      await pumpIn(tester, LabelCard(preview: preview()));
      expectNoOverflow(tester, 'LabelCard');
      for (final text in ['90210-ABX', 'Front Bumper Bracket LH', '270 NOS', 'INV INV-77001', 'Rajesh Menon', '28-Oct-26']) {
        expect(find.text(text), findsOneWidget, reason: 'the sticker omits $text');
      }
      for (final absent in ['Sep', 'DynaFast', 'INVOICE', 'QTY', 'PACKER', 'GRN DATE']) {
        expect(find.textContaining(absent), findsNothing, reason: 'the sticker prints $absent');
      }
    });

    testWidgets('the date is the day Print is pressed, and an unallocated packer is a dash', (tester) async {
      await pumpIn(tester, LabelCard(preview: preview(packer: null)));
      expect(find.text('28-Oct-26'), findsOneWidget, reason: 'the print date, from the server');
      expect(find.textContaining('Sep'), findsNothing, reason: 'printed the shift or GRN date');
      expect(find.text('—'), findsOneWidget, reason: 'no packer until the line is allocated');
    });

    testWidgets('only the QR is painted — no barcode', (tester) async {
      await pumpIn(tester, LabelCard(preview: preview()));
      final painters = tester
          .widgetList<CustomPaint>(find.descendant(of: find.byType(LabelCard), matching: find.byType(CustomPaint)))
          .where((p) => p.painter != null);
      expect(painters, hasLength(1), reason: 'only the QR should be painted, not a barcode');
    });

    testWidgets('is a 50 × 25 mm sticker at any width', (tester) async {
      for (final w in [330.0, 260.0]) {
        await pumpIn(tester, LabelCard(preview: preview(), width: w), light: true, width: 390);
        expectNoOverflow(tester, 'LabelCard at $w');
        final size = tester.getSize(find.byType(LabelCard));
        expect(size.width, w);
        expect(size.height, closeTo(w * 70.87 / 141.73, 0.01), reason: 'not 2 : 1 at $w');
      }
    });

    testWidgets('survives an empty QR rather than blanking the screen', (tester) async {
      // The server is the only source of these; a failed preview must degrade.
      await pumpIn(tester, LabelCard(preview: LabelPreview(
        line: preview().line, template: 'x',
        labels: [LabelUnit(index: 1, of: 1, qty: 270, payload: 'x', qr: const [])],
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

    testWidgets('a split sticker shows its own pouch quantity, not the line total', (tester) async {
      /* MOQ 300 against a GRN quantity of 350: this is the remainder pouch and
         it holds 50. A sticker showing 350 would have someone pack the wrong
         bag. No pack index — two full pouches are interchangeable. */
      await pumpIn(tester, LabelCard(
        preview: preview(grnQty: 350, moq: 300, labels: [unit(300, index: 1, of: 2), unit(50, index: 2, of: 2)]),
        unit: unit(50, index: 2, of: 2),
      ));
      expectNoOverflow(tester, 'split LabelCard');
      expect(find.text('50 NOS'), findsOneWidget, reason: 'this pouch holds 50');
      expect(find.text('350 NOS'), findsNothing, reason: 'the receipt total must not appear');
      expect(find.textContaining(' OF '), findsNothing, reason: 'and no pouch marker');
    });

    testWidgets('a bigger QR matrix costs the layout nothing', (tester) async {
      final qrSizes = <int, Size>{};
      final cardSizes = <int, Size>{};
      for (final n in [25, 29, 33]) {
        await pumpIn(tester, LabelCard(preview: preview(labels: [unit(270, qrSize: n)])));
        expectNoOverflow(tester, 'LabelCard with a $n×$n QR');
        qrSizes[n] = tester.getSize(qrBox);
        cardSizes[n] = tester.getSize(find.byType(LabelCard));
      }
      for (final n in [29, 33]) {
        expect(qrSizes[n], qrSizes[25], reason: '$n modules should draw into the same square');
        expect(cardSizes[n], cardSizes[25], reason: 'a $n-module QR moved the sticker about');
      }
    });

    testWidgets('nothing on the sticker reaches the QR’s quiet zone, however long', (tester) async {
      /* A scanner finds the code by four modules of white on every side. The
         part number spans the sticker above the code and the left column sits
         beside it, so both are measured with every field as long as it can
         honestly be. */
      for (final n in [25, 29, 33]) {
        await pumpIn(tester, LabelCard(
          preview: LabelPreview(
            line: GrnLine({
              'id': 'L001',
              'invoice_no': 'INV-77003/2026-27/04-BLUEVOLT-MUMBAI-1',
              'part_no': '90210-ABX-BRACKET-FRONT-LH-REV12-A/B.012',
              'part_desc': 'Front bumper mounting bracket, left hand, revision 12, powder coated',
              'uom': 'NOS', 'grn_date': '2026-05-05', 'grn_qty': 1234567, 'moq': 300,
              'packed_on': '2026-09-28',
            }),
            template: 'SPD 2-up 100×25',
            labels: [unit(300, index: 1, of: 2, qrSize: n), unit(50, index: 2, of: 2, qrSize: n)],
            alreadyPrinted: false,
          ),
          unit: unit(50, index: 2, of: 2, qrSize: n),
        ));
        expectNoOverflow(tester, 'LabelCard with over-long fields and a $n×$n QR');

        final qr = tester.getRect(qrBox);
        final quiet = qr.inflate(4 * (qr.width / n));
        final card = tester.getRect(find.byType(LabelCard));
        expect(card.contains(quiet.topLeft) && card.contains(quiet.bottomRight - const Offset(0.01, 0.01)), isTrue,
            reason: 'v$n: the quiet zone $quiet runs off the sticker $card');
        for (final element in find
            .descendant(of: find.byType(LabelCard), matching: find.byType(Text))
            .evaluate()) {
          final box = element.renderObject! as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          expect(rect.overlaps(quiet), isFalse,
              reason: 'v$n: ${(element.widget as Text).data} at $rect is in the quiet zone $quiet');
        }
      }
    });

    testWidgets('every module lands on its own cell, at every version', (tester) async {
      /* Driving the painter over a recording canvas, rather than comparing
         pixels: it says exactly where each module was drawn, which is what
         decides whether the thing scans.

         The pattern is a tall, narrow block in the top-left — deliberately not
         square and not centred, because a square one is its own transpose and a
         painter that swapped rows for columns would draw it identically. */
      for (final n in [25, 29, 33]) {
        final rows = n ~/ 2;
        final cols = n ~/ 4;
        final modules = List.generate(n, (r) => List.generate(n, (c) => r < rows && c < cols));
        await pumpIn(tester, LabelCard(preview: preview(labels: [
          LabelUnit(index: 1, of: 1, qty: 270, payload: 'x', qr: modules),
        ])));

        final painter = tester.widget<CustomPaint>(
            find.descendant(of: qrBox, matching: find.byType(CustomPaint))).painter!;
        final canvas = _RecordingCanvas();
        painter.paint(canvas, const Size(62, 62));

        final cell = 62 / n;
        expect(canvas.rects.length, rows * cols,
            reason: 'v$n: drew ${canvas.rects.length} modules, expected ${rows * cols}');

        for (final rect in canvas.rects) {
          final c = (rect.left / cell).round();
          final r = (rect.top / cell).round();
          expect(modules[r][c], isTrue, reason: 'v$n: painted a light module at $r,$c');
          expect(rect.left, closeTo(c * cell, 0.001), reason: 'v$n: column $c is off its cell');
          expect(rect.top, closeTo(r * cell, 0.001), reason: 'v$n: row $r is off its cell');
        }

        /* The modules overlap by a hair so antialiasing leaves no white seam
           between them. That bleed has to stay a fraction of a cell: a flat one
           would dilate a 33-module code half again as much as a 25-module one,
           and a QR that prints too heavy stops scanning. */
        final bleed = canvas.rects.first.width - cell;
        expect(bleed, greaterThan(0), reason: 'v$n: modules would show seams');
        expect(bleed / cell, closeTo(0.16, 0.02),
            reason: 'v$n: modules bleed ${(bleed / cell * 100).round()}% of a cell');

        // And a dark matrix fills its box, overhanging only by the bleed.
        final full = List.generate(n, (_) => List.filled(n, true));
        await pumpIn(tester, LabelCard(preview: preview(labels: [
          LabelUnit(index: 1, of: 1, qty: 270, payload: 'x', qr: full),
        ])));
        final edges = _RecordingCanvas();
        tester.widget<CustomPaint>(find.descendant(of: qrBox, matching: find.byType(CustomPaint)))
            .painter!
            .paint(edges, const Size(62, 62));
        expect(edges.rects.length, n * n, reason: 'v$n: a dark matrix lost modules');
        final right = edges.rects.map((r) => r.right).reduce((a, b) => a > b ? a : b);
        final bottom = edges.rects.map((r) => r.bottom).reduce((a, b) => a > b ? a : b);
        expect(right, closeTo(62 + bleed, 0.001), reason: 'v$n: the code does not fill its width');
        expect(bottom, closeTo(62 + bleed, 0.001), reason: 'v$n: the code does not fill its height');
      }
    });
  });


  /* ===================================================================== */
  /* 6b. allocating to several tables, and writing off a remainder         */
  /* ===================================================================== */

  group('multi-table allocation and quantity write-off', () {
    GrnLine line({int allocations = 0, List<String> tables = const [], num pending = 150}) => GrnLine({
          'id': 'L001', 'invoice_no': 'INV-77001', 'part_no': '90210-ABX',
          'part_desc': 'Front Bumper Bracket LH', 'uom': 'NOS', 'vendor': 'DynaFast',
          'grn_date': '2026-09-09', 'grn_qty': 270, 'packed': 270 - pending,
          'pending': pending, 'status': 'In Progress',
          'allocations': allocations, 'tables': tables,
        });

    Widget host(SpdRepository repo, Widget Function(BuildContext, WidgetRef) child) => ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            tablesProvider.overrideWith((ref) async => [
                  TableStat(const {'table_no': 'T-01', 'member_name': 'Sandeep Singh', 'status': 'Occupied'}),
                  TableStat(const {'table_no': 'T-02', 'member_name': 'Priya Nair', 'status': 'Free'}),
                  TableStat(const {'table_no': 'T-03', 'member_name': null, 'status': 'Free'}),
                ]),
          ],
          child: MaterialApp(
            theme: buildTheme(light: false),
            /* The dialog reads the table list with , which does not
               subscribe — so without something watching it here the provider is
               never initialised and the dialog bails with 'No packing tables'.
               The real screens watch it to draw the board. */
            home: Scaffold(body: Consumer(builder: (c, r, _) {
              r.watch(tablesProvider);
              return child(c, r);
            })),
          ),
        );

    testWidgets('a line already on a table can still be sent to another', (tester) async {
      /* BR-04 used to refuse a second table outright unless the whole thing
         was split in one go, which meant an invoice could never be spread
         across the floor as the work actually arrives. The dialog now offers
         every table the line is *not* already on, and says which it is. */
      final repo = _AllocRepo();
      await tester.pumpWidget(host(repo, (c, r) => GradButton(
            label: 'open',
            onPressed: () => showAllocateDialog(c, r, line(allocations: 1, tables: ['T-01'])),
          )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Already on T-01'), findsOneWidget);
      expect(find.textContaining('T-01 ·'), findsNothing,
          reason: 'the table it is already on must not be offered again');
      expect(find.textContaining('T-02 ·'), findsOneWidget);
      expect(find.textContaining('T-03 ·'), findsOneWidget);

      // Adding to a line already placed is the BR-04 case, so a reason is asked
      // for before anything is picked.
      expect(find.textContaining('REASON'), findsOneWidget);

      await tester.tap(find.textContaining('T-02 ·'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Second bench opened for the cut-off');
      await tester.tap(find.text('Confirm allocation'));
      await tester.pumpAndSettle();

      expect(repo.sent, isNotNull);
      expect(repo.sent!.map((t) => t.tableNo).toList(), ['T-02']);
      expect(repo.reason, 'Second bench opened for the cut-off');

      // A toast outlives the frame that shows it; drain its timer so the
      // test does not end with one pending.
      await tester.pump(const Duration(milliseconds: 6500));
      await tester.pump();
    });

    testWidgets('several tables can be picked at once, each with a share', (tester) async {
      final repo = _AllocRepo();
      await tester.pumpWidget(host(repo, (c, r) => GradButton(
            label: 'open', onPressed: () => showAllocateDialog(c, r, line()))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // One table is an ordinary allocation and asks for nothing more.
      await tester.tap(find.textContaining('T-01 ·'));
      await tester.pumpAndSettle();
      expect(find.textContaining('QUANTITY EACH'), findsNothing);
      expect(find.textContaining('REASON'), findsNothing,
          reason: 'the first table is a plain choice — BR-04 only guards the second');

      // A second turns it into a split, which asks for both.
      await tester.tap(find.textContaining('T-03 ·'));
      await tester.pumpAndSettle();
      expect(find.textContaining('QUANTITY EACH'), findsOneWidget);
      expect(find.textContaining('REASON'), findsOneWidget);

      final qtys = find.descendant(
          of: find.byType(Wrap).last, matching: find.byType(TextField));
      expect(qtys, findsNothing, reason: 'the shares are not inside the chip wrap');

      await tester.enterText(find.byType(TextField).first, '170');
      await tester.enterText(find.byType(TextField).at(1), '100');
      await tester.enterText(find.byType(TextField).last, 'Bulky line spread over two benches');
      await tester.tap(find.text('Confirm allocation'));
      await tester.pumpAndSettle();

      expect(repo.sent!.map((t) => '${t.tableNo}:${t.qty}').toList(), ['T-01:170', 'T-03:100']);
      expect(repo.reason, 'Bulky line spread over two benches');

      // A toast outlives the frame that shows it; drain its timer so the
      // test does not end with one pending.
      await tester.pump(const Duration(milliseconds: 6500));
      await tester.pump();
    });

    testWidgets('the write-off sends a quantity and a reason, and nothing else', (tester) async {
      /* BR-01 — there is no remaining quantity to edit, so what the dialog
         collects is the write-off itself. It must say so: a Supervisor who
         thinks this is correcting the GRN figure has been misled about what
         the MIS will show. */
      final repo = _AdjustRepo();
      await tester.pumpWidget(host(repo, (c, r) => GradButton(
            label: 'open', onPressed: () => showAdjustQtyDialog(c, r, line(pending: 5)))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('does not change the GRN quantity'), findsOneWidget);
      expect(find.textContaining('5 NOS outstanding'), findsOneWidget);

      // It defaults to the whole remainder, because closing a line out is what
      // it is for.
      expect(find.widgetWithText(TextField, '5'), findsOneWidget);

      // A reason is not optional, and the refusal happens before the call.
      await tester.tap(find.text('Write off'));
      await tester.pumpAndSettle();
      expect(repo.qty, isNull, reason: 'a write-off with no reason must not reach the server');

      await tester.enterText(find.byType(TextField).last, 'Balance short-shipped');
      await tester.tap(find.text('Write off'));
      await tester.pumpAndSettle();
      expect(repo.qty, 5);
      expect(repo.reason, 'Balance short-shipped');

      // A toast outlives the frame that shows it; drain its timer so the
      // test does not end with one pending.
      await tester.pump(const Duration(milliseconds: 6500));
      await tester.pump();
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
  group('FR-3.5 label counts', labelCountTests);
  group('FR-3.5 print dialog', splitDialogTests);
  group('the operator prompt', _operatorPromptTests);
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

/// Captures what the allocation dialog would have sent, without a server.
class _AllocRepo extends SpdRepository {
  _AllocRepo() : super(ApiClient(baseUrl: 'http://127.0.0.1:1/api'));

  List<TableShare>? sent;
  String? reason;

  @override
  Future<void> allocate({
    required String lineId,
    required List<TableShare> tables,
    String reason = '',
  }) async {
    sent = tables;
    this.reason = reason;
  }
}

/// Ditto for the BR-01 write-off.
class _AdjustRepo extends SpdRepository {
  _AdjustRepo() : super(ApiClient(baseUrl: 'http://127.0.0.1:1/api'));

  num? qty;
  String? reason;

  @override
  Future<void> adjustQty(String lineId, {required num qty, required String reason}) async {
    this.qty = qty;
    this.reason = reason;
  }
}

class _FailingRepo extends SpdRepository {
  _FailingRepo() : super(ApiClient(baseUrl: 'http://127.0.0.1:1/api'));

  @override
  Future<LineDetail> line(String id) async =>
      throw ApiException('No connection to the SPD server');
}

/// Captures the names the operator prompt would have sent.
class _OperatorRepo extends SpdRepository {
  _OperatorRepo({this.existing = const {}}) : super(ApiClient(baseUrl: 'http://127.0.0.1:1/api'));

  final Map<String, List<String>> existing;
  String? toTable;
  List<String>? sent;

  @override
  Future<List<Shift>> shifts() async => [
        Shift(const {'id': 'A-2026-09-30', 'label': 'Shift A', 'status': 'Open'}),
      ];

  @override
  Future<Map<String, List<String>>> shiftOperators(String shiftId) async => existing;

  @override
  Future<List<String>> saveTableOperators(
      String shiftId, String tableNo, List<String> names) async {
    toTable = tableNo;
    sent = names;
    return names;
  }
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

/* ========================================================================= */
/* 9. FR-3.5 — the numbers the label screens quote                           */
/* ========================================================================= */

void labelCountTests() {
  test('a line reports how many labels it prints', () {
    expect(GrnLine(const {'id': 'L1', 'grn_qty': 350, 'label_count': 2}).labelCount, 2);
    expect(GrnLine(const {'id': 'L1', 'grn_qty': 270, 'label_count': 1}).labelCount, 1);
  });

  test('a line from a server that does not send the count still prints one label', () {
    // The count is what "Print sheet · N" sums. Defaulting it to 0 would tell a
    // Supervisor the sheet is empty; defaulting to 1 matches every line that
    // has no MOQ, which is the case the field is absent for.
    expect(GrnLine(const {'id': 'L1', 'grn_qty': 270}).labelCount, 1);
  });

  test('the sheet total is the sum of the label counts, not the line count', () {
    final lines = [
      GrnLine(const {'id': 'L1', 'grn_qty': 350, 'moq': 300, 'label_count': 2}),
      GrnLine(const {'id': 'L2', 'grn_qty': 360, 'moq': 100, 'label_count': 4}),
      GrnLine(const {'id': 'L3', 'grn_qty': 270, 'label_count': 1}),
    ];
    final total = lines.fold<int>(0, (n, l) => n + l.labelCount);
    expect(total, 7);
    expect(total, isNot(lines.length), reason: 'counting lines would understate the sheet by 4');
  });

  test('a line carries its MOQ, and null when the export had none', () {
    expect(GrnLine(const {'id': 'L1', 'grn_qty': 350, 'moq': 300}).moq, 300);
    expect(GrnLine(const {'id': 'L1', 'grn_qty': 350}).moq, isNull);
  });

  test('the optional import columns reach the console (NFR-6.1)', () {
    final cfg = SpdConfig(const {
      'grnCols': ['Invoice No.', 'Part Number'],
      'grnColsOptional': ['MOQ'],
    });
    expect(cfg.grnCols, ['Invoice No.', 'Part Number']);
    expect(cfg.grnColsOptional, ['MOQ']);
    // An older server that does not send the key must not crash the screen.
    expect(SpdConfig(const {}).grnColsOptional, isEmpty);
  });
}

/// A [Canvas] that records the rectangles drawn on it and ignores everything
/// else, so a painter can be examined without rasterising anything.
class _RecordingCanvas implements Canvas {
  final List<Rect> rects = [];

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(rect);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/* ========================================================================= */
/* 10. FR-3.5 — the print dialog, which now holds more than one label        */
/* ========================================================================= */

void splitDialogTests() {
  LabelUnit u(num qty, int index, int of) => LabelUnit(
        index: index, of: of, qty: qty,
        payload: '76621-MFS|INV-77003|$qty',
        qr: List.generate(25, (r) => List.generate(25, (c) => (r + c).isEven)),
      );

  LabelPreview split(int packs) {
    final labels = [for (var i = 1; i <= packs; i++) u(i == packs ? 50 : 300, i, packs)];
    return LabelPreview(
      line: GrnLine({
        'id': 'L0012', 'invoice_no': 'INV-77003', 'part_no': '76621-MFS',
        'part_desc': 'Mudflap Set (4 pc)', 'uom': 'SET', 'vendor': 'BlueVolt Harness',
        'grn_date': '2026-09-09', 'grn_qty': 350, 'moq': 300,
      }),
      template: 'SPD Standard 100×60',
      labels: labels,
      alreadyPrinted: true,
    );
  }

  /// The modal's content box: showSpdModal constrains it to 620 (880 when wide).
  Widget dialogContent(LabelPreview p) => Column(children: [
        if (p.labels.length > 1) ...[
          AlertBox(
            tone: AlertTone.info,
            title: 'This line prints ${p.labels.length} labels (FR-3.5)',
            message: 'MOQ 300 against a GRN quantity of 350 SET — '
                '${p.labels.map((l) => l.qty).join(' + ')}.',
          ),
          const SizedBox(height: 14),
        ],
        Center(
          child: Wrap(
            spacing: 12, runSpacing: 12, alignment: WrapAlignment.center,
            children: [for (final l in p.labels) LabelCard(preview: p, unit: l)],
          ),
        ),
      ]);

  for (final packs in [2, 4]) {
    for (final width in [620.0, 480.0, 390.0]) {
      testWidgets('$packs labels fit the dialog at ${width.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(width + 48, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(light: false),
          home: Scaffold(body: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: dialogContent(split(packs)),
            ),
          )),
        ));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull,
            reason: '$packs labels overflowed the dialog at ${width.toInt()}px');
      });
    }
  }

  testWidgets('the dialog states the arithmetic it is about to commit stock to', (tester) async {
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(light: false),
      home: Scaffold(body: SingleChildScrollView(child: dialogContent(split(2)))),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('prints 2 labels'), findsOneWidget);
    expect(find.textContaining('300 + 50'), findsOneWidget);
    // Two labels, neither of them numbered or carrying a quantity: the
    // dialog states the arithmetic, the stickers no longer repeat it.
    expect(find.text('76621-MFS'), findsNWidgets(2));
    expect(find.textContaining(' OF '), findsNothing);
    expect(tester.takeException(), isNull);
  });

}

/* ========================================================================= */
/* 10. the operator prompt — who is at the bench                             */
/* ========================================================================= */

/// FR-5.1, after it moved off the sign-in screen.
///
/// A roster picker used to stand on the login form: a member found themselves
/// in a list of every operator in the company before they could type a
/// password, and it named exactly one person. A bench often has three, and
/// most of them have no account at all. So the question is asked after
/// sign-in, at the table, and it takes as many names as the bench holds.
void _operatorPromptTests() {
  Widget host(SpdRepository repo, Widget Function(BuildContext, WidgetRef) child) => ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: buildTheme(light: false),
          home: Scaffold(body: Builder(
            builder: (c) => Consumer(builder: (c, r, _) => child(c, r)),
          )),
        ),
      );

  Future<void> open(WidgetTester tester, SpdRepository repo, {bool atSignIn = true}) async {
    await tester.pumpWidget(host(repo, (c, r) => GradButton(
          label: 'open',
          onPressed: () => showOperatorPrompt(c, r, tableNo: 'T-01', atSignIn: atSignIn),
        )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a bench takes more than one name', (tester) async {
    final repo = _OperatorRepo();
    await open(tester, repo);

    expect(find.textContaining('Who is working at T-01'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Anita Varma');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Sunil Rao');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.toTable, 'T-01');
    expect(repo.sent, ['Anita Varma', 'Sunil Rao']);
  });

  testWidgets('the same person in two cases is one person', (tester) async {
    final repo = _OperatorRepo();
    await open(tester, repo);

    await tester.enterText(find.byType(TextField).first, 'Anita Varma');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '  anita   varma ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.textContaining('already on this bench'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.sent, ['Anita Varma']);
  });

  testWidgets('a name still in the box is not lost on Save', (tester) async {
    /* Someone who types the last name and goes straight for Save has said
       what they mean. Losing it to an unpressed Enter is the kind of small
       betrayal that makes a screen feel broken. */
    final repo = _OperatorRepo();
    await open(tester, repo);

    await tester.enterText(find.byType(TextField).first, 'Kiran Pillai');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.sent, ['Kiran Pillai']);
  });

  testWidgets('the names already on the bench are what it opens with', (tester) async {
    final repo = _OperatorRepo(existing: const {'T-01': ['Lata Thomas', 'Mohan Farooq']});
    await open(tester, repo);

    expect(find.text('Lata Thomas'), findsOneWidget);
    expect(find.text('Mohan Farooq'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove Mohan Farooq'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.sent, ['Lata Thomas']);
  });

  testWidgets('Not now saves nothing', (tester) async {
    final repo = _OperatorRepo();
    await open(tester, repo);

    await tester.enterText(find.byType(TextField).first, 'Anita Varma');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(repo.sent, isNull, reason: 'dismissing the prompt must not write a bench');
  });
}
