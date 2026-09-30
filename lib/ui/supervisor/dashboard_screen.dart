import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../widgets/common.dart';
import '../widgets/line_detail.dart';

/// UC-09 / FR-11 — the real-time dashboard: headline reconciliation, table- and
/// member-wise productivity, and the colour-coded invoice/part status.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    final role = ref.watch(viewRoleProvider);

    return async.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(padding: EdgeInsets.only(top: 80), child: SpdLoader()),
      error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
      data: (d) => _Body(data: d, role: role),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data, required this.role});

  final DashboardPage data;
  final String role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = data.stats;
    final maxTableQty = data.tables.fold<num>(1, (m, t) => t.packed > m ? t.packed : m);
    final maxMemberQty = data.members.fold<num>(1, (m, x) => x.qty > m ? x.qty : m);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        crumb: 'Overview ·',
        accent: 'Live Dashboard',
        title: 'SPD pre-packing dashboard',
        blurbWidget: BlurbText([
          (data.shift.label, true),
          (' · ${data.shift.status} · auto-refresh ${data.refreshSeconds}s · last updated ', false),
          (fmtTs(data.generatedAt.toIso8601String()), true),
          ('. Toggle ', false),
          ('Floor live', true),
          (' in the top bar to keep it current as tables submit.', false),
        ]),
        actions: [
          GhostButton(label: 'Refresh', icon: Icons.refresh_rounded, onPressed: () => invalidateAll(ref)),
          if (role == 'supervisor')
            GradButton(
              label: 'Review & finalise',
              icon: Icons.visibility_outlined,
              small: true,
              onPressed: () => context.go('/review'),
            ),
        ],
      ),

      // FR-11.1 — the headline reconciliation tiles.
      ResponsiveGrid(columns: 3, children: [
        KpiCard(icon: Icons.storage_rounded, value: nf(st.grn), caption: 'Total GRN quantity'),
        KpiCard(
          icon: Icons.check_rounded,
          value: nf(st.packed),
          caption: 'Packed quantity',
          gradient: true,
          extra: DeltaChip('${st.completionPct}%'),
        ),
        KpiCard(icon: Icons.schedule_rounded, value: nf(st.pending), caption: 'Pending quantity (GRN − packed)'),
      ]),
      const SizedBox(height: 14),
      ResponsiveGrid(columns: 4, children: [
        KpiCard(icon: Icons.format_list_bulleted_rounded, value: '${st.linesPacked} / ${st.lines}', caption: 'Lines packed'),
        KpiCard(icon: Icons.inventory_2_outlined, value: nf(st.pouches), caption: 'Pouches'),
        KpiCard(icon: Icons.all_inbox_rounded, value: nf(st.boxes), caption: 'Boxes'),
        KpiCard(
          icon: Icons.warning_amber_rounded,
          value: '${st.excOpen}',
          caption: 'Open exceptions',
          extra: st.excOpen > 0 ? const DeltaChip('review', tone: PillTone.bad) : null,
        ),
      ]),
      const SizedBox(height: 18),

      SplitPane(
        sideFirst: true,
        sideWidth: 320,
        side: Panel(
          title: 'Shift completion',
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
              child: Center(child: RingProgress(percent: st.completionPct, label: 'Packed')),
            ),
            KeyValues([
              ('GRN batch', data.batchId ?? '—'),
              ('Transactions', '${st.txns}'),
              ('Tables occupied',
                  '${data.tables.where((t) => t.status == 'Occupied').length} / ${data.tables.length}'),
              ('Hourly reports sent', '${data.hourlyCount}'),
              ('Shift status',
                  data.shift.status + (data.shift.resubmits > 0 ? ' · rev ${data.shift.resubmits + 1}' : '')),
            ]),
          ]),
        ),
        main: Panel(
          title: 'Table-wise productivity',
          trailingText: 'packed qty · lines · status',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final t in data.tables)
              BarRow(
                label: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: t.tableNo, style: body(size: 12.5, weight: FontWeight.w700)),
                    TextSpan(
                      text: t.memberName == null
                          ? ' · unstaffed'
                          : ' · ${t.memberName!.split(' ').first}',
                      style: body(
                        size: 12.5,
                        weight: FontWeight.w700,
                        color: t.memberName == null ? Brand.txt3 : Brand.txt,
                      ),
                    ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                value: '${nf(t.packed)} qty · ${t.lines} lines · ${t.status}',
                percent: pct(t.packed, maxTableQty),
              ),
            const Hairline(),
            const SectionTitle('Member-wise productivity'),
            if (data.members.isEmpty)
              Text('No submissions yet.', style: body(size: 13, color: Brand.txt3))
            else
              for (final m in data.members)
                BarRow(
                  leading: Avatar(m.name, size: 27),
                  label: Text(m.name,
                      style: body(size: 12.5, weight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  value: '${nf(m.qty)} qty · ${m.lines} lines · ${m.pouches} pouches · ${m.boxes} boxes',
                  percent: pct(m.qty, maxMemberQty),
                ),
          ]),
        ),
      ),
      const SizedBox(height: 18),

      // FR-11.3 — invoice/part status, colour-coded, with the drill-down.
      const SectionTitle('Invoice / part status', trailing: 'colour-coded · click a row to drill down'),
      SpdTable(
        columns: const [
          SpdCol('Invoice', width: 108),
          SpdCol('Part Number', width: 128),
          SpdCol('Description', width: 210),
          SpdCol('Vendor', width: 178),
          SpdCol('GRN Qty', right: true, width: 96),
          SpdCol('Packed', right: true, width: 92),
          SpdCol('Pending', right: true, width: 92),
          SpdCol('Table(s)', width: 108),
          SpdCol('Status', width: 128),
        ],
        rows: [
          for (final l in data.lines)
            SpdRow(
              [
                monoCell(l.invoiceNo),
                strongCell(l.partNo),
                cell(l.partDesc),
                cell(l.vendor),
                monoCell(nf(l.grnQty)),
                monoCell(nf(l.packed), color: Brand.txt, weight: FontWeight.w700),
                monoCell(nf(l.pending), color: l.pending > 0 ? Brand.warn : Brand.ok),
                monoCell(l.tablesLabel),
                StatusPill(l.status),
              ],
              onTap: () => showLineDetail(context, ref, l.id),
            ),
        ],
        emptyMessage: 'No GRN lines for this shift yet — upload the GRN report.',
      ),
    ]);
  }
}
