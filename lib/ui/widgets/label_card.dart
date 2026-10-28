import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';

/// `.plabel` — one ID sticker as it prints (FR-3.1): 50 × 25 mm, two to a
/// 100 × 25 mm row. Part number across the top; description, the quantity in
/// this pouch, the invoice, the packer and the date it is printed down the
/// left; the QR on the right.
///
/// Laid out from the same points as services/labels.js on the server, scaled
/// to [width], and the QR modules come from that same code — so what a
/// supervisor approves on screen is what the printer produces.
class LabelCard extends StatelessWidget {
  const LabelCard({super.key, required this.preview, this.unit, this.width = 330});

  final LabelPreview preview;

  /// FR-3.5 — which of the line's labels to draw. Defaults to the first, which
  /// is the only one for a line without an MOQ.
  final LabelUnit? unit;

  final double width;

  // The sticker and its parts in PDF points, as labels.js draws them.
  static const _w = 141.73;
  static const _h = 70.87;
  static const _qr = 42.0;
  static const _quiet = 4 * _qr / 25;
  static const _m = 6.0;

  @override
  Widget build(BuildContext context) {
    final l = preview.line;
    final u = unit ?? (preview.labels.isEmpty ? null : preview.first);
    final s = width / _w;
    final qrLeft = _w - _quiet - _qr;
    final band = qrLeft - _quiet - _m;

    TextStyle ink(double size) =>
        body(size: size * s, weight: FontWeight.w800, color: Colors.black, height: 1);

    Widget at(double top, double w, Widget child) =>
        Positioned(left: _m * s, top: top * s, width: w * s, child: child);

    Widget line(String text, double size) =>
        Text(text, style: ink(size), maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false);

    return Container(
      width: width,
      height: _h * s,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Color(0x99000000), blurRadius: 30, spreadRadius: -14, offset: Offset(0, 10)),
        ],
      ),
      child: Stack(children: [
        // A part number gives up size before characters, as on paper.
        at(4, _w - 2 * _m, FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(l.partNo, style: ink(10.5), maxLines: 1, softWrap: false),
        )),
        // The left column, at labels.js's ROWS.
        at(18, band, line(l.partDesc, 7.5)),
        // The POUCH quantity — what is in this bag, not what the receipt carried.
        at(28, band, line('${nf(u?.qty ?? l.grnQty)} ${l.uom}'.trim(), 8.5)),
        at(39, band, line(l.invoiceNo.isEmpty ? '—' : 'INV ${l.invoiceNo}', 7)),
        // Whoever staffs the tables the line is allocated to; a dash until then.
        at(48.5, band, line(l.packer ?? '—', 7)),
        // The day Print is pressed — the server stamps the sheet with the same.
        at(58, band, line(fmtLabelDate(preview.printedOn ?? DateTime.now().toIso8601String()), 7.5)),
        Positioned(
          left: qrLeft * s,
          top: (_h - _quiet - _qr) * s,
          child: _Qr(modules: u?.qr ?? const [], size: _qr * s),
        ),
      ]),
    );
  }
}

/// 28-Oct-26, as labels.js prints it.
String fmtLabelDate(String v) {
  final d = DateTime.tryParse(v);
  if (d == null) return v;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day.toString().padLeft(2, '0')}-${months[d.month - 1]}-${(d.year % 100).toString().padLeft(2, '0')}';
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
