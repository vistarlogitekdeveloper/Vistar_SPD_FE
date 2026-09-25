import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/downloads.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../widgets/common.dart';

/// UC-08 / FR-10 — lines packed, pouches, boxes and pending quantity, sliced
/// part-, invoice-, table- and member-wise, exportable to Excel or CSV.
class MisScreen extends ConsumerWidget {
  const MisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(misProvider);
    final facets = ref.watch(facetsProvider).value;
    final f = ref.watch(misFilterProvider);

    return async.when(
      loading: () => const Padding(padding: EdgeInsets.only(top: 80), child: SpdLoader()),
      error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
      data: (page) {
        final st = page.stats;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PageHeader(
            crumb: 'Reports ·',
            accent: 'MIS',
            title: 'MIS report',
            blurbWidget: BlurbText([
              ('Lines packed, pouches, boxes and pending quantity — generated automatically on the '
                  'Supervisor’s final submission (FR-10.1)', false),
              if (page.provisional) (', shown here in ', false),
              if (page.provisional) ('provisional', true),
              if (page.provisional) (' form until then (BR-07)', false),
              ('. Sliceable date-wise, invoice-wise, part-wise, table-wise and member-wise.', false),
            ]),
            actions: [
              GhostButton(
                label: 'Excel',
                icon: Icons.download_rounded,
                onPressed: () => _export(context, ref, 'xlsx', f),
              ),
              GhostButton(
                label: 'CSV',
                icon: Icons.download_rounded,
                onPressed: () => _export(context, ref, 'csv', f),
              ),
            ],
          ),

          Wrap(spacing: 9, runSpacing: 9, children: [
            if (page.provisional)
              const Pill('PROVISIONAL — shift not yet finalised', tone: PillTone.amber)
            else
              Pill(
                'FINAL · generated ${fmtTs(page.snapshots.isEmpty ? page.shift.finalAt : page.snapshots.first.generatedAt)}',
                tone: PillTone.ok,
              ),
            Pill(page.shift.label, tone: PillTone.violet),
          ]),
          const SizedBox(height: 14),

          ResponsiveGrid(columns: 4, children: [
            KpiCard(
              icon: Icons.format_list_bulleted_rounded,
              value: '${st.linesPacked}',
              caption: 'Lines packed',
              gradient: true,
            ),
            KpiCard(icon: Icons.inventory_2_outlined, value: nf(st.pouches), caption: 'Pouches'),
            KpiCard(icon: Icons.all_inbox_rounded, value: nf(st.boxes), caption: 'Boxes'),
            KpiCard(icon: Icons.schedule_rounded, value: nf(st.pending), caption: 'Pending quantity'),
          ]),
          const SizedBox(height: 18),

          FilterBar(
            onReset: () => ref.read(misFilterProvider.notifier).set(const MisFilter()),
            children: [
              Field(
                label: 'View',
                bottom: 0,
                child: SpdDropdown<String>(
                  dense: true,
                  value: f.dim,
                  items: const [
                    DropdownMenuItem(value: 'line', child: Text('Part-number-wise')),
                    DropdownMenuItem(value: 'inv', child: Text('Invoice-wise')),
                    DropdownMenuItem(value: 'table', child: Text('Table-wise')),
                    DropdownMenuItem(value: 'member', child: Text('Member-wise')),
                  ],
                  onChanged: (v) =>
                      ref.read(misFilterProvider.notifier).set(f.copyWith(dim: v ?? 'line')),
                ),
              ),
              Field(
                label: 'Invoice',
                bottom: 0,
                child: SpdDropdown<String>(
                  dense: true,
                  value: f.invoice,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All')),
                    for (final i in facets?.invoices ?? const <String>[])
                      DropdownMenuItem(value: i, child: Text(i)),
                  ],
                  onChanged: (v) =>
                      ref.read(misFilterProvider.notifier).set(f.copyWith(invoice: v ?? '')),
                ),
              ),
              Field(
                label: 'Table',
                bottom: 0,
                child: SpdDropdown<String>(
                  dense: true,
                  value: f.table,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All')),
                    for (final t in facets?.tables ?? const <String>[])
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) =>
                      ref.read(misFilterProvider.notifier).set(f.copyWith(table: v ?? '')),
                ),
              ),
              Field(
                label: 'Member',
                bottom: 0,
                child: SpdDropdown<String>(
                  dense: true,
                  value: f.member,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All')),
                    for (final m in facets?.members ?? const <Map<String, dynamic>>[])
                      DropdownMenuItem(value: '${m['id']}', child: Text('${m['name']}')),
                  ],
                  onChanged: (v) =>
                      ref.read(misFilterProvider.notifier).set(f.copyWith(member: v ?? '')),
                ),
              ),
            ],
          ),

          _MisTable(page: page),

          const SizedBox(height: 24),
          const SectionTitle('Generated MIS snapshots'),
          SpdTable(
            columns: const [
              SpdCol('Report', width: 116),
              SpdCol('Shift', width: 190),
              SpdCol('Generated on', width: 180),
              SpdCol('Lines', right: true, width: 80),
              SpdCol('Pouches', right: true, width: 92),
              SpdCol('Boxes', right: true, width: 84),
              SpdCol('Packed', right: true, width: 96),
              SpdCol('Pending', right: true, width: 96),
            ],
            rows: [
              for (final m in page.snapshots)
                SpdRow([
                  strongCell(m.id),
                  cell(m.shiftLabel),
                  monoCell(fmtDateTime(m.generatedAt)),
                  monoCell('${m.linesPacked}'),
                  monoCell(nf(m.pouches)),
                  monoCell(nf(m.boxes)),
                  monoCell(nf(m.packed)),
                  monoCell(nf(m.pending)),
                ]),
            ],
            emptyMessage: 'No MIS generated yet — it is created automatically on final submission.',
          ),
        ]);
      },
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref, String format, MisFilter f) async {
    final shiftId = ref.read(selectedShiftProvider);
    if (shiftId == null) return;
    try {
      final bytes = await ref.read(repositoryProvider).export(
        key: 'mis',
        format: format,
        query: {'shiftId': shiftId, 'invoice': f.invoice, 'table': f.table, 'member': f.member},
      );
      final shift = ref.read(currentShiftProvider);
      final name = 'SPD_MIS_${shift?.date ?? shiftId}.$format';
      await saveBytes(
        filename: name,
        bytes: bytes,
        mime: format == 'csv' ? 'text/csv' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (context.mounted) {
        Toast.ok(context, '${format.toUpperCase()} export ready', '$name is in your downloads.');
      }
    } on ApiException catch (e) {
      if (context.mounted) Toast.warn(context, 'Nothing exported', e.message);
    }
  }
}

/// The table changes shape with the selected dimension, exactly as the
/// prototype's `misTable()` does.
class _MisTable extends StatelessWidget {
  const _MisTable({required this.page});

  final MisPage page;

  @override
  Widget build(BuildContext context) {
    if (page.dim == 'line') {
      return SpdTable(
        columns: const [
          SpdCol('Invoice', width: 108),
          SpdCol('Part Number', width: 128),
          SpdCol('Description', width: 210),
          SpdCol('GRN Qty', right: true, width: 96),
          SpdCol('Packed', right: true, width: 92),
          SpdCol('Pending', right: true, width: 92),
          SpdCol('Pouches', right: true, width: 90),
          SpdCol('Boxes', right: true, width: 82),
          SpdCol('Tables', width: 106),
          SpdCol('Status', width: 126),
        ],
        rows: [
          for (final r in page.rows)
            SpdRow([
              monoCell(r.invoiceNo),
              strongCell(r.partNo),
              cell(r.partDesc),
              monoCell(nf(r.grnQty)),
              monoCell(nf(r.packed), color: Brand.txt, weight: FontWeight.w700),
              monoCell(nf(r.pending)),
              monoCell('${r.pouches}'),
              monoCell('${r.boxes}'),
              monoCell(r.tables.isEmpty ? '—' : r.tables.join(', ')),
              StatusPill(r.status),
            ]),
        ],
        emptyMessage: 'No transactions match the selected filters.',
      );
    }

    if (page.dim == 'inv') {
      return SpdTable(
        columns: const [
          SpdCol('Invoice', width: 140),
          SpdCol('Lines', right: true, width: 90),
          SpdCol('Txns', right: true, width: 90),
          SpdCol('Packed Qty', right: true, width: 120),
          SpdCol('Pouches', right: true, width: 100),
          SpdCol('Boxes', right: true, width: 96),
        ],
        rows: [
          for (final r in page.rows)
            SpdRow([
              strongCell(r.key),
              monoCell('${r.lines}'),
              monoCell('${r.txns}'),
              monoCell(nf(r.qty), color: Brand.txt, weight: FontWeight.w700),
              monoCell(nf(r.pouches)),
              monoCell(nf(r.boxes)),
            ]),
        ],
        emptyMessage: 'No transactions match the selected filters.',
      );
    }

    final memberWise = page.dim == 'member';
    return SpdTable(
      columns: [
        SpdCol(memberWise ? 'Member' : 'Table', width: memberWise ? 200 : 110),
        SpdCol(memberWise ? 'Table' : 'Member', width: memberWise ? 110 : 190),
        const SpdCol('Lines', right: true, width: 88),
        const SpdCol('Txns', right: true, width: 88),
        const SpdCol('Packed Qty', right: true, width: 118),
        const SpdCol('Pouches', right: true, width: 98),
        const SpdCol('Boxes', right: true, width: 92),
      ],
      rows: [
        for (final r in page.rows)
          SpdRow([
            memberWise ? personCell(r.label) : strongCell(r.key),
            memberWise ? monoCell(r.tableNo ?? '—') : cell(r.memberName ?? '—'),
            monoCell('${r.lines}'),
            monoCell('${r.txns}'),
            monoCell(nf(r.qty), color: Brand.txt, weight: FontWeight.w700),
            monoCell(nf(r.pouches)),
            monoCell(nf(r.boxes)),
          ]),
      ],
      emptyMessage: 'No transactions match the selected filters.',
    );
  }
}
