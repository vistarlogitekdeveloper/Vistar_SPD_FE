import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/downloads.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../widgets/common.dart';
import '../widgets/label_card.dart';
import '../widgets/pdf_preview_dialog.dart';

/// UC-02 / FR-3 — generate, preview and print the ID label, with the reprint
/// reason BR-09 requires.
class LabelsScreen extends ConsumerStatefulWidget {
  const LabelsScreen({super.key});

  @override
  ConsumerState<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends ConsumerState<LabelsScreen> {
  /// Which invoice the sheet covers. Empty is the whole shift, which on a real
  /// GRN is usually more labels than one sheet will carry — see the advisory
  /// below.
  String _invoice = '';

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(linesProvider);
    final log = ref.watch(labelLogProvider);
    final shiftId = ref.watch(selectedShiftProvider);
    final cap = ref.watch(configProvider).value?.maxSheetLabels ?? 0;

    final page = lines.value;
    final scoped = page == null
        ? const <GrnLine>[]
        : (_invoice.isEmpty
            ? page.lines
            : page.lines.where((l) => l.invoiceNo == _invoice).toList());
    // FR-3.5 — labels, not lines. A split line prints more than one page, and
    // this is the number a Supervisor sizes label stock from.
    final count = scoped.fold<int>(0, (n, l) => n + l.labelCount);
    /* The sheet the server will refuse is the one the console must not offer.
       MOQ 1 means one pouch per piece, so a whole shift is tens of thousands
       of labels: 517 lines came to 31,398 against a ceiling of 5,000. The
       button used to advertise that exact number and then fail on every
       press. */
    final overCap = cap > 0 && count > cap;
    final blocked = shiftId == null || count == 0 || overCap;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        crumb: 'GRN ·',
        accent: 'ID Labels',
        title: 'ID label print & preview',
        blurb: 'Labels carry the part number, its description, the invoice, the quantity in '
            'the pouch, the packer and the GRN date, with a scannable QR — generated from '
            'the imported data, never typed. Reprints are audit-logged (BR-09).',
        actions: [
          GhostButton(
            label: 'Save sheet (PDF)',
            icon: Icons.download_rounded,
            onPressed: blocked ? null : () => _saveSheet(context, ref, shiftId),
          ),
          GradButton(
            label: 'Print sheet · ${nf(count)}',
            icon: Icons.print_outlined,
            small: true,
            onPressed: blocked ? null : () => _printSheet(context, ref, shiftId, count),
          ),
        ],
      ),

      /* The scope. A sheet is carried to one bench for one invoice, which is
         how the floor already works and is also the only size that prints —
         so this is the control that makes the buttons above usable rather
         than a filter someone might think to reach for. */
      FilterBar(
        onReset: _invoice.isEmpty ? null : () => setState(() => _invoice = ''),
        children: [
          Field(
            label: 'Sheet covers',
            bottom: 0,
            child: SpdDropdown<String>(
              dense: true,
              value: _invoice,
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text('Whole shift · ${nf(page?.lines.fold<int>(0, (n, l) => n + l.labelCount) ?? 0)} labels'),
                ),
                for (final i in page?.invoices ?? const <String>[])
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      '$i · ${nf(page!.lines.where((l) => l.invoiceNo == i).fold<int>(0, (n, l) => n + l.labelCount))} labels',
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _invoice = v ?? ''),
            ),
          ),
        ],
      ),

      if (overCap) ...[
        AlertBox(
          tone: AlertTone.warn,
          title: '${nf(count)} labels is more than one sheet carries (${nf(cap)})',
          message: 'Every piece gets its own pouch, so a shift runs to tens of thousands of '
              'labels. Pick an invoice above and the sheet prints for that invoice — which is '
              'how it reaches the bench anyway. A single line prints from its own row below.',
        ),
        const SizedBox(height: 16),
      ],

      lines.when(
        skipLoadingOnReload: true,
        loading: () => const SpdLoader(size: 48),
        error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
        data: (page) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final l in page.lines.take(6)) _LabelTile(line: l),
            ],
          ),
          if (page.lines.length > 6) ...[
            const SizedBox(height: 14),
            Text(
              '+ ${page.lines.length - 6} more available from the Lines screen or the bulk print sheet.',
              style: body(size: 12, color: Brand.txt3),
            ),
          ],
        ]),
      ),

      const SizedBox(height: 24),
      const SectionTitle('Print log', trailing: 'reprints require a reason'),
      log.when(
        skipLoadingOnReload: true,
        loading: () => const SpdLoader(size: 40, fill: false),
        error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
        data: (prints) => SpdTable(
          columns: const [
            SpdCol('Part', width: 140),
            SpdCol('Invoice', width: 120),
            SpdCol('Copies', right: true, width: 88),
            SpdCol('Printed at', width: 140),
            SpdCol('By', width: 160),
            SpdCol('Reprint reason', width: 280, wrap: true),
          ],
          rows: [
            for (final p in prints.take(14))
              SpdRow([
                strongCell(p.partNo),
                monoCell(p.invoiceNo),
                monoCell('${p.copies}'),
                monoCell(fmtTs(p.printedAt)),
                cell(p.printedByName),
                p.reason.isEmpty
                    ? Text('first print', style: body(size: 13, color: Brand.txt3))
                    : wrapCell(p.reason),
              ]),
          ],
          emptyMessage: 'No labels printed yet.',
        ),
      ),
    ]);
  }

  /// The file name a sheet is saved under, so a Supervisor with four of them
  /// in a downloads folder can tell which invoice each one is.
  String _fileName(String shiftId) => _invoice.isEmpty
      ? 'SPD_ID_LABELS_$shiftId.pdf'
      : 'SPD_ID_LABELS_${shiftId}_${_invoice.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}.pdf';

  Future<void> _saveSheet(BuildContext context, WidgetRef ref, String shiftId) async {
    try {
      final bytes = await ref
          .read(repositoryProvider)
          .labelSheetPdf(shiftId: shiftId, invoice: _invoice);
      final name = _fileName(shiftId);
      await saveBytes(filename: name, bytes: bytes, mime: 'application/pdf');
      if (context.mounted) Toast.ok(context, 'Label sheet saved', '$name is in your downloads.');
    } on ApiException catch (e) {
      if (context.mounted) Toast.bad(context, 'Could not build the sheet', e.message);
    }
  }

  Future<void> _printSheet(BuildContext context, WidgetRef ref, String shiftId, int count) async {
    try {
      final bytes = await ref
          .read(repositoryProvider)
          .labelSheetPdf(shiftId: shiftId, invoice: _invoice);
      if (!context.mounted) return;
      // Previewed before it reaches the printer — label stock is consumable,
      // and a sheet that goes straight to the OS dialog is one nobody has seen.
      await showPdfPreviewDialog(
        context,
        title: _invoice.isEmpty ? 'ID label sheet' : 'ID label sheet · $_invoice',
        subtitle: '${nf(count)} label${count == 1 ? '' : 's'} · check the sheet, then send it to the label printer',
        fileName: _fileName(shiftId),
        bytes: bytes,
      );
    } on ApiException catch (e) {
      if (context.mounted) Toast.bad(context, 'Could not build the sheet', e.message);
    }
  }
}

/// One preview tile with its own "Print" link, as in the prototype.
class _LabelTile extends ConsumerWidget {
  const _LabelTile({required this.line});

  final GrnLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 330,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(
            child: Text('${line.partNo} · ${line.invoiceNo}',
                style: body(size: 11, color: Brand.txt3), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => showLabelDialog(context, ref, line.id),
            // The prototype's "Print ↗" uses U+2197, which neither Manrope nor
            // Bricolage carries — it was the one glyph still pulling a Noto
            // fallback font off the internet. A bundled Material icon says the
            // same thing and ships with the app.
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Print', style: body(size: 11, weight: FontWeight.w700, color: Brand.pink)),
              const SizedBox(width: 2),
              Icon(Icons.north_east_rounded, size: 11, color: Brand.pink),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        ref.watch(labelPreviewProvider(line.id)).when(
          loading: () => Container(
            height: 150,
            decoration: BoxDecoration(
                color: Brand.surface2, borderRadius: BorderRadius.circular(6)),
          ),
          error: (e, _) => Container(
            height: 150,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Brand.surface2, borderRadius: BorderRadius.circular(6)),
            child: Text('Preview unavailable',
                style: body(size: 11, color: Brand.txt3)),
          ),
          data: (p) {
            // FR-3.5 — a line with an MOQ prints one label per pack, so the
            // preview has to show that it is more than one.
            //
            // It no longer draws EVERY one. A piece-level line on a large GRN
            // runs to thousands of labels, each carrying a QR code, and this
            // sits inside the page's own scroll view where nothing is
            // virtualised: laying them all out is what froze the screen. The
            // requirement is that the preview does not pretend a line prints a
            // single label, and a few plus a count says that just as plainly.
            const shown = 3;
            final visible = p.labels.take(shown).toList();
            return Column(children: [
              for (final u in visible) ...[
                LabelCard(preview: p, unit: u),
                if (u != visible.last) const SizedBox(height: 10),
              ],
              if (p.labels.length > shown) ...[
                const SizedBox(height: 10),
                Text(
                  '+ ${nf(p.labels.length - shown)} more label(s) print for this line.',
                  style: body(size: 11, color: Brand.txt3),
                ),
              ],
            ]);
          },
        ),
      ]),
    );
  }
}

/// How many sticker cards the print dialog draws before it starts counting.
///
/// Twelve rather than all of them, for the reason the tile preview stops at
/// three: each card carries a QR drawn module by module, the dialog's column
/// virtualises nothing, and a line of 484 pieces at an MOQ of 1 is 484 of them
/// — which is a frozen screen, not a preview. Twelve fills the dialog, so what
/// is being checked (does the label say the right thing) is still checkable.
const int _kCardsShown = 12;

/// The copies box as a number, defaulting to one.
///
/// An empty or nonsense box means one rather than nothing: the field exists
/// to ask for more than one, so the absence of an answer is the ordinary
/// case. The server clamps the upper end — it is the side that knows what a
/// sheet costs to render.
int _copiesOf(String s) {
  final n = int.tryParse(s.trim());
  return n == null || n < 1 ? 1 : n;
}

/// "140 pouches of 25, and one of 12" rather than "25 + 25 + 25 + …".
///
/// The split used to be spelled out term by term, which is readable for the
/// 300-and-50 case it was written for and is a hundred copies of "1 + " for
/// a line packed one piece to a pouch — the common case once the master
/// began supplying an MOQ of 1. What the Supervisor needs to see is that the
/// line does not print one label, and how the remainder fell.
String _splitBlurb(List<LabelUnit> labels) {
  if (labels.isEmpty) return 'no labels';
  final full = labels.first.qty;
  final tail = labels.last.qty;
  final n = labels.length;
  if (n == 1) return '${nf(full)} in one pouch';
  if (tail == full) return '$n pouches of ${nf(full)}';
  return '${n - 1} pouches of ${nf(full)} and one of ${nf(tail)}';
}

/// UC-02 — the print dialog. The server decides whether this is a reprint, so
/// the reason requirement of BR-09 cannot be sidestepped by the client.
Future<void> showLabelDialog(BuildContext context, WidgetRef ref, String lineId) async {
  final LabelPreview preview;
  try {
    preview = await ref.read(repositoryProvider).labelPreview(lineId);
  } on ApiException catch (e) {
    if (context.mounted) Toast.bad(context, 'Could not build the label', e.message);
    return;
  }
  if (!context.mounted) return;

  final reasons = [
    'Label damaged / torn',
    'Label lost in transit to table',
    'Print quality unreadable',
  ];
  String? reason;
  /* FR-3.3 — how many times to print this run.

     Not a quantity of pieces and not a number of pouches: both of those
     are facts about the GRN line that the MOQ has already decided. This
     is how many times the same set of stickers comes out, which is the
     thing the floor was going back to the printer dialog for. */
  final copies = TextEditingController(text: '1');

  await showSpdModal<void>(
    context,
    title: preview.alreadyPrinted ? 'Reprint ID label' : 'Print ID label',
    subtitle: '${preview.line.partNo} · ${preview.line.invoiceNo} · sent to ${preview.template}',
    content: (context, setModalState) => Column(children: [
      if (preview.labels.length > 1) ...[
        AlertBox(
          tone: AlertTone.info,
          title: 'This line prints ${nf(preview.labels.length)} labels (FR-3.5)',
          message: 'MOQ ${nf(preview.line.moq ?? 0)} against a GRN quantity of '
              '${nf(preview.line.grnQty)} ${preview.line.uom} — ${_splitBlurb(preview.labels)}.',
        ),
        const SizedBox(height: 14),
      ],
      /* Above the stickers, not below them. A line packed one piece to a pouch
         is hundreds of cards, and a control placed after them is a control
         nobody scrolls to — the same reason the tile preview stopped drawing
         every label. Copies is the thing being decided here; the cards are
         what is being checked. */
      Field(
        label: 'Copies',
        hint: 'How many times to print this set of ${nf(preview.labels.length)} label(s)',
        bottom: 0,
        child: TextField(
          controller: copies,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: mono(size: 14),
          decoration: const InputDecoration(hintText: '1'),
        ),
      ),
      const SizedBox(height: 18),
      Center(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            for (final u in preview.labels.take(_kCardsShown))
              LabelCard(preview: preview, unit: u),
          ],
        ),
      ),
      if (preview.labels.length > _kCardsShown) ...[
        const SizedBox(height: 10),
        Center(
          child: Text(
            '+ ${nf(preview.labels.length - _kCardsShown)} more label(s) print for this line.',
            style: body(size: 12, color: Brand.txt3),
          ),
        ),
      ],
      if (preview.alreadyPrinted) ...[
        const SizedBox(height: 18),
        Field(
          label: 'Reprint reason (BR-09)',
          required: true,
          bottom: 0,
          child: SpdDropdown<String>(
            value: reason,
            items: [
              const DropdownMenuItem(value: null, child: Text('Select…')),
              for (final r in reasons) DropdownMenuItem(value: r, child: Text(r)),
            ],
            onChanged: (v) => setModalState(() => reason = v),
          ),
        ),
      ],
    ]),
    actions: (context, _) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
      GhostButton(
        label: 'Save PDF',
        icon: Icons.download_rounded,
        onPressed: () async {
          final bytes = await ref
              .read(repositoryProvider)
              .labelSheetPdf(lineId: lineId, copies: _copiesOf(copies.text));
          await saveBytes(
            filename: 'SPD_LABEL_${preview.line.partNo}.pdf',
            bytes: bytes,
            mime: 'application/pdf',
          );
        },
      ),
      GradButton(
        label: preview.alreadyPrinted ? 'Reprint label' : 'Print label',
        icon: Icons.sell_outlined,
        small: true,
        onPressed: () async {
          if (preview.alreadyPrinted && (reason == null || reason!.isEmpty)) {
            Toast.bad(context, 'Reason required', 'A reprint must be logged with a reason (BR-09).');
            return;
          }
          final n = _copiesOf(copies.text);
          try {
            final wasReprint = await ref.read(repositoryProvider).printLabel(
                  lineId: lineId,
                  copies: n,
                  reason: reason ?? '',
                );
            final bytes = await ref
                .read(repositoryProvider)
                .labelSheetPdf(lineId: lineId, copies: n);
            if (context.mounted) Navigator.pop(context);
            if (context.mounted) {
              await showPdfPreviewDialog(
                context,
                title: wasReprint ? 'Reprint ${preview.line.partNo}' : 'Print ${preview.line.partNo}',
                subtitle: '${preview.line.invoiceNo} · ${preview.template}',
                fileName: 'SPD_LABEL_${preview.line.partNo}.pdf',
                bytes: bytes,
              );
            }
            invalidateAll(ref);
            if (context.mounted) {
              Toast.ok(
                context,
                wasReprint ? 'Label reprinted' : 'Label printed',
                '${preview.line.partNo} sent to the label printer'
                    '${wasReprint ? ' — reason logged in the audit trail' : ''}.',
              );
            }
          } on ApiException catch (e) {
            if (context.mounted) Toast.bad(context, 'Print refused', e.message);
          }
        },
      ),
    ],
  );
}
