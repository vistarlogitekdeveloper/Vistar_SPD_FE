import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../widgets/common.dart';
import '../widgets/part_photos.dart';
import 'config_screen.dart' show PartMasterPanel;

/// FR-3.5 — the part master, and what it has done to the floor.
///
/// It used to be a panel on Masters & Config, which is an Administrator screen,
/// so the two people most likely to ask it a question could not reach it: the
/// Supervisor whose label count surprises them, and Management reading an MIS
/// built on those pouch counts. It has a screen of its own now, open to all
/// three; replacing the master stays with the Administrator and the Supervisor.
///
/// The master itself is three columns — part number, description, MOQ — because
/// that is the whole of what it is. Everything else about a part belongs to the
/// GRN, so it is answered per part rather than copied in: open a row and it
/// says which invoices carried it, when, how much arrived and how many pouches
/// the MOQ made of that.
class PartMasterScreen extends ConsumerStatefulWidget {
  const PartMasterScreen({super.key});

  @override
  ConsumerState<PartMasterScreen> createState() => _PartMasterScreenState();
}

class _PartMasterScreenState extends ConsumerState<PartMasterScreen> {
  late final TextEditingController _q =
      TextEditingController(text: ref.read(partSearchProvider));

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(partMasterProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        crumb: 'Masters ·',
        accent: 'Part Master',
        title: 'Pack size per part',
        blurb: 'The MOQ is the number of pieces that go in one pouch, so it decides how many '
            'labels a GRN line becomes. The SAP export carries no MOQ column — this is where '
            'it comes from. Open a part to see which invoices have carried it.',
      ),

      // Upload and the counts. The panel shows itself only to the roles that
      // may replace the master, and draws the summary for the rest.
      const PartMasterPanel(),
      const SizedBox(height: 24),

      FilterBar(
        onReset: _q.text.isEmpty
            ? null
            : () {
                _q.clear();
                ref.read(partSearchProvider.notifier).set('');
              },
        children: [
          Field(
            label: 'Search',
            bottom: 0,
            child: TextField(
              controller: _q,
              style: body(size: 13),
              decoration: const InputDecoration(hintText: 'Part number or description…'),
              onChanged: (v) => ref.read(partSearchProvider.notifier).set(v),
            ),
          ),
        ],
      ),

      async.when(
        skipLoadingOnReload: true,
        loading: () => const SpdLoader(size: 48),
        error: (e, _) {
          /* A console in front of a backend that has not taken these routes
             yet gets a 404, and so does one whose user may not read the
             master. Neither is something the person looking at it can act on
             by retrying, so both say what happened. */
          if (e is ApiException && e.statusCode == 403) {
            return const AlertBox(
              tone: AlertTone.warn,
              title: 'Not available to your role',
              message: 'The part master is open to an Administrator, a Supervisor and '
                  'Management.',
            );
          }
          return ErrorPanel(message: '$e', onRetry: () => ref.invalidate(partMasterProvider));
        },
        data: (page) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (page.shown < page.total) ...[
            BlurbText([
              ('Showing ${nf(page.shown)} of ${nf(page.total)} matching parts', true),
              (' — narrow the search to see the rest.', false),
            ]),
            const SizedBox(height: 12),
          ],
          SpdTable(
            columns: const [
              SpdCol('Part Number', width: 190),
              SpdCol('Description', width: 360, wrap: true),
              SpdCol('MOQ', right: true, width: 110),
              SpdCol('', right: true, width: 150),
            ],
            rows: [
              for (final p in page.parts)
                SpdRow(
                  [
                    strongCell('${p['part_no']}'),
                    wrapCell('${p['description'] ?? ''}'),
                    monoCell(p['moq'] == null ? '—' : nf(p['moq'])),
                    GhostButton(
                      label: 'Invoices',
                      icon: Icons.receipt_long_outlined,
                      onPressed: () => showPartLines(context, ref, '${p['part_no']}'),
                    ),
                  ],
                  onTap: () => showPartLines(context, ref, '${p['part_no']}'),
                ),
            ],
            emptyMessage: 'No part matches that search.',
          ),
        ]),
      ),
    ]);
  }
}

/// Which invoices have carried a part, when, and what the MOQ made of them.
Future<void> showPartLines(BuildContext context, WidgetRef ref, String partNo) async {
  ({Map<String, dynamic> part, List<Map<String, dynamic>> lines, Map<String, dynamic> totals})? data;
  String? error;
  try {
    data = await ref.read(repositoryProvider).partMasterLines(partNo);
  } on ApiException catch (e) {
    error = e.message;
  }
  if (!context.mounted) return;

  if (error != null) {
    Toast.bad(context, 'Could not read that part', error);
    return;
  }

  final part = data!.part;
  final lines = data.lines;
  final t = data.totals;

  await showSpdModal<void>(
    context,
    wide: true,
    title: '${part['part_no']}',
    subtitle: '${part['description'] ?? ''}'
        '${part['moq'] == null ? '' : '  ·  MOQ ${nf(part['moq'])} per pouch'}',
    content: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KeyValues([
        ('Invoices', nf(t['invoices'] ?? 0)),
        ('GRN lines', nf(t['lines'] ?? 0)),
        ('Quantity received', nf(t['quantity'] ?? 0)),
        ('Pouches created', nf(t['pouches'] ?? 0)),
      ]),
      const SizedBox(height: 16),
      /* FR-3.6 — photographs are keyed by the code the GRN carried, so the
         family's are those of the master code and of every variant its lines
         carried. */
      PartPhotoGallery(partNos: {
        '${part['part_no']}',
        for (final l in lines) '${l['part_no']}'.trim().toUpperCase(),
      }.toList()),
      const SizedBox(height: 16),
      if (lines.isEmpty)
        const AlertBox(
          tone: AlertTone.info,
          title: 'No GRN has carried this part yet',
          message: 'It is in the master, so the next receipt that names it will be split '
              'by its MOQ.',
        )
      else
        SpdTable(
          maxHeight: 340,
          columns: const [
            SpdCol('Invoice', width: 150),
            SpdCol('GRN Date', width: 120),
            SpdCol('Part on the GRN', width: 160),
            SpdCol('Quantity', right: true, width: 120),
            SpdCol('Pouches', right: true, width: 110),
            SpdCol('Shift', width: 180),
          ],
          rows: [
            for (final l in lines)
              SpdRow([
                strongCell('${l['invoice_no']}'),
                monoCell(fmtD('${l['grn_date']}')),
                /* The code the GRN actually carried, which is the master's
                   plus a two-character variant. Shown rather than hidden: it
                   is why this line is on this part's list at all. */
                monoCell('${l['part_no']}'),
                monoCell('${nf(l['grn_qty'])} ${l['uom'] ?? ''}'),
                monoCell(nf(l['label_count'] ?? 1)),
                cell('${l['shift_label'] ?? l['shift_id']}'),
              ]),
          ],
        ),
    ]),
    actions: (context, _) => [
      GhostButton(label: 'Close', onPressed: () => Navigator.pop(context)),
    ],
  );
}
