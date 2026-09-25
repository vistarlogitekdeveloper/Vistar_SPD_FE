import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// UC-07 / FR-9 — the Supervisor's review screen: packed vs pending by table
/// and member, every flagged mismatch in one place, and the final submission
/// that locks member entry and generates the MIS.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reviewProvider);
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.only(top: 80), child: SpdLoader()),
      error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
      data: (d) => _Body(data: d),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});

  final ReviewPage data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = data.stats;
    final locked = data.shift.finalised;
    final blocking = data.exceptions.where((e) => e.blocksFinalisation).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        crumb: 'Floor ·',
        accent: 'Review',
        title: 'Review, exceptions & final submission',
        blurb: 'Packed vs pending by table and member, every flagged mismatch in one place. '
            'Final submission locks member entry for the shift and generates the MIS automatically.',
        actions: [
          if (locked)
            GhostButton(
              label: 'Reopen shift (logged)',
              icon: Icons.lock_open_rounded,
              danger: true,
              onPressed: () => _reopen(context, ref, data.shift),
            )
          else
            GradButton(
              label: 'Submit final status',
              icon: Icons.lock_outline_rounded,
              small: true,
              onPressed: data.canFinalise ? () => _finalise(context, ref, data) : null,
            ),
        ],
      ),

      ResponsiveGrid(columns: 4, children: [
        KpiCard(icon: Icons.check_rounded, value: nf(st.packed), caption: 'Packed quantity', gradient: true),
        KpiCard(icon: Icons.schedule_rounded, value: nf(st.pending), caption: 'Pending quantity'),
        KpiCard(
          icon: Icons.format_list_bulleted_rounded,
          value: '${st.linesPacked}/${st.lines}',
          caption: 'Lines fully packed',
        ),
        KpiCard(
          icon: Icons.warning_amber_rounded,
          value: '${st.excOpen}',
          caption: 'Exceptions needing remarks',
        ),
      ]),

      const SizedBox(height: 14),
      if (locked)
        AlertBox(
          tone: AlertTone.ok,
          icon: Icons.lock_outline_rounded,
          title: 'Shift finalised by ${data.shift.finalByName ?? '—'} at ${fmtTs(data.shift.finalAt)}',
          message: 'Member data entry is locked (BR-06) and the MIS has been generated. Reopening is '
              'available to the Supervisor only and is logged as a resubmission.',
        )
      else if (blocking > 0)
        AlertBox(
          tone: AlertTone.bad,
          title: '$blocking exception${blocking == 1 ? '' : 's'} must carry a remark before final submission (BR-03)',
          message: 'Add remarks below, or resolve the exception, to unlock the final submit.',
        ),

      const SizedBox(height: 18),
      SectionTitle('Exceptions (${data.exceptions.length})'),
      SpdTable(
        columns: const [
          SpdCol('ID', width: 84),
          SpdCol('Type', width: 148),
          SpdCol('Part', width: 130),
          SpdCol('Invoice', width: 110),
          SpdCol('Detail', width: 300, wrap: true),
          SpdCol('Remarks', width: 200, wrap: true),
          SpdCol('Status', width: 116),
          SpdCol('', right: true, width: 110),
        ],
        rows: [
          for (final e in data.exceptions)
            SpdRow([
              strongCell(e.id),
              Pill(e.type, tone: e.type == 'Excess Entry' ? PillTone.bad : PillTone.amber),
              strongCell(e.partNo),
              monoCell(e.invoiceNo),
              wrapCell(e.detail),
              e.remarks.isEmpty
                  ? Text('— required —', style: body(size: 13, color: Brand.txt3))
                  : wrapCell(e.remarks),
              Pill(e.resolved ? 'Resolved' : 'Open', tone: e.resolved ? PillTone.ok : PillTone.bad),
              e.resolved
                  ? const SizedBox.shrink()
                  : GhostButton(
                      label: 'Review',
                      icon: Icons.visibility_outlined,
                      onPressed: () => _annotate(context, ref, e),
                    ),
            ]),
        ],
        emptyMessage: 'No exceptions flagged — packed and GRN quantities reconcile.',
      ),

      const SizedBox(height: 18),
      ResponsiveGrid(columns: 2, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('Table-wise status'),
          SpdTable(
            columns: const [
              SpdCol('Table', width: 82),
              SpdCol('Member', width: 150),
              SpdCol('Status', width: 116),
              SpdCol('Lines', right: true, width: 74),
              SpdCol('Packed', right: true, width: 92),
              SpdCol('Pending', right: true, width: 92),
            ],
            rows: [
              for (final t in data.tables)
                SpdRow([
                  strongCell(t.tableNo),
                  cell(t.memberName ?? '—'),
                  StatusPill(t.status),
                  monoCell('${t.allocatedLines}'),
                  monoCell(nf(t.allocatedPacked)),
                  monoCell(nf(t.pending)),
                ]),
            ],
          ),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('Member-wise status'),
          SpdTable(
            columns: const [
              SpdCol('Member', width: 180),
              SpdCol('Table', width: 82),
              SpdCol('Txns', right: true, width: 74),
              SpdCol('Qty', right: true, width: 90),
              SpdCol('Pouches', right: true, width: 88),
              SpdCol('Boxes', right: true, width: 80),
              SpdCol('Last submit', width: 110),
            ],
            rows: [
              for (final m in data.members)
                SpdRow([
                  personCell(m.name),
                  monoCell(m.tableNo ?? '—'),
                  monoCell('${m.txns}'),
                  monoCell(nf(m.qty), color: Brand.txt, weight: FontWeight.w700),
                  monoCell('${m.pouches}'),
                  monoCell('${m.boxes}'),
                  monoCell(m.lastSubmit == null ? '—' : fmtTs(m.lastSubmit)),
                ]),
            ],
          ),
        ]),
      ]),
    ]);
  }

  /// FR-9.2 — remarks, with the option to close the exception.
  Future<void> _annotate(BuildContext context, WidgetRef ref, SpdException e) async {
    final remarks = TextEditingController(text: e.remarks);
    final cfg = ref.read(configProvider).value ?? SpdConfig.empty();
    final line = await ref.read(repositoryProvider).line(e.lineId);
    if (!context.mounted) return;

    Future<void> save(bool resolve) async {
      final text = remarks.text.trim();
      if (text.isEmpty) {
        Toast.bad(context, 'Remarks required',
            'An exception cannot be saved without supervisor remarks (FR-9.2).');
        return;
      }
      try {
        await ref.read(repositoryProvider).annotateException(id: e.id, remarks: text, resolve: resolve);
        if (context.mounted) Navigator.pop(context);
        invalidateAll(ref);
        if (context.mounted) {
          Toast.ok(context, resolve ? 'Exception resolved' : 'Remarks saved',
              '${e.id} ${resolve ? 'closed' : 'annotated'} — recorded in the audit trail.');
        }
      } on ApiException catch (err) {
        if (context.mounted) Toast.bad(context, 'Could not save', err.message);
      }
    }

    await showSpdModal<void>(
      context,
      title: '${e.type} · ${e.id}',
      subtitle: '${e.partNo} · ${e.invoiceNo} · flagged ${fmtTs(e.createdAt)}',
      content: (context, setModalState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AlertBox(
          tone: e.type == 'Excess Entry' ? AlertTone.bad : AlertTone.warn,
          title: e.type,
          message: e.detail,
        ),
        const SizedBox(height: 14),
        KeyValues([
          ('GRN quantity', '${nf(line.line.grnQty)} ${line.line.uom}'),
          ('Cumulative packed', nf(line.line.packed)),
          ('Abnormal threshold', '${cfg.threshold}% of GRN qty'),
        ]),
        const SizedBox(height: 14),
        Field(
          label: 'Supervisor remarks / corrective action',
          required: true,
          bottom: 0,
          child: TextField(
            controller: remarks,
            maxLines: 3,
            style: body(size: 14),
            decoration: const InputDecoration(
              hintText: 'e.g. physical recount done — excess 20 pcs returned to stores under GD note',
            ),
          ),
        ),
      ]),
      actions: (context, _) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        GhostButton(label: 'Save remarks', onPressed: () => save(false)),
        GradButton(label: 'Save & resolve', icon: Icons.check_rounded, small: true, onPressed: () => save(true)),
      ],
    );
  }

  /// UC-07 — the confirmation the prototype shows before locking the shift.
  Future<void> _finalise(BuildContext context, WidgetRef ref, ReviewPage data) async {
    final st = data.stats;
    await showSpdModal<void>(
      context,
      title: 'Submit final status — ${data.shift.label}',
      subtitle: 'UC-07 · locks member entry and generates the MIS',
      content: (context, setModalState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        KeyValues([
          ('Packed / GRN', '${nf(st.packed)} / ${nf(st.grn)}'),
          ('Pending quantity', nf(st.pending)),
          ('Lines fully packed', '${st.linesPacked} / ${st.lines}'),
          ('Pouches / Boxes', '${nf(st.pouches)} / ${nf(st.boxes)}'),
          ('Exceptions', '${st.exc} flagged · all annotated'),
        ]),
        const SizedBox(height: 14),
        AlertBox(
          tone: AlertTone.warn,
          icon: Icons.lock_outline_rounded,
          title: 'BR-06 — this locks the shift',
          message: 'Table-member data entry for ${data.shift.label} will be locked. Only you can '
              'reopen it, and the reopening is logged as a resubmission.',
        ),
      ]),
      actions: (context, _) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        GradButton(
          label: 'Confirm final submission',
          icon: Icons.lock_outline_rounded,
          small: true,
          onPressed: () async {
            try {
              final misId = await ref.read(repositoryProvider).finaliseShift(data.shift.id);
              if (context.mounted) Navigator.pop(context);
              ref.invalidate(shiftsProvider);
              invalidateAll(ref);
              if (context.mounted) {
                Toast.ok(context, 'Shift finalised',
                    'Member entry locked · MIS $misId generated automatically — open the MIS Report screen.');
              }
            } on ApiException catch (e) {
              if (context.mounted) Toast.bad(context, 'Could not finalise', e.message);
            }
          },
        ),
      ],
    );
  }

  /// BR-06 — reopening, with the reason that goes into the audit trail.
  Future<void> _reopen(BuildContext context, WidgetRef ref, Shift shift) async {
    final reason = TextEditingController();
    await showSpdModal<void>(
      context,
      title: 'Reopen ${shift.label}',
      subtitle: 'Logged as a resubmission (BR-06)',
      content: (context, setModalState) => Field(
        label: 'Reason',
        required: true,
        bottom: 0,
        child: TextField(
          controller: reason,
          style: body(size: 14),
          decoration: const InputDecoration(hintText: 'e.g. T-04 boxes count correction'),
        ),
      ),
      actions: (context, _) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        GhostButton(
          label: 'Reopen shift',
          icon: Icons.lock_open_rounded,
          danger: true,
          onPressed: () async {
            if (reason.text.trim().isEmpty) {
              Toast.bad(context, 'Reason required', 'Reopening must be logged with a reason.');
              return;
            }
            try {
              await ref.read(repositoryProvider).reopenShift(shiftId: shift.id, reason: reason.text.trim());
              if (context.mounted) Navigator.pop(context);
              ref.invalidate(shiftsProvider);
              invalidateAll(ref);
              if (context.mounted) {
                Toast.warn(context, 'Shift reopened',
                    'Member entry unlocked. Submit the final status again when done — it will be recorded as a resubmission.');
              }
            } on ApiException catch (e) {
              if (context.mounted) Toast.bad(context, 'Could not reopen', e.message);
            }
          },
        ),
      ],
    );
  }
}
