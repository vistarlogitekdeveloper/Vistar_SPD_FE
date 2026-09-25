import 'package:intl/intl.dart';

/// Formatters transcribed from the prototype's helpers, so a quantity that read
/// `2,480` there reads `2,480` here rather than `2.48K` or `2480`.

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// `nf()` — Indian digit grouping, which is what the floor and the MIS use.
final _nf = NumberFormat.decimalPattern('en_IN');

String nf(dynamic v) {
  if (v == null) return '—';
  final n = v is num ? v : num.tryParse('$v');
  if (n == null) return '$v';
  return n == n.roundToDouble() ? _nf.format(n.round()) : _nf.format(n);
}

/// A DATE from the API is a plain `YYYY-MM-DD` string with no zone. Parsing it
/// as a `DateTime` and formatting in local time would shift it by a day for
/// anyone west of UTC, so the parts are read straight out of the string.
String fmtD(dynamic v) {
  if (v == null) return '—';
  final s = '$v';
  final plain = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (plain != null) {
    return '${plain.group(3)}-${_months[int.parse(plain.group(2)!) - 1]}-${plain.group(1)}';
  }
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  final l = d.toLocal();
  return '${_two(l.day)}-${_months[l.month - 1]}-${l.year}';
}

/// `fmtT()` — HH:mm. A timestamp from the API is a real instant, so it *is*
/// converted to the viewer's local time.
String fmtT(dynamic v) {
  final d = _ts(v);
  return d == null ? '—' : '${_two(d.hour)}:${_two(d.minute)}';
}

/// `fmtTs()` — HH:mm:ss.
String fmtTs(dynamic v) {
  final d = _ts(v);
  return d == null ? '—' : '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

String fmtDateTime(dynamic v) {
  final d = _ts(v);
  return d == null ? '—' : '${fmtD(d.toIso8601String())} ${fmtTs(v)}';
}

/// `durTxt()` — "38m" / "1h 12m".
String durTxt(Duration? d) {
  if (d == null) return '—';
  final m = d.inMinutes;
  return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
}

/// Elapsed between two API timestamps, or null if either is missing.
Duration? between(dynamic startIso, dynamic endIso) {
  final a = _ts(startIso);
  final b = _ts(endIso);
  if (a == null || b == null) return null;
  return b.difference(a);
}

/// `pct()` — integer percentage, zero-safe.
int pct(num a, num b) => b == 0 ? 0 : (a / b * 100).round();

/// `initials()` — up to two initials for the avatar.
String initials(String? name) {
  final parts = (name ?? '').split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
  if (parts.isEmpty) return '—';
  return parts.map((p) => p[0]).join().toUpperCase();
}

/// mm:ss for the running packing timer.
String clockMs(Duration d) => '${_two(d.inMinutes)}:${_two(d.inSeconds % 60)}';

DateTime? _ts(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  final d = DateTime.tryParse('$v');
  return d?.toLocal();
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Coerces an API number that may arrive as int, double or string.
num numOf(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  return num.tryParse('$v') ?? 0;
}

int intOf(dynamic v) => numOf(v).round();
