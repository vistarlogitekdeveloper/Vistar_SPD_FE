import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../core/downloads.dart';
import '../../core/theme.dart';
import 'common.dart';

/// FR-3.2 — the label stock every SPD sheet is laid out on.
///
/// 100 × 25 mm, two 50 × 25 mm stickers to a row, with no margin: the same
/// geometry services/labels.js builds the pages at (PAGE = [STICKER_W * 2,
/// STICKER_H], 141.73 × 70.87 pt). The two must agree — a preview told one
/// paper size and handed bytes of another is exactly the mismatch below.
const PdfPageFormat kLabelStock =
    PdfPageFormat(141.73 * 2, 70.87, marginAll: 0);

/// FR-3.2 — shows a generated PDF **in the app** before it reaches a printer.
///
/// Handing the bytes straight to `Printing.layoutPdf` leaves the preview to the
/// operating system, and the Windows print dialog answers "This app doesn't
/// support print preview" — so a Supervisor would be committing label stock to
/// a sheet they have not seen. This renders the pages first, and only then
/// offers the printer.
///
/// Returns true if the sheet was sent to a printer.
///
/// [pageFormat] is the stock the PDF is already laid out on. It is not a
/// choice offered to the user — it is what the bytes are — and giving it is
/// the whole of why the print dialog now defaults sensibly. See kLabelStock.
Future<bool> showPdfPreviewDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String fileName,
  required Uint8List bytes,
  PdfPageFormat pageFormat = kLabelStock,
  String formatLabel = '100 × 25 mm label',
}) async {
  var printed = false;

  await showDialog<void>(
    context: context,
    barrierColor: Brand.isLight ? const Color(0x4D28164E) : const Color(0xA804030A),
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 880,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: Brand.isLight
                  ? [const Color(0xFFFFFFFF), const Color(0xFFF8F5FE)]
                  : [const Color(0xFF16142A), const Color(0xFF110F1E)],
            ),
            border: Border.all(color: Brand.line2),
            borderRadius: BorderRadius.circular(Brand.rLg),
            boxShadow: Brand.shadow,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: display(size: 19)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: body(size: 12.5, color: Brand.txt3)),
                  ]),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Material(
                    color: Brand.field,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: Brand.fieldLine),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.close_rounded, size: 16, color: Brand.txt3),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            Flexible(
              child: Container(
                margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Brand.isLight ? const Color(0xFFE9E5F3) : const Color(0xFF0A0917),
                  border: Border.all(color: Brand.line),
                  borderRadius: BorderRadius.circular(Brand.r),
                ),
                child: PdfPreview(
                  // The bytes are already built; the format below does not
                  // re-lay them out, it declares what they are.
                  build: (_) => bytes,
                  pdfFileName: fileName,
                  /* The paper the sheet is actually on.

                     PdfPreview falls back to A4 when it is told nothing, and
                     it was told nothing — so a 100 × 25 mm label sheet was
                     previewed, and handed to the operating system’s print
                     dialog, as A4. That is why nothing defaulted sensibly:
                     every orientation and fit-to-page guess the dialog made
                     was a guess about the wrong paper, and a label printer
                     fed an A4 job scales the artwork to a size no stock
                     matches. Landscape and "fit" now follow from the real
                     dimensions instead of being asked for by hand.

                     Pinned rather than offered: pageFormats holds exactly one
                     entry, so there is nothing for the format picker to change
                     the sheet to. */
                  initialPageFormat: pageFormat,
                  pageFormats: {formatLabel: pageFormat},
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  allowSharing: false,
                  allowPrinting: true,
                  dynamicLayout: false,
                  maxPageWidth: 560,
                  loadingWidget: const SpdLoader(size: 48, label: 'Rendering the sheet…'),
                  scrollViewDecoration: BoxDecoration(color: Colors.transparent),
                  pdfPreviewPageDecoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Color(0x66000000), blurRadius: 24, spreadRadius: -10, offset: Offset(0, 8)),
                    ],
                  ),
                  actionBarTheme: PdfActionBarTheme(
                    backgroundColor: Brand.surface2,
                    iconColor: Brand.txt2,
                    elevation: 0,
                    textStyle: body(size: 13, color: Brand.txt2),
                  ),
                  actions: [
                    // The OS print dialog is still what talks to the label
                    // printer; the preview just makes sure nobody reaches it
                    // without having looked at the sheet first. Saving a copy
                    // belongs next to printing rather than back on the page.
                    PdfPreviewAction(
                      icon: Icon(Icons.download_rounded, color: Brand.txt2),
                      onPressed: (context, build, format) async {
                        await saveBytes(filename: fileName, bytes: bytes, mime: 'application/pdf');
                        if (context.mounted) {
                          Toast.ok(context, 'Saved', '$fileName is in your downloads.');
                        }
                      },
                    ),
                  ],
                  onPrinted: (_) => printed = true,
                  onPrintError: (context, error) =>
                      Toast.bad(context, 'Could not print', '$error'),
                ),
              ),
            ),
          ]),
        ),
      ),
    ),
  );

  return printed;
}
