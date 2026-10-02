import 'package:flutter/material.dart';
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
class LabelsScreen extends ConsumerWidget {
  const LabelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(linesProvider);
    final log = ref.watch(labelLogProvider);
    final shiftId = ref.watch(selectedShiftProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        crumb: 'GRN ·',
        accent: 'ID Labels',
        title: 'ID label print & preview',
        blurb: 'Labels carry part number, description, invoice, GRN quantity, GRN date and a '
            'scannable QR — generated from the imported data, never typed. Reprints are '
            'audit-logged with a reason (BR-09).',
        actions: [
          GhostButton(
            label: 'Save sheet (PDF)',
            icon: Icons.download_rounded,
            onPressed: shiftId == null ? null : () => _saveSheet(context, ref, shiftId),
          ),
          GradButton(
            // FR-3.5 — labels, not lines. A split line prints more than one
            // page, and this is the number a Supervisor sizes label stock from.
            label: 'Print sheet · ${lines.value?.lines.fold<int>(0, (n, l) => n + l.labelCount) ?? 0}',
            icon: Icons.print_outlined,
            small: true,
            onPressed: shiftId == null ? null : () => _printSheet(context, ref, shiftId),
          ),
        ],
      ),

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

  Future<void> _saveSheet(BuildContext context, WidgetRef ref, String shiftId) async {
    try {
      final bytes = await ref.read(repositoryProvider).labelSheetPdf(shiftId: shiftId);
      await saveBytes(filename: 'SPD_ID_LABELS_$shiftId.pdf', bytes: bytes, mime: 'application/pdf');
      if (context.mounted) {
        Toast.ok(context, 'Label sheet saved', 'SPD_ID_LABELS_$shiftId.pdf is in your downloads.');
      }
    } on ApiException catch (e) {
      if (context.mounted) Toast.bad(context, 'Could not build the sheet', e.message);
    }
  }

  Future<void> _printSheet(BuildContext context, WidgetRef ref, String shiftId) async {
    try {
      final bytes = await ref.read(repositoryProvider).labelSheetPdf(shiftId: shiftId);
      final count = ref.read(linesProvider).value?.lines.length ?? 0;
      if (!context.mounted) return;
      // Previewed before it reaches the printer — label stock is consumable,
      // and a sheet that goes straight to the OS dialog is one nobody has seen.
      await showPdfPreviewDialog(
        context,
        title: 'ID label sheet',
        subtitle: '$count label${count == 1 ? '' : 's'} · check the sheet, then send it to the label printer',
        fileName: 'SPD_ID_LABELS_$shiftId.pdf',
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
        FutureBuilder<LabelPreview>(
          future: ref.read(repositoryProvider).labelPreview(line.id),
          builder: (context, snap) {
            if (!snap.hasData) {
              return Container(
                height: 150,
                decoration: BoxDecoration(color: Brand.surface2, borderRadius: BorderRadius.circular(6)),
              );
            }
            // FR-3.5 — a line with an MOQ prints one label per pack, so the
            // preview shows all of them rather than only the first.
            final p = snap.data!;
            return Column(children: [
              for (final u in p.labels) ...[
                LabelCard(preview: p, unit: u),
                if (u != p.labels.last) const SizedBox(height: 10),
              ],
            ]);
          },
        ),
      ]),
    );
  }
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

  await showSpdModal<void>(
    context,
    title: preview.alreadyPrinted ? 'Reprint ID label' : 'Print ID label',
    subtitle: '${preview.line.partNo} · ${preview.line.invoiceNo} · sent to ${preview.template}',
    content: (context, setModalState) => Column(children: [
      if (preview.labels.length > 1) ...[
        AlertBox(
          tone: AlertTone.info,
          title: 'This line prints ${preview.labels.length} labels (FR-3.5)',
          message: 'MOQ ${nf(preview.line.moq ?? 0)} against a GRN quantity of '
              '${nf(preview.line.grnQty)} ${preview.line.uom} — '
              '${preview.labels.map((u) => nf(u.qty)).join(' + ')}.',
        ),
        const SizedBox(height: 14),
      ],
      Center(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [for (final u in preview.labels) LabelCard(preview: preview, unit: u)],
        ),
      ),
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
          final bytes = await ref.read(repositoryProvider).labelSheetPdf(lineId: lineId);
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
          try {
            final wasReprint = await ref.read(repositoryProvider).printLabel(
                  lineId: lineId,
                  reason: reason ?? '',
                );
            final bytes = await ref.read(repositoryProvider).labelSheetPdf(lineId: lineId);
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
