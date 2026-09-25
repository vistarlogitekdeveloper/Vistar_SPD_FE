import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import 'common.dart';

/// The drill-down the prototype opens when a dashboard row is clicked: every
/// transaction against the line, with the auto-captured start and submit times,
/// and any open exception underneath.
Future<void> showLineDetail(BuildContext context, WidgetRef ref, String lineId) async {
  try {
    final detail = await ref.read(repositoryProvider).line(lineId);
    if (!context.mounted) return;
    final l = detail.line;

    await showSpdModal<void>(
      context,
      title: '${l.partNo} · ${l.partDesc}',
      subtitle: '${l.invoiceNo} · ${l.vendor} · GRN ${nf(l.grnQty)} ${l.uom} · '
          'packed ${nf(l.packed)} · pending ${nf(l.pending)} · ${l.status}',
      wide: true,
      content: (context, setModalState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SpdTable(
          columns: const [
            SpdCol('Txn', width: 92),
            SpdCol('Table', width: 82),
            SpdCol('Member', width: 150),
            SpdCol('Start', width: 96),
            SpdCol('Submit', width: 96),
            SpdCol('Duration', width: 92),
            SpdCol('Qty', right: true, width: 86),
            SpdCol('Pouches', right: true, width: 86),
            SpdCol('Boxes', right: true, width: 80),
            SpdCol('Status', width: 120),
          ],
          rows: [
            for (final t in detail.txns)
              SpdRow([
                monoCell(t.id),
                monoCell(t.tableNo),
                cell(t.memberName),
                monoCell(fmtTs(t.startAt)),
                monoCell(t.submitAt == null ? '—' : fmtTs(t.submitAt)),
                monoCell(t.running ? 'running' : durTxt(t.elapsed)),
                monoCell(t.qty == 0 ? '—' : nf(t.qty), color: Brand.txt, weight: FontWeight.w700),
                monoCell(t.pouches == 0 ? '—' : '${t.pouches}'),
                monoCell(t.boxes == 0 ? '—' : '${t.boxes}'),
                StatusPill(t.status),
              ]),
          ],
          emptyMessage: 'No transactions yet for this line.',
        ),
        for (final e in detail.exceptions.where((e) => !e.resolved)) ...[
          const SizedBox(height: 14),
          AlertBox(tone: AlertTone.bad, title: 'Open exception · ${e.id}', message: e.detail),
        ],
        if (detail.allocations.any((a) => a.reason.isNotEmpty)) ...[
          const SizedBox(height: 14),
          AlertBox(
            tone: AlertTone.info,
            title: 'Split allocation (BR-04)',
            message: detail.allocations.firstWhere((a) => a.reason.isNotEmpty).reason,
          ),
        ],
      ]),
      actions: (context, _) => [GhostButton(label: 'Close', onPressed: () => Navigator.pop(context))],
    );
  } on ApiException catch (e) {
    if (context.mounted) Toast.bad(context, 'Could not open the line', e.message);
  }
}
