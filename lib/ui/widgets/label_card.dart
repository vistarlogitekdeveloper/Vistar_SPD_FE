import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';

/// `.plabel` — the ID label as it prints (FR-3.1): part number, description,
/// invoice, GRN quantity, GRN date, a scannable QR and a Code 128 barcode.
///
/// The QR modules and the barcode bar widths come from the server, which is the
/// same code that draws the PDF — so what a supervisor approves on screen is
/// what the printer produces, rather than two implementations that agree today.
class LabelCard extends StatelessWidget {
  const LabelCard({super.key, required this.preview, this.width = 330});

  final LabelPreview preview;
  final double width;

  @override
  Widget build(BuildContext context) {
    final l = preview.line;
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
                  Row(children: [
                    _Field('INVOICE', l.invoiceNo),
                    const SizedBox(width: 10),
                    _Field('GRN QTY', '${nf(l.grnQty)} ${l.uom}'),
                    const SizedBox(width: 10),
                    _Field('GRN DATE', fmtD(l.grnDate)),
                  ]),
                ]),
              ),
              const SizedBox(width: 10),
              _Qr(modules: preview.qr, size: 62),
            ]),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Text(l.vendor,
                    style: body(size: 11, color: const Color(0xFF555555)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Text('SPD PRE-PACK', style: body(size: 11, color: const Color(0xFF555555))),
            ]),
            const SizedBox(height: 6),
            SizedBox(height: 26, child: _Barcode(widths: preview.barcode)),
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
          Text(caption, style: body(size: 9.5, color: const Color(0xFF333333))),
          Text(value, style: body(size: 11, weight: FontWeight.w700, color: const Color(0xFF111111))),
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
    final p = Paint()..color = const Color(0xFF111111);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < modules[r].length; c++) {
        if (modules[r][c]) {
          // A hair of overlap, so antialiasing does not leave white seams
          // between modules and make the code harder to read.
          canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell + 0.4, cell + 0.4), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.modules != modules;
}

class _Barcode extends StatelessWidget {
  const _Barcode({required this.widths});

  final List<int> widths;

  @override
  Widget build(BuildContext context) =>
      SizedBox.expand(child: CustomPaint(painter: _BarcodePainter(widths)));
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.widths);

  final List<int> widths;

  @override
  void paint(Canvas canvas, Size size) {
    if (widths.isEmpty) return;
    final total = widths.fold<int>(0, (s, w) => s + w);
    final unit = size.width / total;
    final p = Paint()..color = const Color(0xFF111111);
    var x = 0.0;
    for (var i = 0; i < widths.length; i++) {
      final w = widths[i] * unit;
      // Code 128 alternates bar, space, bar, space… starting with a bar.
      if (i.isEven) canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), p);
      x += w;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => old.widths != widths;
}
