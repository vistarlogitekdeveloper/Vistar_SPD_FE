import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/downloads.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// UC-01 / FR-1 — upload the SAP GRN export, see it validated column by column,
/// and keep the import history the SRS asks for (FR-1.6).
class GrnUploadScreen extends ConsumerStatefulWidget {
  const GrnUploadScreen({super.key});

  @override
  ConsumerState<GrnUploadScreen> createState() => _GrnUploadScreenState();
}

class _GrnUploadScreenState extends ConsumerState<GrnUploadScreen> {
  bool _busy = false;
  GrnImportResult? _result;
  String? _error;
  List<Map<String, dynamic>> _errorRows = const [];

  Future<void> _pickAndUpload({bool confirm = false, String reason = '', PlatformFile? reuse}) async {
    final shiftId = ref.read(selectedShiftProvider);
    if (shiftId == null) return;

    final PlatformFile file;
    if (reuse != null) {
      file = reuse;
    } else {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xls', 'csv'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      file = picked.files.first;
    }
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'That file could not be read — try selecting it again');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _errorRows = const [];
    });

    try {
      final res = await ref.read(repositoryProvider).uploadGrn(
            shiftId: shiftId,
            filename: file.name,
            bytes: bytes,
            confirm: confirm,
            reason: reason,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = res;
        _errorRows = res.errors;
      });
      invalidateAll(ref);
      Toast.ok(
        context,
        'GRN batch imported',
        '${res.imported} line${res.imported == 1 ? '' : 's'} added as ${res.batchId} and displayed '
            'invoice-wise / part-number-wise.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorRows = e.rowErrors;
        _error = e.message;
      });

      // BR-08 — a duplicate batch is a decision, not a failure: offer the
      // confirm-with-reason path rather than just refusing.
      if (e.isDuplicateBatch) {
        setState(() => _error = null);
        await _confirmReupload(e, file);
      } else {
        Toast.bad(context, 'Upload rejected', e.message);
      }
    }
  }

  Future<void> _confirmReupload(ApiException e, PlatformFile file) async {
    final details = e.details as Map;
    final rows = (details['rows'] as List? ?? const []).cast<Map>();
    final controller = TextEditingController();

    await showSpdModal<void>(
      context,
      title: 'Duplicate GRN batch detected',
      subtitle: 'BR-08 · double-counting protection',
      content: (context, setModalState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AlertBox(tone: AlertTone.warn, title: file.name, message: e.message),
        const SizedBox(height: 14),
        if (rows.isNotEmpty)
          SpdTable(
            columns: const [
              SpdCol('Invoice', width: 120),
              SpdCol('Part Number', width: 140),
              SpdCol('Already in batch', width: 140),
              SpdCol('Uploaded by', width: 160),
            ],
            rows: [
              for (final r in rows.take(8))
                SpdRow([
                  monoCell('${r['invoice_no']}'),
                  strongCell('${r['part_no']}'),
                  monoCell('${r['batch_id']}'),
                  cell('${r['uploaded_by_name'] ?? '—'}'),
                ]),
            ],
            maxHeight: 260,
          ),
        const SizedBox(height: 14),
        Field(
          label: 'Reason for intentional re-upload',
          required: true,
          bottom: 0,
          child: TextField(
            controller: controller,
            style: body(size: 14),
            decoration: const InputDecoration(hintText: 'e.g. SAP correction re-export for INV-77003'),
          ),
        ),
      ]),
      actions: (context, _) => [
        GhostButton(label: 'Cancel upload', onPressed: () => Navigator.pop(context)),
        GhostButton(
          label: 'Confirm re-upload',
          danger: true,
          onPressed: () {
            final r = controller.text.trim();
            if (r.isEmpty) {
              Toast.bad(context, 'Reason required', 'A confirmed re-upload must carry a reason (BR-08).');
              return;
            }
            Navigator.pop(context);
            _pickAndUpload(confirm: true, reason: r, reuse: file);
          },
        ),
      ],
    );
  }

  Future<void> _saveErrorFile() async {
    final rows = _errorRows;
    if (rows.isEmpty) return;
    String q(dynamic v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"';
    final csv = StringBuffer('﻿')
      ..writeln(['Row', 'Column', 'Value', 'Error'].map(q).join(','));
    for (final e in rows) {
      csv.writeln([e['row'], e['column'], e['value'], e['error']].map(q).join(','));
    }
    await saveBytes(
      filename: 'GRN_UPLOAD_ERRORS.csv',
      bytes: Uint8List.fromList(utf8.encode(csv.toString())),
      mime: 'text/csv',
    );
    if (mounted) {
      Toast.ok(context, 'Error file saved', 'GRN_UPLOAD_ERRORS.csv — ${rows.length} rejected rows.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(configProvider).value ?? SpdConfig.empty();
    final shift = ref.watch(currentShiftProvider);
    final batches = ref.watch(grnBatchesProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHeader(
        crumb: 'GRN ·',
        accent: 'Upload',
        title: 'GRN upload & import history',
        blurb: 'Upload the day-wise GRN report exported from SAP (.xlsx / .csv). The file is '
            'validated column by column before import — no more copy-paste into the Excel master.',
      ),

      ResponsiveGrid(columns: 2, children: [
        Panel(
          title: 'Upload SAP GRN export',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Field(
              label: 'Shift / date',
              hint: 'Switch shift from the picker in the top bar.',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: Brand.field,
                  border: Border.all(color: Brand.fieldLine),
                  borderRadius: BorderRadius.circular(Brand.rSm),
                ),
                child: Row(children: [
                  Expanded(child: Text(shift?.label ?? '—', style: body(size: 14))),
                  StatusPill(shift?.status ?? 'Open'),
                ]),
              ),
            ),
            if (shift?.finalised == true)
              AlertBox(
                tone: AlertTone.warn,
                title: 'This shift is finalised (BR-06)',
                message: 'Reopen it from Review & Finalise before importing more GRN data.',
              )
            else
              DropZone(
                title: 'Drop GRN_SAP_EXPORT.xlsx / .csv here',
                subtitle: 'or click to browse · validated against ${cfg.grnCols.length} required columns before import',
                onTap: _busy ? null : () => _pickAndUpload(),
              ),
            if (_busy) ...[
              const SizedBox(height: 14),
              Row(children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Brand.pink),
                ),
                const SizedBox(width: 10),
                Text('Validating and importing…', style: body(size: 13, color: Brand.txt3)),
              ]),
            ],
            if (_result != null) ...[
              const SizedBox(height: 14),
              AlertBox(
                tone: _result!.rejected > 0 ? AlertTone.warn : AlertTone.ok,
                title: _result!.rejected > 0 ? 'GRN imported with rejections' : 'GRN imported',
                message: '${_result!.imported} of ${_result!.imported + _result!.rejected} rows validated and '
                    'imported as batch ${_result!.batchId}. '
                    '${_result!.rejected > 0 ? '${_result!.rejected} row(s) rejected — see below.' : 'Lines are ready for label printing and table allocation.'}',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              AlertBox(
                tone: AlertTone.bad,
                title: 'Upload rejected — file failed validation (FR-1.3)',
                message: _error!,
              ),
            ],
            // FR-1.3 — the exact row and column of every problem.
            if (_errorRows.isNotEmpty) ...[
              const SizedBox(height: 14),
              SpdTable(
                columns: const [
                  SpdCol('Row', width: 80),
                  SpdCol('Column', width: 150),
                  SpdCol('Value', width: 150),
                  SpdCol('Error', width: 240, wrap: true),
                ],
                rows: [
                  for (final e in _errorRows)
                    SpdRow([
                      monoCell('${e['row']}'),
                      cell('${e['column']}'),
                      monoCell('${e['value']}'.isEmpty ? '—' : '${e['value']}'),
                      wrapCell('${e['error']}'),
                    ]),
                ],
                maxHeight: 280,
              ),
              const SizedBox(height: 10),
              GhostButton(label: 'Error file', icon: Icons.download_rounded, onPressed: _saveErrorFile),
            ],
          ]),
        ),
        Panel(
          title: 'Import columns (configurable)',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in cfg.grnCols) SpdChip(c, selected: true),
                // NFR-6.1 — read when the export carries them. Shown unselected
                // so it is visible that MOQ is picked up (FR-3.5) without
                // implying the file is rejected for omitting it.
                for (final c in cfg.grnColsOptional) SpdChip('$c (optional)'),
              ],
            ),
            const Hairline(),
            const AlertBox(
              tone: AlertTone.info,
              title: 'BR-08 — duplicate protection',
              message: 'Re-uploading a GRN batch already imported for the same date/invoice is blocked '
                  'unless the Supervisor confirms an intentional correction — preventing double-counting.',
            ),
            const SizedBox(height: 10),
            const AlertBox(
              tone: AlertTone.warn,
              title: 'Row/column-level rejection (FR-1.3)',
              message: 'Invalid files never fail silently — the exact row and column of every problem is named.',
            ),
            const SizedBox(height: 10),
            const AlertBox(
              tone: AlertTone.info,
              title: 'NFR-6.1 — the column mapping is configuration',
              message: 'A change to the SAP export header is edited in Masters & Config, not released in code.',
            ),
          ]),
        ),
      ]),

      const SizedBox(height: 18),
      const SectionTitle('Import history (FR-1.6)'),
      batches.when(
        skipLoadingOnReload: true,
        loading: () => const SpdLoader(size: 40, fill: false),
        error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
        data: (list) => SpdTable(
          columns: const [
            SpdCol('Batch', width: 120),
            SpdCol('File', width: 250),
            SpdCol('Shift', width: 180),
            SpdCol('Uploaded', width: 180),
            SpdCol('By', width: 150),
            SpdCol('Rows', right: true, width: 80),
            SpdCol('Rejected', right: true, width: 92),
            SpdCol('Status', width: 120),
            SpdCol('', right: true, width: 110),
          ],
          rows: [
            for (final b in list)
              SpdRow([
                strongCell(b.id),
                monoCell(b.fileName),
                cell(b.shiftLabel),
                monoCell(fmtDateTime(b.uploadedAt)),
                cell(b.uploadedByName),
                monoCell('${b.rowCount}'),
                monoCell('${b.rejectedCount}', color: b.rejectedCount > 0 ? Brand.warn : null),
                Pill(b.status, tone: b.status == 'Imported' ? PillTone.ok : PillTone.neutral),
                // FR-1.6 — the wrong file uploaded is corrected by discarding
                // the batch. The server refuses once anything has been packed
                // against it, so this only ever removes work nobody has begun.
                GhostButton(
                  label: 'Discard',
                  danger: true,
                  onPressed: () => _discardBatch(context, ref, b),
                ),
              ]),
          ],
          emptyMessage: 'No GRN report has been imported yet.',
        ),
      ),
    ]);
  }
}

/// FR-1.6 — discards a mis-imported GRN batch and everything it brought in.
///
/// Confirmed first, because it takes the whole upload away. The refusal case —
/// anything already packed against it — is the server's to decide and arrives
/// as the message it gives.
Future<void> _discardBatch(BuildContext context, WidgetRef ref, GrnBatch b) async {
  final ok = await showSpdModal<bool>(
        context,
        title: 'Discard GRN batch',
        subtitle: '${b.id} · ${b.fileName}',
        content: (context, _) => AlertBox(
          tone: AlertTone.warn,
          title: '${b.rowCount} imported line${b.rowCount == 1 ? '' : 's'} will be removed',
          message: 'Use this when the wrong file was uploaded. If any of these lines have '
              'been packed against, the server will refuse and the batch stays.',
        ),
        actions: (context, _) => [
          GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context, false)),
          GradButton(label: 'Discard', onPressed: () => Navigator.pop(context, true)),
        ],
      ) ??
      false;
  if (!ok || !context.mounted) return;

  try {
    await ref.read(repositoryProvider).deleteGrnBatch(b.id);
    invalidateAll(ref);
    if (context.mounted) Toast.ok(context, 'Batch discarded', '${b.id} and its lines are gone.');
  } on ApiException catch (e) {
    if (context.mounted) Toast.bad(context, 'Could not discard the batch', e.message);
  }
}
