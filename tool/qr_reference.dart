// One-off: emit a known-good QR matrix from the `qr` package so the backend's
// hand-written encoder can be checked against an independent implementation.
import 'package:qr/qr.dart';

void main() {
  const payload = '90210-ABX|INV-77001|270';
  final code = QrCode(2, QrErrorCorrectLevel.M)..addData(payload);
  final image = QrImage(code);
  final rows = <String>[];
  for (var r = 0; r < code.moduleCount; r++) {
    var s = '';
    for (var c = 0; c < code.moduleCount; c++) {
      s += image.isDark(r, c) ? '1' : '0';
    }
    rows.add(s);
  }
  print('PAYLOAD=$payload');
  print('SIZE=${code.moduleCount}');
  print(rows.join('\n'));
}
