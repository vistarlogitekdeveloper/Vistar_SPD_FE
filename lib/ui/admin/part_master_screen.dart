import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../widgets/common.dart';
import '../widgets/part_photos.dart';
import 'config_screen.dart' show PartMasterPanel;

/// FR-3.5 — the part master, and what it has done to the floor.
///
/// It used to be a panel on Masters & Config, which is an Administrator screen,
/// so the two people most likely to ask it a question could not reach it: the
/// Supervisor whose label count surprises them, and Management reading an MIS
/// built on those pouch counts. It has a screen of its own now, open to all
/// three; replacing the master stays with the Administrator and the Supervisor.
///
/// The master itself is three columns — part number, description, MOQ — because
/// that is the whole of what it is. Everything else about a part belongs to the
/// GRN, so it is answered per part rather than copied in: open a row and it
/// says which invoices carried it, when, how much arrived and how many pouches
/// the MOQ made of that.
class PartMasterScreen extends ConsumerStatefulWidget {
  const PartMasterScreen({super.key});

  @override
  ConsumerState<PartMasterScreen> createState() => _PartMasterScreenState();
}

class _PartMasterScreenState extends ConsumerState<PartMasterScreen> {
  late final TextEditingController _q =
      TextEditingController(text: ref.read(partSearchProvider));

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(partMasterProvider);
    /* The same two roles PUT /masters/parts/:partNo/moq already lets
       write. Management reads the floor and does not change it, so they
       see the figure without a control that would be refused. */
    final role = ref.watch(sessionProvider).user?.roleKey;
    final canWrite = role == 'admin' || role == 'supervisor';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        crumb: 'Masters ·',
        accent: 'Part Master',
        title: 'Pack size per part',
        blurb: 'The MOQ is the number of pieces that go in one pouch, so it decides how many '
            'labels a GRN line becomes. The SAP export carries no MOQ column — this is where '
            'it comes from. Open a part to see which invoices have carried it.',
      ),

      // Upload and the counts. The panel shows itself only to the roles that
      // may replace the master, and draws the summary for the rest.
      const PartMasterPanel(),
      const SizedBox(height: 24),

      FilterBar(
        onReset: _q.text.isEmpty
            ? null
            : () {
                _q.clear();
                ref.read(partSearchProvider.notifier).set('');
              },
        children: [
          Field(
            label: 'Search',
            bottom: 0,
            child: TextField(
              controller: _q,
              style: body(size: 13),
              decoration: const InputDecoration(hintText: 'Part number or description…'),
              onChanged: (v) => ref.read(partSearchProvider.notifier).set(v),
            ),
          ),
        ],
      ),

      async.when(
        skipLoadingOnReload: true,
        loading: () => const SpdLoader(size: 48),
        error: (e, _) {
          /* A console in front of a backend that has not taken these routes
             yet gets a 404, and so does one whose user may not read the
             master. Neither is something the person looking at it can act on
             by retrying, so both say what happened. */
          if (e is ApiException && e.statusCode == 403) {
            return const AlertBox(
              tone: AlertTone.warn,
              title: 'Not available to your role',
              message: 'The part master is open to an Administrator, a Supervisor and '
                  'Management.',
            );
          }
          return ErrorPanel(message: '$e', onRetry: () => ref.invalidate(partMasterProvider));
        },
        data: (page) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (page.shown < page.total) ...[
            BlurbText([
              ('Showing ${nf(page.shown)} of ${nf(page.total)} matching parts', true),
              (' — narrow the search to see the rest.', false),
            ]),
            const SizedBox(height: 12),
          ],
          SpdTable(
            columns: const [
              SpdCol('Part Number', width: 190),
              SpdCol('Description', width: 360, wrap: true),
              SpdCol('MOQ', right: true, width: 110),
              SpdCol('', right: true, width: 250),
            ],
            rows: [
              for (final p in page.parts)
                SpdRow(
                  [
                    strongCell('${p['part_no']}'),
                    wrapCell('${p['description'] ?? ''}'),
                    /* Editable in place. The endpoint already exists for
                       the Lines screen, and the master is where somebody
                       goes when they are fixing pack sizes rather than
                       discovering one is missing — so the list that shows
                       the MOQ should be the list that changes it. Setting
                       one here re-splits every open line of the part, the
                       same as setting it from a row. */
                    _MoqCell(
                      partNo: '${p['part_no']}',
                      description: '${p['description'] ?? ''}',
                      moq: p['moq'] == null ? null : numOf(p['moq']),
                      editable: canWrite,
                    ),
                    /* Two questions, two buttons. The photographs used to
                       open inside the invoice history, which put "what does
                       this part look like" behind "which receipts carried
                       it" — and the first is the one somebody at a bench is
                       asking. They are unrelated facts about the same part;
                       neither belongs inside the other. */
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      GhostButton(
                        label: 'Photos',
                        icon: Icons.photo_camera_outlined,
                        onPressed: () => showPartPhotos(context, ref, '${p['part_no']}',
                            description: '${p['description'] ?? ''}'),
                      ),
                      const SizedBox(width: 6),
                      GhostButton(
                        label: 'Invoices',
                        icon: Icons.receipt_long_outlined,
                        onPressed: () => showPartLines(context, ref, '${p['part_no']}'),
                      ),
                    ]),
                  ],
                  onTap: () => showPartLines(context, ref, '${p['part_no']}'),
                ),
            ],
            emptyMessage: 'No part matches that search.',
          ),
        ]),
      ),
    ]);
  }
}

/// The MOQ as a figure you can change, or just a figure.
///
/// A dash rather than a zero where the master has none: "no pack size on
/// record" and "one piece per pouch" are different facts, and only the
/// first is something to go and fix.
class _MoqCell extends ConsumerWidget {
  const _MoqCell({
    required this.partNo,
    required this.description,
    required this.moq,
    required this.editable,
  });

  final String partNo;
  final String description;
  final num? moq;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!editable) {
      return Align(
        alignment: Alignment.centerRight,
        child: moq == null
            ? Text('—', style: mono(size: 13, color: Brand.txt3))
            : Text(nf(moq), style: mono(size: 13)),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: GhostButton(
        label: moq == null ? 'Set' : nf(moq),
        icon: Icons.edit_outlined,
        onPressed: () => showSetPartMoqDialog(context, ref,
            partNo: partNo, description: description, current: moq),
      ),
    );
  }
}

/// FR-3.5 — give one part its pack size, from the master.
///
/// The twin of showSetMoqDialog on the Lines screen, which asks the same
/// question about a GRN line. They are kept apart rather than shared
/// because what they can say differs: a line knows the quantity that
/// arrived and can offer it as context, and the master knows only the part.
Future<void> showSetPartMoqDialog(
  BuildContext context,
  WidgetRef ref, {
  required String partNo,
  String description = '',
  num? current,
}) async {
  final moq = TextEditingController(text: current == null ? '' : '${current.toInt()}');
  String? error;
  var saving = false;

  await showSpdModal<void>(
    context,
    title: 'Pack size for $partNo',
    subtitle: description,
    content: (context, setModalState) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AlertBox(
        tone: AlertTone.info,
        title: current == null ? 'This part has no pack size yet' : 'This changes the pack size',
        message: 'The MOQ is how many pieces go in one pouch, so it decides how many labels '
            'a GRN line of this part becomes. It is saved against $partNo exactly — other '
            'variants of the same code are not touched — and every line of this part in an '
            'open shift is re-split straight away.',
      ),
      const SizedBox(height: 14),
      Field(
        label: 'Pieces per pouch',
        bottom: 0,
        child: TextField(
          controller: moq,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: mono(size: 14),
          decoration: const InputDecoration(hintText: 'e.g. 1 for one piece per pouch'),
          onChanged: (_) => setModalState(() => error = null),
        ),
      ),
      if (error != null) ...[
        const SizedBox(height: 14),
        AlertBox(tone: AlertTone.bad, title: 'Not saved', message: error!),
      ],
    ]),
    actions: (context, setModalState) => [
      GhostButton(label: 'Cancel', onPressed: saving ? null : () => Navigator.pop(context)),
      GradButton(
        label: saving ? 'Saving…' : 'Save pack size',
        icon: Icons.check_rounded,
        small: true,
        onPressed: saving
            ? null
            : () async {
                final n = num.tryParse(moq.text.trim());
                if (n == null || n <= 0) {
                  setModalState(() => error = 'Enter how many pieces go in one pouch.');
                  return;
                }
                setModalState(() {
                  saving = true;
                  error = null;
                });
                try {
                  final n2 = await ref.read(repositoryProvider).setPartMoq(partNo, n);
                  if (context.mounted) Navigator.pop(context);
                  ref.invalidate(partMasterProvider);
                  invalidateAll(ref);
                  if (context.mounted) {
                    Toast.ok(context, 'Pack size saved',
                        '$partNo is ${nf(n)} per pouch — $n2 line(s) re-split.');
                  }
                } on ApiException catch (e) {
                  setModalState(() {
                    saving = false;
                    error = e.message;
                  });
                }
              },
      ),
    ],
  );
}

/// FR-3.6 — what the part looks like, on its own.
///
/// It used to be rendered inside the invoice-history dialog, which buried
/// "what does this part look like" under "which receipts carried it". The
/// first question is the one asked at a bench, with the part in hand.
///
/// The GRN carries a variant of the master code (BMA14C00540A0 against
/// BMA14C00540), and photographs are keyed by whatever code the line
/// carried — so a part shows its own and its variants’ together, which is
/// what somebody holding one of them means by "this part".
Future<void> showPartPhotos(
  BuildContext context,
  WidgetRef ref,
  String partNo, {
  String description = '',
}) async {
  List<Map<String, dynamic>> lines = const [];
  try {
    lines = (await ref.read(repositoryProvider).partMasterLines(partNo)).lines;
  } on ApiException {
    /* A part no GRN has carried yet still has a master code to photograph
       against, so the gallery opens on that alone rather than refusing. */
  }
  if (!context.mounted) return;

  await showSpdModal<void>(
    context,
    wide: true,
    title: 'Photographs · $partNo',
    subtitle: description.isEmpty
        ? 'Taken at the bench, the first time this part was packed'
        : '$description  ·  taken at the bench, the first time this part was packed',
    content: (context, _) => PartPhotoGallery(partNos: {
      partNo.trim().toUpperCase(),
      for (final l in lines) '${l['part_no']}'.trim().toUpperCase(),
    }.toList()),
    actions: (context, _) => [
      GhostButton(label: 'Close', onPressed: () => Navigator.pop(context)),
    ],
  );
}

/// Which invoices have carried a part, when, and what the MOQ made of them.
Future<void> showPartLines(BuildContext context, WidgetRef ref, String partNo) async {
  ({Map<String, dynamic> part, List<Map<String, dynamic>> lines, Map<String, dynamic> totals})? data;
  String? error;
  try {
    data = await ref.read(repositoryProvider).partMasterLines(partNo);
  } on ApiException catch (e) {
    error = e.message;
  }
  if (!context.mounted) return;

  if (error != null) {
    Toast.bad(context, 'Could not read that part', error);
    return;
  }

  final part = data!.part;
  final lines = data.lines;
  final t = data.totals;

  await showSpdModal<void>(
    context,
    wide: true,
    title: '${part['part_no']}',
    subtitle: '${part['description'] ?? ''}'
        '${part['moq'] == null ? '' : '  ·  MOQ ${nf(part['moq'])} per pouch'}',
    content: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KeyValues([
        ('Invoices', nf(t['invoices'] ?? 0)),
        ('GRN lines', nf(t['lines'] ?? 0)),
        ('Quantity received', nf(t['quantity'] ?? 0)),
        ('Pouches created', nf(t['pouches'] ?? 0)),
      ]),
      const SizedBox(height: 16),
      if (lines.isEmpty)
        const AlertBox(
          tone: AlertTone.info,
          title: 'No GRN has carried this part yet',
          message: 'It is in the master, so the next receipt that names it will be split '
              'by its MOQ.',
        )
      else
        SpdTable(
          maxHeight: 340,
          columns: const [
            SpdCol('Invoice', width: 150),
            SpdCol('GRN Date', width: 120),
            SpdCol('Part on the GRN', width: 160),
            SpdCol('Quantity', right: true, width: 120),
            SpdCol('Pouches', right: true, width: 110),
            SpdCol('Shift', width: 180),
          ],
          rows: [
            for (final l in lines)
              SpdRow([
                strongCell('${l['invoice_no']}'),
                monoCell(fmtD('${l['grn_date']}')),
                /* The code the GRN actually carried, which is the master's
                   plus a two-character variant. Shown rather than hidden: it
                   is why this line is on this part's list at all. */
                monoCell('${l['part_no']}'),
                monoCell('${nf(l['grn_qty'])} ${l['uom'] ?? ''}'),
                monoCell(nf(l['label_count'] ?? 1)),
                cell('${l['shift_label'] ?? l['shift_id']}'),
              ]),
          ],
        ),
    ]),
    actions: (context, _) => [
      GhostButton(label: 'Close', onPressed: () => Navigator.pop(context)),
    ],
  );
}
