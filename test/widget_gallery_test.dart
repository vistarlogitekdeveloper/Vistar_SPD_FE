import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spd_frontend/core/theme.dart';
import 'package:spd_frontend/ui/widgets/common.dart';

/// Renders every widget in the shared component library, in both themes.
///
/// This exists because of a bug that a release build cannot catch: `Wordmark`
/// reproduced the prototype's negative CSS margin with a negative `EdgeInsets`,
/// which `RenderPadding` asserts against. Asserts are stripped from a release
/// bundle, so the signed-off web build rendered it happily while `flutter run`
/// threw on the splash screen and left the element tree inconsistent.
///
/// Anything that only fails under an assert — negative padding, a bad flex, an
/// unbounded constraint — is invisible to a release build and to a screenshot.
/// Mounting each widget here is what makes it visible.
void main() {
  Future<void> show(WidgetTester tester, Widget child, {bool light = false}) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(light: light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(child: Padding(padding: const EdgeInsets.all(16), child: child)),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Every widget worth mounting, with the arguments the app actually passes.
  final gallery = <String, Widget Function()>{
    'Wordmark lg': () => const Wordmark(size: 58),
    'Wordmark md': () => const Wordmark(size: 36),
    'SMark': () => const SMark(width: 34),
    'SMark no glow': () => const SMark(width: 96, glow: false),
    'GradientText': () => GradientText('2,260', style: display(size: 30)),
    'RibbonAccent': () => const RibbonAccent(),
    'SectionTitle': () => const SectionTitle('Table-wise productivity', trailing: 'packed qty'),
    'SpdCard': () => const SpdCard(child: Text('card')),
    'Panel': () => const Panel(title: 'Shift completion', child: Text('body')),
    'KpiCard': () => const KpiCard(
          icon: Icons.storage_rounded,
          value: '6,040',
          caption: 'Total GRN quantity',
          extra: DeltaChip('37%'),
        ),
    'KpiCard gradient': () => const KpiCard(
          icon: Icons.check_rounded, value: '2,260', caption: 'Packed', gradient: true),
    'Pill': () => const Pill('Occupied', tone: PillTone.amber),
    'StatusPill': () => const StatusPill('Exception'),
    'Avatar': () => const Avatar('Rajesh Menon'),
    'PageHeader': () => const PageHeader(
          crumb: 'Overview ·',
          accent: 'Live Dashboard',
          title: 'SPD pre-packing dashboard',
          blurb: 'A blurb that wraps onto a second line to exercise the constraint.',
          actions: [GhostButton(label: 'Refresh')],
        ),
    'BlurbText': () => const BlurbText([('Shift A', true), (' · Open', false)]),
    'GradButton': () => const GradButton(label: 'Submit', icon: Icons.check_rounded),
    'GradButton big': () => const GradButton(label: 'Start Packing', big: true, expand: true),
    'GhostButton': () => const GhostButton(label: 'Excel', icon: Icons.download_rounded),
    'GhostButton danger': () => const GhostButton(label: 'Reopen', danger: true),
    'IconTile': () => const IconTile(icon: Icons.notifications_none_rounded, dot: true),
    'Field': () => const Field(label: 'Packed quantity', required: true, child: TextField()),
    'SpdDropdown': () => SpdDropdown<String>(
          value: 'a',
          items: const [DropdownMenuItem(value: 'a', child: Text('All invoices'))],
          onChanged: (_) {},
        ),
    'FilterBar': () => FilterBar(
          onReset: () {},
          children: const [Field(label: 'Search', bottom: 0, child: TextField())],
        ),
    'AlertBox': () => const AlertBox(
          tone: AlertTone.bad,
          title: 'Warning — exceeds GRN quantity',
          message: 'Cumulative would be 160 vs GRN 140.',
        ),
    'ProgressBar': () => const ProgressBar(percent: 37),
    'BarRow': () => const BarRow(
          label: Text('T-01 · Sandeep'), value: '330 qty · 2 lines · Occupied', percent: 60),
    'RingProgress': () => const RingProgress(percent: 37, label: 'Packed'),
    'SpdTable': () => SpdTable(
          columns: const [SpdCol('Invoice'), SpdCol('Qty', right: true), SpdCol('Detail', wrap: true)],
          rows: [
            SpdRow([strongCell('INV-77001'), monoCell('270'), wrapCell('a wrapping cell')]),
            SpdRow([cell('INV-77002'), monoCell('340'), personCell('Priya Nair')]),
          ],
        ),
    'SpdTable empty': () => const SpdTable(columns: [SpdCol('x')], rows: []),
    'KeyValues': () => const KeyValues([('GRN batch', 'GRN-0909-01'), ('Transactions', '12')]),
    'ListRow': () => const ListRow(children: [Pill('1'), SizedBox(width: 12), Text('step')]),
    'Hairline': () => const Hairline(),
    'SpdChip': () => const SpdChip('Invoice No.', selected: true),
    'DropZone': () => const DropZone(title: 'Drop the GRN export', subtitle: 'or click to browse'),
    'PartCard': () => const PartCard(selected: true, child: Text('90210-ABX')),
    'TableCard': () => const TableCard(child: Text('T-01')),
    'EmailPreview': () => const EmailPreview(
          subject: 'Hourly Status', meta: 'To: spd@…', content: Text('body')),
    'ResponsiveGrid': () => const ResponsiveGrid(
          columns: 4, children: [Text('a'), Text('b'), Text('c'), Text('d')]),
    'SplitPane': () => const SplitPane(main: Text('main'), side: Text('side')),
    'SpdLoader': () => const SpdLoader(label: 'Rendering…'),
    'ErrorPanel': () => const ErrorPanel(message: 'No connection to the SPD server'),
  };

  for (final entry in gallery.entries) {
    for (final light in [false, true]) {
      testWidgets('${entry.key} mounts in ${light ? 'light' : 'dark'}', (tester) async {
        await show(tester, entry.value(), light: light);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
