import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// UC-05 / FR-6 — the touch-first packing screen: select the allocated part,
/// Start (the time is recorded for you), pack, then enter the quantity and
/// Submit. Minimal clicks, nothing typed that can be selected (NFR-4.1).
class PackScreen extends ConsumerWidget {
  const PackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myQueueProvider);
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const SpdLoader(),
      error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
      data: (q) {
        if (q.locked) return _Locked(queue: q);
        if (q.running != null) return _Running(queue: q, txn: q.running!);
        return _Select(queue: q);
      },
    );
  }
}

/// BR-06 — the shift is finalised, so entry is closed.
class _Locked extends StatelessWidget {
  const _Locked({required this.queue});

  final MemberQueue queue;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PageHeader(
          crumb: 'My table ·',
          accent: 'Pack',
          title: 'Shift finalised',
          blurb: 'The Supervisor has submitted the final status — data entry is locked for this '
              'shift (BR-06). Ask the Supervisor to reopen if a correction is needed.',
        ),
        AlertBox(
          tone: AlertTone.warn,
          icon: Icons.lock_outline_rounded,
          title: 'Entry locked',
          message: '${queue.shift.label} was finalised at ${fmtTs(queue.shift.finalAt)}.',
        ),
      ]);
}

/// Step one — pick the part and Start.
class _Select extends ConsumerWidget {
  const _Select({required this.queue});

  final MemberQueue queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = queue.openLines;
    final stored = ref.watch(selectedPackLineProvider);
    final selected = open.any((l) => l.id == stored) ? stored : (open.isEmpty ? null : open.first.id);
    final user = ref.watch(sessionProvider).user;
    final clock = ref.watch(packClockProvider).value ?? DateTime.now();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHeader(
        crumb: 'My table ·',
        accent: 'Pack',
        title: 'Select your part & start',
        blurb: 'Your part numbers are selected, never typed — that is what removes the '
            'part-number errors of the paper sheet.',
      ),
      SplitPane(
        sideWidth: 340,
        main: Panel(
          title: 'Lines allocated to ${queue.tableNo}',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (open.isEmpty)
              SpdTable(
                columns: const [SpdCol('')],
                rows: const [],
                emptyMessage: 'All your lines are fully packed. Great shift!',
              )
            else
              for (final l in open)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PartCard(
                    selected: selected == l.id,
                    onTap: () => ref.read(selectedPackLineProvider.notifier).set(l.id),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(l.partNo, style: mono(size: 14, weight: FontWeight.w700))),
                        Pill('Pending ${nf(l.pending)}', tone: PillTone.amber),
                      ]),
                      const SizedBox(height: 6),
                      Text('${l.partDesc} · ${l.invoiceNo} · GRN ${nf(l.grnQty)} ${l.uom}',
                          style: body(size: 12, color: Brand.txt3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
            if (selected != null) ...[
              const SizedBox(height: 18),
              GradButton(
                label: 'Start Packing — ${open.firstWhere((l) => l.id == selected).partNo}',
                icon: Icons.play_arrow_rounded,
                big: true,
                expand: true,
                onPressed: () => _start(context, ref, selected),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'The start date & time is recorded automatically — nothing to write.',
                  style: body(size: 12, color: Brand.txt3),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ]),
        ),
        side: Column(children: [
          Panel(
            title: 'Auto-captured',
            child: KeyValues([
              ('Member', user?.name ?? '—'),
              ('Table', queue.tableNo),
              ('Device', user?.device.isNotEmpty == true ? user!.device : 'web'),
              ('Date', fmtD(clock.toIso8601String().split('T').first)),
              ('Time', fmtTs(clock.toIso8601String())),
            ]),
          ),
          const SizedBox(height: 14),
          Panel(
            title: 'How it works',
            cornerMark: false,
            child: Column(children: const [
              _Step(1, 'Tap your part · tap Start Packing'),
              _Step(2, 'Pack the material physically'),
              _Step(3, 'Enter packed qty, pouches & boxes · Submit'),
              _Step(4, 'Pending qty updates instantly — partial submits allowed'),
            ]),
          ),
        ]),
      ),
    ]);
  }

  Future<void> _start(BuildContext context, WidgetRef ref, String lineId) async {
    try {
      final table = ref.read(sessionProvider).user?.role == 'Member' ? null : ref.read(previewTableProvider);
      final txn = await ref.read(repositoryProvider).startPacking(lineId: lineId, tableNo: table);
      invalidateAll(ref);
      if (context.mounted) {
        Toast.ok(context, 'Packing started',
            'Start time ${fmtTs(txn.startAt)} recorded automatically.');
      }
    } on ApiException catch (e) {
      if (context.mounted) Toast.bad(context, 'Could not start', e.message);
    }
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.text);

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) => ListRow(children: [
        Pill('$n', tone: PillTone.ok),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: body(size: 12))),
      ]);
}

/// Step two — the running activity: elapsed timer, quantity pad, live warning.
class _Running extends ConsumerStatefulWidget {
  const _Running({required this.queue, required this.txn});

  final MemberQueue queue;
  final PackingTxn txn;

  @override
  ConsumerState<_Running> createState() => _RunningState();
}

class _RunningState extends ConsumerState<_Running> {
  final _qty = TextEditingController();
  final _pouches = TextEditingController();
  final _boxes = TextEditingController();
  SubmitHint? _hint;
  Timer? _debounce;
  bool _busy = false;
  bool _qtyError = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _qty.dispose();
    _pouches.dispose();
    _boxes.dispose();
    super.dispose();
  }

  /// FR-7.2 — the same threshold that flags is the one that warns, so the hint
  /// is asked of the server rather than recomputed here.
  void _onQtyChanged(String v) {
    setState(() => _qtyError = false);
    _debounce?.cancel();
    final n = int.tryParse(v);
    if (n == null || n <= 0) {
      setState(() => _hint = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final hint = await ref.read(repositoryProvider).submitHint(lineId: widget.txn.lineId, qty: n);
        if (mounted) setState(() => _hint = hint);
      } on ApiException {
        // A missing hint is cosmetic; the submit itself is still validated.
      }
    });
  }

  Future<void> _submit() async {
    final raw = _qty.text.trim();
    final n = int.tryParse(raw);
    // BR-02 — blank, zero, negative or non-numeric is refused before the call,
    // and again on the server, which is the one that matters.
    if (raw.isEmpty || n == null || n <= 0) {
      setState(() => _qtyError = true);
      Toast.bad(
        context,
        'Invalid quantity',
        'Packed quantity must be a whole number greater than zero — blank, zero, negative or '
            'non-numeric entries are rejected (BR-02).',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final res = await ref.read(repositoryProvider).submitPacking(
            txnId: widget.txn.id,
            qty: n,
            pouches: int.tryParse(_pouches.text) ?? 0,
            boxes: int.tryParse(_boxes.text) ?? 0,
          );
      invalidateAll(ref);
      if (!mounted) return;
      final elapsed = durTxt(between(res.txn.startAt, res.txn.submitAt));
      if (res.exception != null) {
        Toast.warn(context, 'Submitted — flagged for review',
            '${res.exception!.type}: ${res.exception!.detail} The Supervisor must add remarks before final submission.');
      } else {
        Toast.ok(
          context,
          'Submitted',
          '${res.line.partNo} · ${nf(n)} ${res.line.uom} recorded in $elapsed. Pending is now '
              '${nf(res.line.pending < 0 ? 0 : res.line.pending)} — updated live on the Supervisor’s dashboard.',
        );
      }
      if (res.line.pending > 0) {
        ref.read(selectedPackLineProvider.notifier).set(res.line.id);
      } else {
        ref.read(selectedPackLineProvider.notifier).set(null);
        if (mounted) context.go('/my/work');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _qtyError = e.statusCode == 400;
        });
        Toast.bad(context, 'Submit refused', e.message);
      }
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.txn;
    final line = widget.queue.lines.where((l) => l.id == t.lineId).firstOrNull;
    final pending = line?.pending ?? (t.grnQty - 0);
    final packed = line?.packed ?? 0;
    // Ticks once a second so the elapsed clock counts up (FR-6.3).
    final now = ref.watch(packClockProvider).value ?? DateTime.now();
    final elapsed = now.difference(DateTime.parse('${t.startAt}').toLocal());

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        crumb: 'My table ·',
        accent: 'Pack',
        title: 'Packing in progress',
        blurbWidget: BlurbText([
          (t.partNo, true),
          (' · ${t.partDesc} · ${t.invoiceNo} — enter the packed quantity when done. '
              'Partial quantities are fine (FR-6.5).', false),
        ]),
      ),
      SplitPane(
        sideWidth: 340,
        main: SpdCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
              child: Column(children: [
                Text('ELAPSED', style: eyebrow(size: 12, tracking: 1.5)),
                const SizedBox(height: 4),
                GradientText(
                  clockMs(elapsed.isNegative ? Duration.zero : elapsed),
                  style: display(size: 42, height: 1),
                ),
                const SizedBox(height: 4),
                Text('started ${fmtTs(t.startAt)} · recorded automatically',
                    style: body(size: 12, color: Brand.txt3)),
              ]),
            ),
            const Hairline(),
            Field(
              label: 'Packed quantity · pending ${nf(pending)} ${t.uom}',
              required: true,
              child: TextField(
                controller: _qty,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: mono(size: 26, weight: FontWeight.w800),
                decoration: InputDecoration(
                  hintText: '0',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Brand.rSm),
                    borderSide: BorderSide(color: _qtyError ? Brand.bad.withValues(alpha: 0.65) : Brand.fieldLine),
                  ),
                ),
                onChanged: _onQtyChanged,
                onSubmitted: (_) => _submit(),
              ),
            ),
            Row(children: [
              Expanded(
                child: Field(
                  label: 'Pouches',
                  child: TextField(
                    controller: _pouches,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: mono(size: 19, weight: FontWeight.w800),
                    decoration: const InputDecoration(
                      hintText: '0',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Field(
                  label: 'Boxes',
                  child: TextField(
                    controller: _boxes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: mono(size: 19, weight: FontWeight.w800),
                    decoration: const InputDecoration(
                      hintText: '0',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
              ),
            ]),
            if (_hint != null)
              AlertBox(
                tone: AlertTone.parse(_hint!.tone),
                title: _hint!.title,
                message: _hint!.message,
              ),
            const SizedBox(height: 14),
            GradButton(
              label: _busy ? 'Submitting…' : 'Submit',
              icon: Icons.check_rounded,
              big: true,
              expand: true,
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Blank, zero, negative or non-numeric quantity is rejected (BR-02). '
                'Over-GRN entries are flagged to the Supervisor (BR-03).',
                style: body(size: 11, color: Brand.txt3),
                textAlign: TextAlign.center,
              ),
            ),
          ]),
        ),
        side: Panel(
          title: 'This line',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KeyValues([
              ('Part', t.partNo),
              ('Invoice', t.invoiceNo),
              ('GRN quantity', '${nf(t.grnQty)} ${t.uom}'),
              ('Packed so far', nf(packed)),
              ('Pending', nf(pending)),
            ]),
            const SizedBox(height: 14),
            ProgressBar(percent: pct(packed, t.grnQty)),
          ]),
        ),
      ),
    ]);
  }
}
