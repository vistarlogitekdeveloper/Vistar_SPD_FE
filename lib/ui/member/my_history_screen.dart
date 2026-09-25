import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../widgets/common.dart';

/// Every Start / Submit the member made this shift — one row per transaction,
/// with the times the system captured rather than any the member wrote down.
class MyHistoryScreen extends ConsumerWidget {
  const MyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myHistoryProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHeader(
        crumb: 'My table ·',
        accent: 'History',
        title: 'My submissions',
        blurb: 'Every Start / Submit is a separate transaction with automatic time capture — '
            'nothing on paper, nothing re-typed.',
      ),
      async.when(
        loading: () => const SpdLoader(size: 48),
        error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
        data: (txns) => SpdTable(
          columns: const [
            SpdCol('Txn', width: 92),
            SpdCol('Part', width: 130),
            SpdCol('Invoice', width: 112),
            SpdCol('Start', width: 96),
            SpdCol('Submit', width: 96),
            SpdCol('Duration', width: 96),
            SpdCol('Qty', right: true, width: 90),
            SpdCol('Pouches', right: true, width: 90),
            SpdCol('Boxes', right: true, width: 82),
            SpdCol('Status', width: 124),
          ],
          rows: [
            for (final t in txns)
              SpdRow([
                monoCell(t.id),
                strongCell(t.partNo),
                monoCell(t.invoiceNo),
                monoCell(fmtTs(t.startAt)),
                monoCell(fmtTs(t.submitAt)),
                monoCell(durTxt(t.elapsed)),
                monoCell(nf(t.qty), color: Brand.txt, weight: FontWeight.w700),
                monoCell('${t.pouches}'),
                monoCell('${t.boxes}'),
                StatusPill(t.status),
              ]),
          ],
          emptyMessage: 'You have not submitted anything this shift.',
        ),
      ),
    ]);
  }
}
