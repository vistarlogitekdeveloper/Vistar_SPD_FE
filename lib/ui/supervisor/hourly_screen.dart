import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// UC-06 / FR-8 — the automated hourly packing report: generated on a schedule,
/// emailed to the distribution list, and retained here for on-demand viewing
/// (FR-8.3).
class HourlyScreen extends ConsumerWidget {
  const HourlyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hourlyProvider);
    final shiftId = ref.watch(selectedShiftProvider);

    return async.when(
      skipLoadingOnReload: true,
      loading: () => const SpdLoader(),
      error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
      data: (page) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeader(
          crumb: 'Floor ·',
          accent: 'Hourly Reports',
          title: 'Automated hourly packing reports',
          blurbWidget: BlurbText([
            ('Generated every ${page.interval} minutes during the shift and emailed to ', false),
            (page.emails.join(', '), true),
            (' — no manual preparation. Also retained here for on-demand viewing (FR-8.3).', false),
          ]),
          actions: [
            GradButton(
              label: 'Generate & email now',
              icon: Icons.mail_outline_rounded,
              small: true,
              onPressed: shiftId == null ? null : () => _generate(context, ref, shiftId),
            ),
          ],
        ),

        SpdTable(
          columns: const [
            SpdCol('Report', width: 96),
            SpdCol('Time', width: 90),
            SpdCol('Packed qty', right: true, width: 110),
            SpdCol('Pending qty', right: true, width: 112),
            SpdCol('Tables', width: 190),
            SpdCol('Exceptions', right: true, width: 106),
            SpdCol('Emailed to', width: 260, wrap: true),
            // Wide enough for the "View email" button at its natural size.
            // Below the table's scaling width the columns stay at their
            // declared size, so anything too tight overflows there and nowhere
            // else — which is why this needs the button's real width, not the
            // width it happens to get on a supervisor's monitor.
            SpdCol('', right: true, width: 150),
          ],
          rows: [
            for (final h in page.reports)
              SpdRow([
                strongCell(h.id),
                monoCell(fmtT(h.generatedAt)),
                monoCell(nf(h.packed)),
                monoCell(nf(h.pending)),
                cell(h.tablesSummary),
                monoCell('${h.exceptionsCount}'),
                wrapCell(h.emailedTo),
                GhostButton(
                  label: 'View email',
                  icon: Icons.mail_outline_rounded,
                  onPressed: () => showEmailPreview(context, ref, h.id),
                ),
              ]),
          ],
          emptyMessage: 'No hourly report yet for this shift.',
        ),

        const SizedBox(height: 18),
        const AlertBox(
          tone: AlertTone.info,
          title: 'UC-06 — system-triggered',
          message: 'The hourly job runs on schedule with no user action; the interval and the '
              'distribution list are configurable in the Admin console.',
        ),
        const SizedBox(height: 10),
        if (page.reports.isNotEmpty && page.reports.first.emailStatus.startsWith('Not sent'))
          const AlertBox(
            tone: AlertTone.warn,
            title: 'No SMTP host is configured on this server',
            message: 'Reports are still generated, stored and viewable here — only the email '
                'delivery is skipped. Set SMTP_HOST on the API to switch delivery on (FR-8.2).',
          ),
      ]),
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref, String shiftId) async {
    try {
      final report = await ref.read(repositoryProvider).generateHourly(shiftId);
      invalidateAll(ref);
      if (!context.mounted) return;
      Toast.ok(context, 'Hourly report generated',
          '${report.id} — ${report.emailStatus.toLowerCase()}.');
      await showEmailPreview(context, ref, report.id);
    } on ApiException catch (e) {
      if (context.mounted) Toast.bad(context, 'Could not generate the report', e.message);
    }
  }
}

/// Section 9.1 — the report as the Supervisor receives it in their inbox.
Future<void> showEmailPreview(BuildContext context, WidgetRef ref, String id) async {
  final HourlyReport h;
  try {
    h = await ref.read(repositoryProvider).hourlyDetail(id);
  } on ApiException catch (e) {
    if (context.mounted) Toast.bad(context, 'Could not open the report', e.message);
    return;
  }
  if (!context.mounted) return;

  await showSpdModal<void>(
    context,
    title: 'Hourly packing status — email',
    subtitle: '${h.id} · sent ${fmtTs(h.generatedAt)} · ${h.emailStatus}',
    wide: true,
    content: (context, setModalState) => EmailPreview(
      subject: 'SPD Pre-Packing · Hourly Status · ${h.shiftLabel} · ${fmtT(h.generatedAt)}',
      meta: 'From: spd-app@vistarlogitek.com · To: ${h.emailedTo}',
      content: DefaultTextStyle(
        style: body(size: 13, color: Brand.txt2, height: 1.65),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Dear Supervisor,'),
          const SizedBox(height: 12),
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Automated status as of '),
            TextSpan(text: fmtT(h.generatedAt), style: body(size: 13, weight: FontWeight.w800)),
            const TextSpan(text: ':'),
          ])),
          const SizedBox(height: 12),
          _Bullet('Packed quantity: ', nf(h.packed)),
          _Bullet('Pending quantity: ', nf(h.pending)),
          _Bullet('Tables: ', h.tablesSummary),
          _Bullet('Open exceptions: ', '${h.exceptionsCount}'),
          const SizedBox(height: 12),
          Text('Member-wise:', style: body(size: 13, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          if (h.members.isEmpty)
            const Text('—')
          else
            for (final m in h.members)
              Text('• ${m['name']} — ${nf(m['qty'])} qty · ${m['lines']} lines'),
          const SizedBox(height: 12),
          Text(
            'This report was generated automatically by VST SPD. No reply is required.',
            style: body(size: 12.5, color: Brand.txt3),
          ),
        ]),
      ),
    ),
    actions: (context, _) => [GhostButton(label: 'Close', onPressed: () => Navigator.pop(context))],
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '• $label'),
          TextSpan(text: value, style: body(size: 13, weight: FontWeight.w800)),
        ])),
      );
}
