import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// FR-3.5 — the pack size each part is pouched in.
///
/// The SAP goods-receipt export carries no MOQ column and never will: it
/// reports what arrived, not how the floor handles it. Without this master a
/// GRN prints one label per line and nothing splits, which is the opposite of
/// what pre-packing is for.
///
/// Uploading REPLACES the master. It states the whole catalogue at a point in
/// time, so a part dropped from the file has been dropped from the catalogue;
/// merging would leave it answering lookups forever with a pack size nobody
/// still believes.
class PartMasterPanel extends ConsumerStatefulWidget {
  const PartMasterPanel({super.key});

  @override
  ConsumerState<PartMasterPanel> createState() => _PartMasterPanelState();
}

class _PartMasterPanelState extends ConsumerState<PartMasterPanel> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _result;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (ref.read(sessionProvider).user?.roleKey != 'admin') return;
    try {
      final m = await ref.read(repositoryProvider).partMaster();
      if (!mounted) return;
      setState(() => _summary = m.summary);
    } on ApiException catch (e) {
      if (!mounted) return;
      // A console in front of a backend without migration 210 answers 404.
      // The panel says nothing rather than showing a failure nobody can act on.
      if (e.statusCode != 404) setState(() => _error = e.message);
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls', 'csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'That file could not be read — try selecting it again');
      return;
    }

    setState(() { _busy = true; _error = null; _result = null; });
    try {
      final res = await ref.read(repositoryProvider)
          .uploadPartMaster(filename: file.name, bytes: bytes);
      if (!mounted) return;
      setState(() { _result = res; _busy = false; });
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    /* Administrator only, matching the endpoints. A Supervisor reaching this
       screen sees nothing here rather than a panel that answers 403 on use:
       an upload button that cannot upload is worse than no button. */
    if (ref.watch(sessionProvider).user?.roleKey != 'admin') {
      return const SizedBox.shrink();
    }

    final s = _summary;
    final r = _result;
    return Panel(
      title: 'Part master — MOQ (FR-3.5)',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        BlurbText(const [
          ('The pack size each part is pouched in. ', false),
          ('The SAP export does not carry one', true),
          (', so without this master every GRN line prints a single label and nothing splits. '
              'Uploading replaces the master.', false),
        ]),
        const SizedBox(height: 12),

        if (s != null)
          KeyValues([
            ('Parts', nf(s['parts'] ?? 0)),
            ('With an MOQ', nf(s['with_moq'] ?? 0)),
            ('Of those, MOQ 1', nf(s['moq_one'] ?? 0)),
            (
              'Last updated',
              s['updated_at'] == null ? 'never uploaded' : '${s['updated_at']}'.split('T').first,
            ),
          ]),

        if (_error != null) ...[
          const SizedBox(height: 12),
          AlertBox(tone: AlertTone.bad, title: 'Part master', message: _error!),
        ],

        if (r != null) ...[
          const SizedBox(height: 12),
          AlertBox(
            tone: (r['rejected'] ?? 0) == 0 ? AlertTone.ok : AlertTone.warn,
            title: '${nf(r['parts'] ?? 0)} parts loaded',
            message: '${nf(r['withMoq'] ?? 0)} carry an MOQ, ${nf(r['moqOne'] ?? 0)} of them MOQ 1. '
                'Replaced ${nf(r['replaced'] ?? 0)} previous row(s).'
                '${(r['rejected'] ?? 0) == 0 ? '' : ' ${nf(r['rejected'])} row(s) rejected.'}',
          ),
        ],

        const SizedBox(height: 12),
        GradButton(
          label: _busy ? 'Uploading…' : 'Upload MOQ master',
          icon: Icons.upload_file_rounded,
          small: true,
          onPressed: _busy ? null : _upload,
        ),
      ]),
    );
  }
}

/// UC-10 / FR-13.2 & NFR-5.1 — tables, label template, email distribution,
/// exception threshold and reporting intervals, all editable without a release.
class ConfigScreen extends ConsumerStatefulWidget {
  const ConfigScreen({super.key});

  @override
  ConsumerState<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends ConsumerState<ConfigScreen> {
  final _threshold = TextEditingController();
  final _hourly = TextEditingController();
  final _refresh = TextEditingController();
  final _emails = TextEditingController();
  final _grnCols = TextEditingController();
  final _grnColsOptional = TextEditingController();
  String? _labelTpl;
  bool _loaded = false;
  bool _busy = false;

  static const _templates = ['SPD Standard 100×60', 'SPD Compact 70×40', 'Customer format A'];

  @override
  void dispose() {
    _threshold.dispose();
    _hourly.dispose();
    _refresh.dispose();
    _emails.dispose();
    _grnCols.dispose();
    _grnColsOptional.dispose();
    super.dispose();
  }

  void _fill(SpdConfig cfg) {
    if (_loaded) return;
    _threshold.text = '${cfg.threshold}';
    _hourly.text = '${cfg.hourly}';
    _refresh.text = '${cfg.refresh}';
    _emails.text = cfg.emails.join(', ');
    _grnCols.text = cfg.grnCols.join(', ');
    _grnColsOptional.text = cfg.grnColsOptional.join(', ');
    _labelTpl = _templates.contains(cfg.labelTpl) ? cfg.labelTpl : _templates.first;
    _loaded = true;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveConfig({
        'threshold': int.tryParse(_threshold.text) ?? 50,
        'hourly': int.tryParse(_hourly.text) ?? 60,
        'refresh': int.tryParse(_refresh.text) ?? 60,
        'emails': _emails.text,
        'grnCols': _grnCols.text,
        'grnColsOptional': _grnColsOptional.text,
        'labelTpl': _labelTpl,
      });
      invalidateAll(ref);
      if (mounted) {
        Toast.ok(context, 'Configuration saved',
            'New thresholds and intervals apply immediately — validations use them live.');
      }
    } on ApiException catch (e) {
      // NFR-4.2 — the server names the exact limit breached; show that, not a
      // generic failure.
      if (mounted) Toast.bad(context, 'Configuration not saved', e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(configProvider);
    final tables = ref.watch(tablesProvider);
    final users = ref.watch(usersProvider).value ?? const <SpdUser>[];

    return cfgAsync.when(
      skipLoadingOnReload: true,
      loading: () => const SpdLoader(),
      error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
      data: (cfg) {
        _fill(cfg);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PageHeader(
            crumb: 'Admin ·',
            accent: 'Config',
            title: 'Masters & configuration',
            blurb: 'Tables, label template, email distribution, exception threshold and reporting '
                'intervals — all configurable without code changes (NFR-5.1).',
          ),

          ResponsiveGrid(columns: 2, children: [
            Panel(
              title: 'Packing tables (Table Master)',
              // FR-13.1 — allocation can only offer the tables that exist, and
              // until now the only ones that could were the eight the seed
              // wrote. The server has always had the route.
              trailing: GhostButton(
                label: 'Add table',
                icon: Icons.add_rounded,
                onPressed: () => _showAddTable(context, ref),
              ),
              child: tables.when(
                skipLoadingOnReload: true,
                loading: () => const SpdLoader(size: 36, fill: false),
                error: (e, _) => Text('$e', style: body(size: 13, color: Brand.bad)),
                data: (list) => SpdTable(
                  columns: const [
                    SpdCol('Table', width: 82),
                    SpdCol('Assigned member', width: 190),
                    SpdCol('Status', width: 116),
                    SpdCol('Lines today', right: true, width: 106),
                  ],
                  rows: [
                    for (final t in list)
                      SpdRow(
                        [
                          strongCell(t.tableNo),
                          t.memberName == null
                              ? Text('unstaffed', style: body(size: 13, color: Brand.txt3))
                              : cell(t.memberName!),
                          StatusPill(t.status),
                          monoCell('${t.allocatedLines}'),
                        ],
                        onTap: () => _assign(context, t.tableNo, t.memberId, users),
                      ),
                  ],
                ),
              ),
            ),
            const PartMasterPanel(),

            Panel(
              title: 'System parameters',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _NumField(
                  label: 'Abnormal-entry exception threshold (FR-7.2)',
                  controller: _threshold,
                  suffix: '% of GRN qty in a single submission',
                ),
                _NumField(
                  label: 'Hourly report interval (FR-8.1)',
                  controller: _hourly,
                  suffix: 'minutes',
                ),
                _NumField(
                  label: 'Dashboard auto-refresh (FR-11.4)',
                  controller: _refresh,
                  suffix: 'seconds',
                ),
                Field(
                  label: 'Label template',
                  child: SpdDropdown<String>(
                    value: _labelTpl,
                    items: [for (final t in _templates) DropdownMenuItem(value: t, child: Text(t))],
                    onChanged: (v) => setState(() => _labelTpl = v),
                  ),
                ),
                Field(
                  label: 'Hourly report distribution list (FR-8.2)',
                  hint: 'Comma-separated.',
                  child: TextField(controller: _emails, style: body(size: 14)),
                ),
                Field(
                  label: 'GRN import columns — required (NFR-6.1)',
                  hint: 'The header the SAP export is validated against. A format change is edited '
                      'here, not released in code.',
                  child: TextField(controller: _grnCols, maxLines: 2, style: body(size: 14)),
                ),
                Field(
                  label: 'GRN import columns — optional (NFR-6.1)',
                  hint: 'Read when the export carries them, ignored when it does not. MOQ is here: '
                      'a line that has one prints a label per pack (FR-3.5), and a line without '
                      'one prints a single label as before.',
                  child: TextField(controller: _grnColsOptional, maxLines: 2, style: body(size: 14)),
                ),
                GradButton(
                  label: _busy ? 'Saving…' : 'Save configuration',
                  icon: Icons.check_rounded,
                  small: true,
                  onPressed: _busy ? null : _save,
                ),
              ]),
            ),
          ]),

          const SizedBox(height: 18),
          const AlertBox(
            tone: AlertTone.info,
            title: 'Everything above is audit-logged',
            message: 'Master-data changes, label reprints, exception overrides and resubmissions are '
                'recorded with user, timestamp and reason (NFR-3.3).',
          ),
        ]);
      },
    );
  }

  /// FR-13.2 — assigning a member to a table. A member can hold only one table,
  /// which the server enforces; this dialog just makes the choice.
  Future<void> _assign(BuildContext context, String tableNo, String? current, List<SpdUser> users) async {
    final members = users.where((u) => u.role == 'Member' && u.active).toList();
    var selected = current;

    await showSpdModal<void>(
      context,
      title: 'Assign a member to $tableNo',
      subtitle: 'The allocated lines appear on that member’s screen (BR-05)',
      content: (context, setModalState) => Field(
        label: 'Table member',
        bottom: 0,
        child: SpdDropdown<String>(
          value: selected,
          items: [
            const DropdownMenuItem(value: null, child: Text('Unstaffed')),
            for (final m in members)
              DropdownMenuItem(value: m.id, child: Text('${m.name} · ${m.empCode}')),
          ],
          onChanged: (v) => setModalState(() => selected = v),
        ),
      ),
      actions: (context, _) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        GradButton(
          label: 'Save',
          icon: Icons.check_rounded,
          small: true,
          onPressed: () async {
            try {
              await ref.read(repositoryProvider).assignTableMember(tableNo: tableNo, memberId: selected);
              if (context.mounted) Navigator.pop(context);
              invalidateAll(ref);
              if (context.mounted) Toast.ok(context, 'Table updated', '$tableNo saved.');
            } on ApiException catch (e) {
              if (context.mounted) Toast.bad(context, 'Could not save', e.message);
            }
          },
        ),
      ],
    );
  }
}

class _NumField extends StatelessWidget {
  const _NumField({required this.label, required this.controller, required this.suffix});

  final String label, suffix;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => Field(
        label: label,
        child: Row(children: [
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: mono(size: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(suffix, style: body(size: 13, color: Brand.txt3))),
        ]),
      );
}

/// FR-13.1 — adds a packing table to the master.
///
/// The number is what allocation, the status board and every member's queue key
/// off, so it follows the seeded convention (T-01, T-02…) rather than being
/// free text. The member is optional: a bench can exist before anyone is put on
/// it, which is how a new table is usually added.
Future<void> _showAddTable(BuildContext context, WidgetRef ref) async {
  final existing = ref.read(tablesProvider).value ?? const <TableStat>[];
  final members = (ref.read(usersProvider).value ?? const <SpdUser>[])
      .where((u) => u.role == 'Member')
      .toList();

  // The next free number in the series, so the common case needs no typing.
  var n = existing.length + 1;
  while (existing.any((t) => t.tableNo == 'T-${n.toString().padLeft(2, '0')}')) {
    n++;
  }
  final controller = TextEditingController(text: 'T-${n.toString().padLeft(2, '0')}');
  String? memberId;

  await showSpdModal<void>(
    context,
    title: 'Add a packing table',
    subtitle: '${existing.length} table(s) on the floor today',
    content: (context, setModalState) => Column(children: [
      Field(
        label: 'Table number',
        required: true,
        hint: 'Used by allocation, the status board and every member queue.',
        child: TextField(controller: controller, style: body(size: 14)),
      ),
      Field(
        label: 'Assigned member',
        hint: 'Optional — a table can exist before anyone is put on it.',
        bottom: 0,
        child: SpdDropdown<String>(
          value: memberId,
          items: [
            const DropdownMenuItem(value: null, child: Text('Unassigned')),
            for (final m in members)
              DropdownMenuItem(value: m.id, child: Text('${m.name} · ${m.empCode}')),
          ],
          onChanged: (v) => setModalState(() => memberId = v),
        ),
      ),
    ]),
    actions: (context, _) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
      GradButton(
        label: 'Add table',
        icon: Icons.check_rounded,
        onPressed: () async {
          final tableNo = controller.text.trim();
          if (tableNo.isEmpty) {
            Toast.bad(context, 'Table not added', 'A table needs a number.');
            return;
          }
          try {
            await ref.read(repositoryProvider).createTable(
                  tableNo: tableNo,
                  memberId: memberId,
                  sortOrder: existing.length,
                );
            invalidateAll(ref);
            if (context.mounted) Navigator.pop(context);
            if (context.mounted) Toast.ok(context, 'Table added', '$tableNo is on the floor.');
          } on ApiException catch (e) {
            if (context.mounted) Toast.bad(context, 'Could not add the table', e.message);
          }
        },
      ),
    ],
  );
}
