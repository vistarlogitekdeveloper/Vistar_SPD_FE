import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// UC-03 / FR-4 — map invoice/part lines to packing tables. This is the screen
/// that replaces the printout handed to each table: the allocated line appears
/// on that member's own screen instantly.
class AllocationScreen extends ConsumerWidget {
  const AllocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(tablesProvider);
    final lines = ref.watch(linesProvider);
    final allocs = ref.watch(allocationsProvider);
    final locked = ref.watch(currentShiftProvider)?.finalised ?? false;

    final unallocated =
        (lines.value?.lines ?? const <GrnLine>[]).where((l) => l.allocationCount == 0).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        crumb: 'Floor ·',
        accent: 'Allocation',
        title: 'Table allocation & status board',
        blurb: 'Map invoice/part lines to packing tables — the manual printout handed to each '
            'table is gone; the allocated line appears on that table member’s screen instantly.',
        actions: [
          Pill('${unallocated.length} lines unallocated',
              tone: unallocated.isEmpty ? PillTone.ok : PillTone.amber),
        ],
      ),

      if (locked) ...[
        const AlertBox(
          tone: AlertTone.warn,
          title: 'This shift is finalised (BR-06)',
          message: 'Reopen it from Review & Finalise before changing allocations.',
        ),
        const SizedBox(height: 16),
      ],

      // FR-4.3 — the live table status board.
      tables.when(
        skipLoadingOnReload: true,
        loading: () => const SpdLoader(size: 48),
        error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
        data: (list) => ResponsiveGrid(
          columns: 4,
          children: [
            for (final t in list)
              TableCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(t.tableNo, style: display(size: 21)),
                    const Spacer(),
                    StatusPill(t.status),
                  ]),
                  const SizedBox(height: 6),
                  Text(t.memberName ?? 'Unstaffed', style: body(size: 12, color: Brand.txt3)),
                  const SizedBox(height: 10),
                  if (t.allocatedLineRows.isEmpty)
                    Text('No lines allocated', style: body(size: 12, color: Brand.txt3))
                  else ...[
                    for (final l in t.allocatedLineRows.take(3))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Flexible(child: Text(l.partNo, style: mono(size: 12), overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          Text('· pend ${nf(l.pending)}', style: body(size: 12, color: Brand.txt3)),
                        ]),
                      ),
                    if (t.allocatedLineRows.length > 3)
                      Text('+${t.allocatedLineRows.length - 3} more',
                          style: body(size: 12, color: Brand.txt3)),
                  ],
                  const SizedBox(height: 10),
                  ProgressBar(percent: t.progressPct, thin: true),
                ]),
              ),
          ],
        ),
      ),

      const SizedBox(height: 24),
      const SectionTitle('Unallocated lines', trailing: 'select a table for each'),
      SpdTable(
        columns: const [
          SpdCol('Invoice', width: 110),
          SpdCol('Part', width: 130),
          SpdCol('Description', width: 230),
          SpdCol('GRN Qty', right: true, width: 110),
          SpdCol('Vendor', width: 180),
          SpdCol('', right: true, width: 130),
        ],
        rows: [
          for (final l in unallocated)
            SpdRow([
              monoCell(l.invoiceNo),
              strongCell(l.partNo),
              cell(l.partDesc),
              monoCell('${nf(l.grnQty)} ${l.uom}'),
              cell(l.vendor),
              GradButton(
                label: 'Allocate',
                icon: Icons.table_chart_outlined,
                small: true,
                onPressed: locked ? null : () => showAllocateDialog(context, ref, l),
              ),
            ]),
        ],
        emptyMessage: 'Every line is allocated to a table.',
      ),

      const SizedBox(height: 24),
      const SectionTitle('Allocation log'),
      allocs.when(
        skipLoadingOnReload: true,
        loading: () => const SpdLoader(size: 40, fill: false),
        error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
        data: (list) => SpdTable(
          columns: const [
            SpdCol('Part', width: 130),
            SpdCol('Invoice', width: 110),
            SpdCol('Table', width: 90),
            SpdCol('Qty', right: true, width: 120),
            SpdCol('Allocated at', width: 120),
            SpdCol('By', width: 150),
            SpdCol('Split reason', width: 260, wrap: true),
            SpdCol('', right: true, width: 120),
          ],
          rows: [
            for (final a in list.take(15))
              SpdRow([
                strongCell(a.partNo),
                monoCell(a.invoiceNo),
                strongCell(a.tableNo),
                monoCell(a.qty == null ? 'Full (${nf(a.grnQty)})' : nf(a.qty)),
                monoCell(fmtTs(a.allocatedAt)),
                cell(a.allocatedByName),
                a.reason.isEmpty
                    ? Text('—', style: body(size: 13, color: Brand.txt3))
                    : wrapCell(a.reason),
                // BR-04 refuses a second table for a line, so without this a
                // line sent to the wrong table stays there for the whole
                // shift. The server still decides: once anything has been
                // packed against it the allocation stays, for the audit trail.
                GhostButton(
                  label: 'Withdraw',
                  danger: true,
                  onPressed: () => _withdraw(context, ref, a),
                ),
              ]),
          ],
          emptyMessage: 'Nothing has been allocated yet.',
        ),
      ),
    ]);
  }
}

/// FR-4.1 — undoing an allocation made to the wrong table.
///
/// Confirmed first, because withdrawing is how a member's queue loses a line
/// mid-shift. The refusal cases (a finalised shift, or anything already packed)
/// are the server's to decide and arrive as the message it gives.
Future<void> _withdraw(BuildContext context, WidgetRef ref, Allocation a) async {
  final ok = await showSpdModal<bool>(
        context,
        title: 'Withdraw allocation',
        subtitle: '${a.partNo} · ${a.invoiceNo} · ${a.tableNo}',
        content: (context, _) => AlertBox(
          tone: AlertTone.warn,
          title: '${a.tableNo} will no longer see this line',
          message: 'It can be allocated again afterwards. If anything has already been packed '
              'against it the server will refuse, and the allocation stays for the audit trail.',
        ),
        actions: (context, _) => [
          GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context, false)),
          GradButton(label: 'Withdraw', onPressed: () => Navigator.pop(context, true)),
        ],
      ) ??
      false;
  if (!ok || !context.mounted) return;

  try {
    await ref.read(repositoryProvider).withdrawAllocation(a.id);
    invalidateAll(ref);
    if (context.mounted) {
      Toast.ok(context, 'Allocation withdrawn', '${a.partNo} is free to allocate again.');
    }
  } on ApiException catch (e) {
    if (context.mounted) Toast.bad(context, 'Could not withdraw', e.message);
  }
}

/// FR-4.1 — putting a line on one table, or on several.
///
/// A line goes to as many tables as the work needs, so this picks a set rather
/// than a table and an optional second: an invoice spread over three benches is
/// what the floor does, and the dialog that only offered "split with one other"
/// is what stopped it. It is also how a line already placed gains another
/// table, which is why the tables it is on are shown but not offered.
///
/// BR-04 survives as the rule it was always protecting — a line never lands on
/// a second table by accident — so the reason is demanded the moment the line
/// would touch more than one, and the server demands it again.
Future<void> showAllocateDialog(BuildContext context, WidgetRef ref, GrnLine line) async {
  final tables = ref.read(tablesProvider).value ?? const <TableStat>[];
  if (tables.isEmpty) {
    Toast.bad(context, 'No packing tables', 'Configure the table master before allocating.');
    return;
  }

  final already = line.tables.toSet();
  final free = tables.where((t) => !already.contains(t.tableNo)).toList();
  if (free.isEmpty) {
    Toast.bad(context, 'Nowhere left to allocate',
        '${line.partNo} is already on every packing table.');
    return;
  }

  final picked = <String>{};
  final shares = {for (final t in free) t.tableNo: TextEditingController()};
  final reason = TextEditingController();

  // Anything past the first table has to say why — including the first one
  // added to a line that is already placed somewhere.
  bool needsReason() => already.isNotEmpty || picked.length > 1;

  await showSpdModal<void>(
    context,
    title: 'Allocate ${line.partNo}',
    subtitle: '${line.invoiceNo} · GRN ${nf(line.grnQty)} ${line.uom} · ${line.partDesc}',
    content: (context, setModalState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (already.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: AlertBox(
            tone: AlertTone.info,
            title: 'Already on ${already.join(', ')}',
            message: 'Adding another table leaves those in place. Both benches see the line, '
                'and what each actually packs is what its members submit.',
          ),
        ),
      Field(
        label: 'Packing tables',
        hint: 'Pick one, or several to share the line',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in free)
              SpdChip(
                '${t.tableNo} · ${t.memberName ?? 'unstaffed'}',
                selected: picked.contains(t.tableNo),
                onTap: () => setModalState(() {
                  if (!picked.remove(t.tableNo)) picked.add(t.tableNo);
                }),
              ),
          ],
        ),
      ),

      /* A share is optional. Left blank the table simply works the line, which
         is what a whole-line allocation has always meant and what several
         tables hold when they share a queue; filled in, it is that table's
         portion and the server checks the total against the GRN quantity. */
      if (picked.length > 1)
        Field(
          label: 'Quantity each (optional)',
          hint: 'Leave blank to share the line without splitting it',
          child: Column(children: [
            for (final t in picked.toList()..sort())
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(width: 78, child: Text(t, style: body(size: 13, weight: FontWeight.w700))),
                  Expanded(
                    child: TextField(
                      controller: shares[t],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: mono(size: 14),
                      decoration: InputDecoration(hintText: 'of ${nf(line.grnQty)} ${line.uom}'),
                    ),
                  ),
                ]),
              ),
          ]),
        ),

      if (needsReason())
        Field(
          label: 'Reason',
          required: true,
          bottom: 0,
          child: TextField(
            controller: reason,
            style: body(size: 14),
            decoration: const InputDecoration(hintText: 'e.g. bulky line, dispatch cut-off'),
          ),
        ),
    ]),
    actions: (context, _) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
      GradButton(
        label: 'Confirm allocation',
        icon: Icons.check_rounded,
        small: true,
        onPressed: () async {
          if (picked.isEmpty) {
            Toast.bad(context, 'No table chosen', 'Pick at least one packing table.');
            return;
          }
          try {
            await ref.read(repositoryProvider).allocate(
                  lineId: line.id,
                  tables: [
                    for (final t in picked.toList()..sort())
                      TableShare(t, num.tryParse(shares[t]?.text.trim() ?? '')),
                  ],
                  reason: reason.text.trim(),
                );
            if (context.mounted) Navigator.pop(context);
            invalidateAll(ref);
            if (context.mounted) {
              final on = (picked.toList()..sort()).join(' and ');
              Toast.ok(context, 'Allocated',
                  '${line.partNo} is now visible on $on — no printout needed.');
            }
          } on ApiException catch (e) {
            if (context.mounted) Toast.bad(context, 'Allocation refused', e.message);
          }
        },
      ),
    ],
  );
}
