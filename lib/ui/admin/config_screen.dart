import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

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
    super.dispose();
  }

  void _fill(SpdConfig cfg) {
    if (_loaded) return;
    _threshold.text = '${cfg.threshold}';
    _hourly.text = '${cfg.hourly}';
    _refresh.text = '${cfg.refresh}';
    _emails.text = cfg.emails.join(', ');
    _grnCols.text = cfg.grnCols.join(', ');
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
      loading: () => const Padding(padding: EdgeInsets.only(top: 80), child: SpdLoader()),
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
              child: tables.when(
                loading: () => const SpdLoader(size: 36),
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
                  label: 'GRN import columns (NFR-6.1)',
                  hint: 'The header the SAP export is validated against. A format change is edited '
                      'here, not released in code.',
                  child: TextField(controller: _grnCols, maxLines: 2, style: body(size: 14)),
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
