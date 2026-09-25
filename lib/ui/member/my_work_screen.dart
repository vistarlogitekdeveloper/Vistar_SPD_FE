import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../widgets/common.dart';

/// UC-04 — the member's work queue. Only the lines allocated to their own table
/// appear (BR-05), which is what removes the typed part number and its errors.
class MyWorkScreen extends ConsumerWidget {
  const MyWorkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myQueueProvider);
    final user = ref.watch(sessionProvider).user;

    return async.when(
      loading: () => const Padding(padding: EdgeInsets.only(top: 80), child: SpdLoader()),
      error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
      data: (q) => _Body(queue: q, firstName: (user?.name ?? '').split(' ').first),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.queue, required this.firstName});

  final MemberQueue queue;
  final String firstName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = queue.stats;
    final open = queue.openLines;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        crumb: 'My table ·',
        accent: queue.tableNo,
        title: 'Hello, $firstName',
        blurbWidget: BlurbText([
          ('Table ', false),
          (queue.tableNo, true),
          (' · ${queue.shift.label}${queue.locked ? ' — entry locked' : ''} · only the lines '
              'allocated to your table appear here (BR-05).', false),
        ]),
        actions: [
          if (!queue.locked)
            GradButton(
              label: queue.running == null ? 'Start packing' : 'Resume packing',
              icon: Icons.play_arrow_rounded,
              small: true,
              onPressed: () => context.go('/my/pack'),
            ),
        ],
      ),

      ResponsiveGrid(columns: 4, children: [
        KpiCard(
          icon: Icons.format_list_bulleted_rounded,
          value: '${open.length}',
          caption: 'Lines waiting on my table',
        ),
        KpiCard(icon: Icons.check_rounded, value: nf(m.qty), caption: 'Qty I packed today', gradient: true),
        KpiCard(icon: Icons.inventory_2_outlined, value: '${m.pouches} / ${m.boxes}', caption: 'Pouches / boxes'),
        KpiCard(
          icon: Icons.schedule_rounded,
          value: m.lastSubmit == null ? '—' : fmtTs(m.lastSubmit),
          caption: 'Last submission',
        ),
      ]),

      if (queue.locked) ...[
        const SizedBox(height: 14),
        AlertBox(
          tone: AlertTone.warn,
          icon: Icons.lock_outline_rounded,
          title: 'Entry locked for this shift (BR-06)',
          message: 'The Supervisor has submitted the final status. Ask them to reopen the shift if a '
              'correction is needed.',
        ),
      ] else if (queue.running != null) ...[
        const SizedBox(height: 14),
        AlertBox(
          tone: AlertTone.info,
          icon: Icons.schedule_rounded,
          title: 'Packing in progress — ${queue.running!.partNo}',
          message: 'Started at ${fmtTs(queue.running!.startAt)}. Open the Pack screen to submit the '
              'packed quantity.',
        ),
      ],

      const SizedBox(height: 18),
      const SectionTitle('My allocated lines'),
      if (queue.lines.isEmpty)
        SpdTable(
          columns: const [SpdCol('')],
          rows: const [],
          emptyMessage: 'Nothing allocated to your table yet — the Supervisor allocates lines from the console.',
        )
      else
        ResponsiveGrid(
          columns: 2,
          children: [
            for (final l in queue.lines)
              PartCard(
                onTap: l.pending > 0 && !queue.locked
                    ? () {
                        ref.read(selectedPackLineProvider.notifier).set(l.id);
                        context.go('/my/pack');
                      }
                    : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(l.partNo, style: mono(size: 14, weight: FontWeight.w700))),
                    StatusPill(l.pending <= 0 ? 'Completed' : l.status),
                  ]),
                  const SizedBox(height: 6),
                  Text('${l.partDesc} · ${l.invoiceNo}',
                      style: body(size: 12, color: Brand.txt3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                  Row(children: [
                    _Metric(
                      value: nf(l.myShare ?? l.grnQty),
                      caption: l.myShare != null ? 'GRN qty (my share)' : 'GRN qty',
                    ),
                    const SizedBox(width: 16),
                    _Metric(value: nf(l.packed), caption: 'Packed', color: Brand.ok),
                    const SizedBox(width: 16),
                    _Metric(
                      value: nf(l.pending < 0 ? 0 : l.pending),
                      caption: 'Pending',
                      color: l.pending > 0 ? Brand.warn : Brand.ok,
                    ),
                  ]),
                  const SizedBox(height: 10),
                  ProgressBar(percent: pct(l.packed, l.grnQty), thin: true),
                ]),
              ),
          ],
        ),
    ]);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.caption, this.color});

  final String value, caption;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: mono(size: 13, weight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(caption, style: body(size: 11, color: Brand.txt3)),
        ],
      );
}
