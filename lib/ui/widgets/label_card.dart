import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';

/// `.plabel` — the ID label as it prints (FR-3.1): part number, description,
/// invoice, GRN quantity, GRN date, packer, packing date and a scannable QR.
/// No barcode and no vendor name: the QR is the one code the floor scans.
///
/// The QR modules come from the server, which is the
/// same code that draws the PDF — so what a supervisor approves on screen is
/// what the printer produces, rather than two implementations that agree today.
class LabelCard extends StatelessWidget {
  const LabelCard({super.key, required this.preview, this.unit, this.width = 330});

  final LabelPreview preview;

  /// FR-3.5 — which of the line's labels to draw. Defaults to the first, which
  /// is the only one for a line without an MOQ.
  final LabelUnit? unit;

  final double width;

  @override
  Widget build(BuildContext context) {
    final l = preview.line;
    final u = unit ?? (preview.labels.isEmpty ? null : preview.first);
    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Color(0x99000000), blurRadius: 30, spreadRadius: -14, offset: Offset(0, 10)),
        ],
      ),
      child: Stack(children: [
        // .lb-strip
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 5,
          child: DecoratedBox(decoration: BoxDecoration(gradient: Brand.labelStrip)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.partNo,
                      style: display(size: 17, color: const Color(0xFF14091F)).copyWith(letterSpacing: -0.3)),
                  const SizedBox(height: 1),
                  Text(l.partDesc,
                      style: body(size: 10, color: const Color(0xFF444444)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  /* A Wrap, not a Row: the captions sit on as few lines as the
                     width allows and flow onto another rather than overflowing,
                     which is the same rule the PDF follows — it fits three
                     columns beside the code on the 100×60 stock and two on the
                     70×40, and wraps the rest onto a second row.

                     Packer and packing date are what the label can know rather
                     than what it would like to: the sheet is printed before the
                     line reaches a bench, so the packer is whoever staffs the
                     tables it has been allocated to, and the date is the
                     shift's. Neither prints until the line is allocated,
                     because a blank is honest where a guess is not. */
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    _Field('INVOICE', l.invoiceNo),
                    /* This pack's own quantity, which is the whole GRN quantity
                       unless the line was split by MOQ. Which pack it is
                       belongs on this caption, because this is the number it
                       qualifies. */
                    _Field(
                      u != null && u.isSplit ? 'QTY (${u.marker.toUpperCase()})' : 'QTY',
                      '${nf(u?.qty ?? l.grnQty)} ${l.uom}',
                    ),
                    _Field('GRN DATE', fmtD(l.grnDate)),
                    _Field('PACKER', l.packer ?? '—'),
                    _Field('PACKED ON', l.packedOn == null ? '—' : fmtD(l.packedOn!)),
                    // FR-3.1 still wants the GRN quantity on the label, so when
                    // QTY is only this pack's share, both numbers are printed.
                    if (u != null && u.isSplit) _Field('GRN TOTAL', '${nf(l.grnQty)} ${l.uom}'),
                  ]),
                ]),
              ),
              const SizedBox(width: 10),
              _Qr(modules: u?.qr ?? const [], size: 62),
            ]),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text('SPD PRE-PACK', style: body(size: 11, color: const Color(0xFF555555))),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.caption, this.value);

  final String caption, value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(caption,
              style: body(size: 9.5, color: const Color(0xFF333333)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(value,
              style: body(size: 11, weight: FontWeight.w700, color: const Color(0xFF111111)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      );
}

class _Qr extends StatelessWidget {
  const _Qr({required this.modules, required this.size});

  final List<List<bool>> modules;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _QrPainter(modules)));
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.modules);

  final List<List<bool>> modules;

  @override
  void paint(Canvas canvas, Size size) {
    if (modules.isEmpty) return;
    final n = modules.length;
    final cell = size.width / n;
    // A hair of overlap, so antialiasing does not leave white seams between
    // modules and make the code harder to read. It is a fraction of a cell
    // rather than a flat 0.4: the server sends 25 modules for a short payload
    // but 29 or 33 for a long one, and a flat bleed would dilate the larger
    // code half again as much — a QR that prints too heavy stops scanning.
    // At 25 modules this is 0.397, which is what it has always drawn.
    final bleed = cell * 0.16;
    final p = Paint()..color = const Color(0xFF111111);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < modules[r].length; c++) {
        if (modules[r][c]) {
          canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell + bleed, cell + bleed), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.modules != modules;
}
