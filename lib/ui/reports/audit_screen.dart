import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/downloads.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../widgets/common.dart';

/// NFR-3.3 / NFR-7.1 — every import, allocation, start/submit, exception
/// override, reprint, config change and resubmission, immutable and stamped
/// with user and time.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  late final TextEditingController _q =
      TextEditingController(text: ref.read(auditFilterProvider).q);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  PillTone _tone(String action) {
    if (action.contains('Exception')) return PillTone.bad;
    if (action.contains('Final') || action.contains('Resub')) return PillTone.violet;
    if (action.contains('Import') || action.contains('Hourly')) return PillTone.info;
    return PillTone.ok;
  }

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(auditFilterProvider);
    final async = ref.watch(auditProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        crumb: 'Reports ·',
        accent: 'Audit',
        title: 'Audit trail',
        blurb: 'Every import, allocation, start/submit, exception, reprint, config change and '
            'resubmission — immutable, with user and timestamp (NFR-7.1).',
        actions: [
          GhostButton(label: 'Excel', icon: Icons.download_rounded, onPressed: () => _export(context, 'xlsx', f)),
          GhostButton(label: 'CSV', icon: Icons.download_rounded, onPressed: () => _export(context, 'csv', f)),
        ],
      ),

      FilterBar(
        onReset: () {
          _q.clear();
          ref.read(auditFilterProvider.notifier).set(const AuditFilter());
        },
        children: [
          Field(
            label: 'Action',
            bottom: 0,
            child: SpdDropdown<String>(
              dense: true,
              value: f.action,
              items: [
                const DropdownMenuItem(value: '', child: Text('All actions')),
                for (final a in async.value?.actions ?? const <String>[])
                  DropdownMenuItem(value: a, child: Text(a)),
              ],
              onChanged: (v) =>
                  ref.read(auditFilterProvider.notifier).set(f.copyWith(action: v ?? '')),
            ),
          ),
          Field(
            label: 'Search',
            bottom: 0,
            child: TextField(
              controller: _q,
              style: body(size: 13),
              decoration: const InputDecoration(hintText: 'Part, batch, table…'),
              onChanged: (v) => ref.read(auditFilterProvider.notifier).set(f.copyWith(q: v)),
            ),
          ),
        ],
      ),

      async.when(
        loading: () => const SpdLoader(size: 48),
        error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
        data: (page) => SpdTable(
          columns: const [
            SpdCol('Date', width: 116),
            SpdCol('Time', width: 96),
            SpdCol('User', width: 180),
            SpdCol('Action', width: 168),
            SpdCol('Reference', width: 140),
            SpdCol('Detail', width: 320, wrap: true),
            SpdCol('Before', width: 128),
            SpdCol('After', width: 148),
          ],
          rows: [
            for (final a in page.entries)
              SpdRow([
                monoCell(fmtD(a.at)),
                monoCell(fmtTs(a.at)),
                a.bySystem ? const Pill('System', tone: PillTone.violet) : personCell(a.actorName!),
                Pill(a.action, tone: _tone(a.action)),
                strongCell(a.reference),
                wrapCell(a.detail),
                monoCell(a.before),
                monoCell(a.after),
              ]),
          ],
          emptyMessage: 'No audit entry matches the filter.',
        ),
      ),
    ]);
  }

  Future<void> _export(BuildContext context, String format, AuditFilter f) async {
    try {
      final bytes = await ref.read(repositoryProvider).export(
        key: 'audit',
        format: format,
        query: {'action': f.action, 'q': f.q},
      );
      await saveBytes(
        filename: 'SPD_AUDIT_TRAIL.$format',
        bytes: bytes,
        mime: format == 'csv' ? 'text/csv' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (context.mounted) {
        Toast.ok(context, '${format.toUpperCase()} export ready',
            'SPD_AUDIT_TRAIL.$format is in your downloads.');
      }
    } on ApiException catch (e) {
      if (context.mounted) Toast.warn(context, 'Nothing exported', e.message);
    }
  }
}
