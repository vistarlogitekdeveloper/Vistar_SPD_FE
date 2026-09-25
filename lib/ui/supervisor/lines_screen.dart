import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../widgets/common.dart';
import '../widgets/line_detail.dart';
import 'allocation_screen.dart' show showAllocateDialog;
import 'labels_screen.dart' show showLabelDialog;

/// FR-2 — the imported GRN grouped by invoice, with live packed and pending
/// quantities and the two actions a Supervisor takes from here: print a label
/// and allocate a table.
class LinesScreen extends ConsumerStatefulWidget {
  const LinesScreen({super.key});

  @override
  ConsumerState<LinesScreen> createState() => _LinesScreenState();
}

class _LinesScreenState extends ConsumerState<LinesScreen> {
  late final TextEditingController _q =
      TextEditingController(text: ref.read(linesFilterProvider).q);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _setFilter(LinesFilter f) => ref.read(linesFilterProvider.notifier).set(f);

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(linesFilterProvider);
    final async = ref.watch(linesProvider);
    final locked = ref.watch(currentShiftProvider)?.finalised ?? false;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        crumb: 'GRN ·',
        accent: 'Lines',
        title: 'Invoice-wise / part-number-wise GRN',
        blurb: 'Imported GRN data grouped by invoice with live packed and pending quantities. '
            'Select lines for label printing or table allocation — the manual invoice-wise '
            'preparation step is gone.',
        actions: [
          GhostButton(label: 'Print labels', icon: Icons.sell_outlined, onPressed: () => context.go('/labels')),
          GradButton(
            label: 'Allocate tables',
            icon: Icons.table_chart_outlined,
            small: true,
            onPressed: () => context.go('/allocation'),
          ),
        ],
      ),

      FilterBar(
        onReset: () {
          _q.clear();
          _setFilter(const LinesFilter());
        },
        children: [
          Field(
            label: 'Search',
            bottom: 0,
            child: TextField(
              controller: _q,
              style: body(size: 13),
              decoration: const InputDecoration(hintText: 'Part, description…'),
              onChanged: (v) => _setFilter(f.copyWith(q: v)),
            ),
          ),
          Field(
            label: 'Invoice',
            bottom: 0,
            child: SpdDropdown<String>(
              dense: true,
              value: f.invoice.isEmpty ? '' : f.invoice,
              items: [
                const DropdownMenuItem(value: '', child: Text('All invoices')),
                for (final i in async.value?.invoices ?? const <String>[])
                  DropdownMenuItem(value: i, child: Text(i)),
              ],
              onChanged: (v) => _setFilter(f.copyWith(invoice: v ?? '')),
            ),
          ),
          Field(
            label: 'Vendor',
            bottom: 0,
            child: SpdDropdown<String>(
              dense: true,
              value: f.vendor.isEmpty ? '' : f.vendor,
              items: [
                const DropdownMenuItem(value: '', child: Text('All vendors')),
                for (final v in async.value?.vendors ?? const <String>[])
                  DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => _setFilter(f.copyWith(vendor: v ?? '')),
            ),
          ),
          Field(
            label: 'Status',
            bottom: 0,
            child: SpdDropdown<String>(
              dense: true,
              value: f.status,
              items: const [
                DropdownMenuItem(value: '', child: Text('All statuses')),
                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                DropdownMenuItem(value: 'Allocated', child: Text('Allocated')),
                DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                DropdownMenuItem(value: 'Exception', child: Text('Exception')),
              ],
              onChanged: (v) => _setFilter(f.copyWith(status: v ?? '')),
            ),
          ),
        ],
      ),

      async.when(
        loading: () => const SpdLoader(size: 48),
        error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
        data: (page) {
          // The prototype repeats the invoice only on the first line of a group
          // and shows a ditto mark below it, so the eye reads the grouping.
          var lastInvoice = '';
          return SpdTable(
            columns: const [
              SpdCol('Invoice', width: 108),
              SpdCol('Part Number', width: 128),
              SpdCol('Description', width: 200),
              SpdCol('Vendor', width: 170),
              SpdCol('GRN Date', width: 110),
              SpdCol('GRN Qty', right: true, width: 106),
              SpdCol('Packed', right: true, width: 92),
              SpdCol('Pending', right: true, width: 92),
              SpdCol('Status', width: 128),
              SpdCol('', right: true, width: 196),
            ],
            rows: [
              for (final l in page.lines)
                () {
                  final first = l.invoiceNo != lastInvoice;
                  lastInvoice = l.invoiceNo;
                  return SpdRow(
                    [
                      first
                          ? strongCell(l.invoiceNo)
                          // The prototype prints U+3003 DITTO MARK here. That
                          // codepoint is CJK, so Manrope does not carry it and
                          // the glyph only appears because the engine fetches a
                          // fallback font at runtime — which a shop-floor
                          // tablet on a closed LAN cannot do, leaving a tofu
                          // box in the invoice column. U+201D is the mark the
                          // ditto derives from, it reads the same, and Manrope
                          // has it.
                          : Text('”', style: body(size: 15, color: Brand.txt3)),
                      strongCell(l.partNo),
                      cell(l.partDesc),
                      cell(l.vendor),
                      monoCell(fmtD(l.grnDate)),
                      monoCell('${nf(l.grnQty)} ${l.uom}'),
                      monoCell(nf(l.packed)),
                      monoCell(nf(l.pending), color: l.pending > 0 ? Brand.warn : Brand.ok),
                      StatusPill(l.status),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        GhostButton(
                          label: 'Label',
                          icon: Icons.sell_outlined,
                          onPressed: () => showLabelDialog(context, ref, l.id),
                        ),
                        const SizedBox(width: 6),
                        if (l.allocationCount > 0)
                          Pill(l.tables.join('+'), tone: PillTone.info)
                        else
                          GradButton(
                            label: 'Allocate',
                            icon: Icons.table_chart_outlined,
                            small: true,
                            onPressed: locked ? null : () => showAllocateDialog(context, ref, l),
                          ),
                      ]),
                    ],
                    onTap: () => showLineDetail(context, ref, l.id),
                  );
                }(),
            ],
            emptyMessage: 'No line matches the filter.',
          );
        },
      ),
    ]);
  }
}
