import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
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
        skipLoadingOnReload: true,
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
              SpdCol('', right: true, width: 272),
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

                        /* BR-01 — the remainder nobody will pack. Pending is
                           computed, so there is nothing here to type over; what
                           this opens is a write-off carrying its reason. Icons
                           rather than labels, because the row already carries
                           two actions and gained a third: at full width the
                           labelled versions overflowed the column by 110px. */
                        if (l.pending > 0) ...[
                          IconTile(
                            icon: Icons.exposure_outlined,
                            tooltip: 'Adjust the outstanding quantity',
                            size: 32,
                            onTap: locked ? null : () => showAdjustQtyDialog(context, ref, l),
                          ),
                          const SizedBox(width: 6),
                        ],

                        /* FR-4.1 — a line can be on several tables, so the ones
                           it is already on are shown *and* another can be added
                           from here. The pill used to be the end of it, which
                           meant a line allocated once could never gain a second
                           bench from this screen — and until BR-04 was
                           generalised, not from anywhere. */
                        if (l.allocationCount > 0) ...[
                          Pill(
                            // Three tables' numbers do not fit the column, and
                            // the count is what a Supervisor is scanning for.
                            l.tables.length <= 2 ? l.tables.join('+') : '${l.tables.length} tables',
                            tone: PillTone.info,
                          ),
                          const SizedBox(width: 6),
                          IconTile(
                            icon: Icons.add_rounded,
                            tooltip: 'Allocate to another table',
                            size: 32,
                            onTap: locked ? null : () => showAllocateDialog(context, ref, l),
                          ),
                        ] else
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

/// BR-01 — writing off a remainder that will never be packed.
///
/// There is no "remaining quantity" to edit: pending is GRN minus packed, both
/// of which are records rather than settings — the GRN figure is what SAP sent
/// and a packing transaction is never rewritten (NFR-7.1). What a Supervisor
/// is actually saying when they close a line with five outstanding is *those
/// five are not coming*: damaged, short-shipped, the wrong part in the box. So
/// that is what this records, as its own entry with the reason attached, and
/// the member's 95 stays 95 on their productivity line.
///
/// The quantity defaults to the whole remainder, because closing a line out is
/// what this is for; a smaller figure writes off part of it and leaves the
/// rest outstanding.
Future<void> showAdjustQtyDialog(BuildContext context, WidgetRef ref, GrnLine line) async {
  final qty = TextEditingController(text: '${line.pending}');
  final reason = TextEditingController();

  await showSpdModal<void>(
    context,
    title: 'Adjust outstanding quantity',
    subtitle: '${line.partNo} · ${line.invoiceNo} · ${nf(line.pending)} ${line.uom} outstanding',
    content: (context, setModalState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AlertBox(
        tone: AlertTone.warn,
        title: 'This does not change the GRN quantity',
        message: 'GRN ${nf(line.grnQty)} and packed ${nf(line.packed)} both stay as they are. '
            'What is recorded is that the balance is not coming, and why — so the line '
            'reconciles without anyone being credited with packing it.',
      ),
      const SizedBox(height: 14),
      Field(
        label: 'Quantity to write off',
        hint: 'Up to the ${nf(line.pending)} ${line.uom} still outstanding',
        child: TextField(
          controller: qty,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: mono(size: 14),
          onChanged: (_) => setModalState(() {}),
        ),
      ),
      Field(
        label: 'Reason',
        required: true,
        bottom: 0,
        child: TextField(
          controller: reason,
          style: body(size: 14),
          decoration: const InputDecoration(
            hintText: 'e.g. balance short-shipped, closed on the supplier’s debit note',
          ),
        ),
      ),
    ]),
    actions: (context, _) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
      GradButton(
        label: 'Write off',
        icon: Icons.check_rounded,
        small: true,
        onPressed: () async {
          final n = num.tryParse(qty.text.trim());
          if (n == null || n <= 0) {
            Toast.bad(context, 'Nothing to write off', 'Enter a quantity greater than zero.');
            return;
          }
          if (reason.text.trim().isEmpty) {
            Toast.bad(context, 'A reason is required', 'Say why the balance is not coming.');
            return;
          }
          try {
            await ref.read(repositoryProvider).adjustQty(line.id, qty: n, reason: reason.text.trim());
            if (context.mounted) Navigator.pop(context);
            invalidateAll(ref);
            if (context.mounted) {
              Toast.ok(context, 'Quantity adjusted',
                  '${nf(n)} ${line.uom} written off ${line.partNo} — ${nf(line.pending - n)} still outstanding.');
            }
          } on ApiException catch (e) {
            if (context.mounted) Toast.bad(context, 'Adjustment refused', e.message);
          }
        },
      ),
    ],
  );
}
