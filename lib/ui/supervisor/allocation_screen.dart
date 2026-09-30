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
        loading: () => const SpdLoader(size: 40),
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

/// The allocation dialog, including the BR-04 split with its mandatory reason.
Future<void> showAllocateDialog(BuildContext context, WidgetRef ref, GrnLine line) async {
  final tables = ref.read(tablesProvider).value ?? const <TableStat>[];
  if (tables.isEmpty) {
    Toast.bad(context, 'No packing tables', 'Configure the table master before allocating.');
    return;
  }

  var tableNo = tables.first.tableNo;
  String? splitWith;
  final q1 = TextEditingController(text: '${(line.grnQty / 2).round()}');
  final q2 = TextEditingController(text: '${(line.grnQty / 2).ceil()}');
  final reason = TextEditingController();

  await showSpdModal<void>(
    context,
    title: 'Allocate ${line.partNo}',
    subtitle: '${line.invoiceNo} · GRN ${nf(line.grnQty)} ${line.uom} · ${line.partDesc}',
    content: (context, setModalState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Field(
        label: 'Packing table',
        child: SpdDropdown<String>(
          value: tableNo,
          items: [
            for (final t in tables)
              DropdownMenuItem(
                value: t.tableNo,
                child: Text('${t.tableNo} · ${t.memberName ?? 'unstaffed'} · ${t.status}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setModalState(() => tableNo = v ?? tableNo),
        ),
      ),
      Field(
        label: 'Split across a second table? (BR-04 — needs a reason)',
        child: SpdDropdown<String>(
          value: splitWith,
          items: [
            const DropdownMenuItem(value: null, child: Text('No — allocate full quantity to one table')),
            for (final t in tables.where((t) => t.tableNo != tableNo))
              DropdownMenuItem(value: t.tableNo, child: Text('Yes — split with ${t.tableNo}')),
          ],
          onChanged: (v) => setModalState(() => splitWith = v),
        ),
      ),
      if (splitWith != null) ...[
        Row(children: [
          Expanded(
            child: Field(
              label: 'Qty to $tableNo',
              child: TextField(
                controller: q1,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: mono(size: 14),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Field(
              label: 'Qty to $splitWith',
              child: TextField(
                controller: q2,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: mono(size: 14),
              ),
            ),
          ),
        ]),
        Field(
          label: 'Split reason',
          required: true,
          bottom: 0,
          child: TextField(
            controller: reason,
            style: body(size: 14),
            decoration: const InputDecoration(hintText: 'e.g. bulky line, dispatch cut-off'),
          ),
        ),
      ],
    ]),
    actions: (context, _) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
      GradButton(
        label: 'Confirm allocation',
        icon: Icons.check_rounded,
        small: true,
        onPressed: () async {
          try {
            await ref.read(repositoryProvider).allocate(
                  lineId: line.id,
                  tableNo: tableNo,
                  splitWith: splitWith,
                  qty1: splitWith == null ? null : num.tryParse(q1.text),
                  qty2: splitWith == null ? null : num.tryParse(q2.text),
                  reason: reason.text.trim(),
                );
            if (context.mounted) Navigator.pop(context);
            invalidateAll(ref);
            if (context.mounted) {
              Toast.ok(
                context,
                'Allocated',
                '${line.partNo} is now visible on $tableNo${splitWith != null ? ' and $splitWith' : ''} — no printout needed.',
              );
            }
          } on ApiException catch (e) {
            if (context.mounted) Toast.bad(context, 'Allocation refused', e.message);
          }
        },
      ),
    ],
  );
}
