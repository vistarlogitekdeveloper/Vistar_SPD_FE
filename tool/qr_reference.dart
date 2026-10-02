// One-off: emit known-good QR matrices from the `qr` package so the backend's
// hand-written encoder can be checked against an independent implementation.
//
// One matrix per version the backend can emit, each carrying a payload of the
// shape and size that pushes the encoder to that version: a plain part number
// for 2, a longer one for 3, and the 40-character maximum PART_RE allows for 4.
// The encoder stops at 4 because the label draws the code 56pt square and a
// denser one stops printing reliably, not because 5 and 6 are hard to emit.
//
//   dart run tool/qr_reference.dart
//
// Paste the output into the REFERENCES table in backend/test/labels.test.js.
// The `qr` package picks its own mask, so these matrices are not expected to
// match ours module for module — the test compares the codewords underneath.
import 'package:qr/qr.dart';

const cases = <int, String>{
  2: '90210-ABX|INV-77001|270',
  3: '90210-ABX-BRACKET-FRONT-LH|INV-77001|270',
  4: '90210-ABX-BRACKET-FRONT-LH-REV12-A/B.012|INV-77001|270',
};

void main() {
  for (final entry in cases.entries) {
    final code = QrCode(entry.key, QrErrorCorrectLevel.M)..addData(entry.value);
    final image = QrImage(code);
    print('VERSION=${entry.key}');
    print('PAYLOAD=${entry.value}');
    print('BYTES=${entry.value.length}');
    print('SIZE=${code.moduleCount}');
    for (var r = 0; r < code.moduleCount; r++) {
      var s = '';
      for (var c = 0; c < code.moduleCount; c++) {
        s += image.isDark(r, c) ? '1' : '0';
      }
      print(s);
    }
    print('');
  }
}
