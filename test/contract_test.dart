import 'package:flutter_test/flutter_test.dart';

import 'package:spd_frontend/core/api.dart';
import 'package:spd_frontend/data/repository.dart';

/// The contract between the repository and the running API.
///
/// Every model getter here reads a raw map with a fallback — `raw['part_no'] ??
/// ''`, `numOf(raw['grn_qty'])`. That is what keeps the console from throwing on
/// a partial response, and it is also what makes a renamed or dropped server
/// field completely silent: the cell renders empty, the quantity renders zero,
/// and nothing anywhere says why. No unit test catches it either, because every
/// fixture in the suite is written to match the getters.
///
/// So this signs in against the real server and asserts that the fields the
/// seeded shift guarantees are actually populated. A field that arrives under a
/// different name fails here rather than showing up as a blank column on the
/// floor.
///
/// Needs the API on :4100 with the demo seed. Skips itself when there is none,
/// so `flutter test` still runs anywhere.
void main() {
  late SpdRepository repo;
  String? skip;

  setUpAll(() async {
    final api = ApiClient(baseUrl: 'http://localhost:4100/api');
    repo = SpdRepository(api);
    try {
      final res = await repo.login(userId: 'sup.rmenon', password: 'vistar@2026');
      api.setToken(res.token);
    } catch (err) {
      skip = 'the SPD API is not reachable on :4100 — contract tests skipped ($err)';
    }
  });

  /// Runs [body] against the open shift, or skips when there is no server.
  ///
  /// markTestSkipped, not an early return: a test's own  argument is
  /// evaluated when the test is registered, which is before setUpAll has had a
  /// chance to discover whether the API is there. Returning quietly instead
  /// reported fifteen passes against no server at all — a green suite proving
  /// nothing, which is worse than a red one.
  void contract(String name, Future<void> Function(String shiftId) body) {
    test(name, () async {
      if (skip != null) {
        markTestSkipped(skip!);
        return;
      }
      final shifts = await repo.shifts();
      expect(shifts, isNotEmpty, reason: 'the seed should leave at least one shift');
      final open = shifts.firstWhere((s) => s.status == 'Open', orElse: () => shifts.first);
      await body(open.id);
    });
  }

  /* ---- the shift itself ------------------------------------------------ */

  contract('a shift arrives with its label, date and status', (shiftId) async {
    final shifts = await repo.shifts();
    for (final s in shifts) {
      expect(s.id, isNotEmpty);
      expect(s.label, isNotEmpty, reason: '${s.id} has no label — the picker would show a blank');
      expect(s.date, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
          reason: '${s.id} date is "${s.date}"; a Date here shifts the day east of UTC');
      expect(['Open', 'Finalised'], contains(s.status));
    }
  });

  /* ---- GRN lines: the table every screen is built on -------------------- */

  contract('a GRN line arrives with every column the lines table shows', (shiftId) async {
    final page = await repo.lines(shiftId: shiftId);
    expect(page.lines, isNotEmpty);

    for (final l in page.lines) {
      expect(l.id, isNotEmpty);
      expect(l.invoiceNo, isNotEmpty, reason: '${l.id} has no invoice number');
      expect(l.partNo, isNotEmpty, reason: '${l.id} has no part number');
      expect(l.partDesc, isNotEmpty, reason: '${l.id} has no description');
      expect(l.uom, isNotEmpty, reason: '${l.id} has no UOM');
      expect(l.vendor, isNotEmpty, reason: '${l.id} has no vendor');
      expect(l.grnDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')), reason: '${l.id} date');
      expect(l.grnQty, greaterThan(0), reason: '${l.id} has no GRN quantity');
      expect(l.status, isNotEmpty, reason: '${l.id} has no status');
      // BR-01 is derived on the server; if the field were renamed this would
      // read zero and every pending figure on every screen would be wrong.
      expect(l.pending, l.grnQty - l.packed, reason: '${l.id} BR-01');
      expect(l.labelCount, greaterThan(0), reason: '${l.id} would print no labels');
    }

    expect(page.invoices, isNotEmpty, reason: 'the invoice filter would be empty');
    expect(page.vendors, isNotEmpty, reason: 'the vendor filter would be empty');
  });

  contract('a split line carries its MOQ (FR-3.5)', (shiftId) async {
    final page = await repo.lines(shiftId: shiftId);
    final split = page.lines.where((l) => l.moq != null).toList();
    expect(split, isNotEmpty, reason: 'the seed should demonstrate the MOQ split');
    for (final l in split) {
      expect(l.moq, greaterThan(0));
      expect(l.labelCount, (l.grnQty / l.moq!).ceil(), reason: '${l.id} label count');
    }
  });

  /* ---- the drill-down -------------------------------------------------- */

  contract('a line detail carries its transactions, times and people', (shiftId) async {
    final page = await repo.lines(shiftId: shiftId);
    final withTxns = page.lines.firstWhere((l) => l.txns > 0);
    final detail = await repo.line(withTxns.id);

    expect(detail.txns, isNotEmpty);
    for (final t in detail.txns) {
      expect(t.id, isNotEmpty);
      expect(t.tableNo, isNotEmpty, reason: '${t.id} has no table');
      expect(t.memberName, isNotEmpty,
          reason: '${t.id} has no member name — the drill-down would show a blank column');
      expect(t.startAt, isNotNull, reason: '${t.id} has no start time (FR-6.2)');
      expect(['Started', 'Submitted', 'Exception'], contains(t.status));
      if (!t.running) {
        expect(t.submitAt, isNotNull, reason: '${t.id} is submitted with no submit time');
        expect(t.elapsed, isNotNull, reason: '${t.id} duration cannot be computed');
      }
    }
  });

  /* ---- the dashboard --------------------------------------------------- */

  contract('the dashboard carries its stats, tables and members', (shiftId) async {
    final d = await repo.dashboard(shiftId);

    expect(d.stats.grn, greaterThan(0), reason: 'total GRN quantity');
    expect(d.stats.packed, greaterThanOrEqualTo(0));
    expect(d.stats.pending, d.stats.grn - d.stats.packed, reason: 'BR-01 on the dashboard');
    expect(d.batchId, isNotEmpty, reason: 'the batch id tile would be blank');

    expect(d.tables, isNotEmpty);
    for (final t in d.tables) {
      expect(t.tableNo, isNotEmpty);
      expect(t.status, isNotEmpty, reason: '${t.tableNo} has no status');
    }

    expect(d.members, isNotEmpty);
    for (final m in d.members) {
      expect(m.name, isNotEmpty, reason: 'a member row with no name');
    }
  });

  /* ---- allocations, labels, review, reports ----------------------------- */

  contract('an allocation says who made it and when', (shiftId) async {
    final list = await repo.allocations(shiftId);
    expect(list, isNotEmpty);
    for (final a in list) {
      expect(a.id, isNotEmpty);
      expect(a.tableNo, isNotEmpty);
      expect(a.partNo, isNotEmpty, reason: '${a.id} has no part number');
      expect(a.invoiceNo, isNotEmpty, reason: '${a.id} has no invoice');
      expect(a.allocatedByName, isNotEmpty, reason: '${a.id} has no "by" name');
      expect(a.allocatedAt, isNotNull, reason: '${a.id} has no timestamp');
      expect(a.grnQty, greaterThan(0));
    }
  });

  contract('a label preview carries its codes and every printed field', (shiftId) async {
    final page = await repo.lines(shiftId: shiftId);
    final p = await repo.labelPreview(page.lines.first.id);

    expect(p.template, isNotEmpty);
    expect(p.labels, isNotEmpty, reason: 'a line that prints no labels at all');
    for (final u in p.labels) {
      expect(u.payload, isNotEmpty);
      expect(u.qty, greaterThan(0));
      expect(u.of, greaterThanOrEqualTo(u.index));
      // A square matrix; a flattened or transposed one would still render.
      expect(u.qr, isNotEmpty, reason: 'no QR modules');
      expect(u.qr.every((row) => row.length == u.qr.length), isTrue,
          reason: 'the QR is ${u.qr.length} rows of varying width');
    }
  });

  contract('the review page carries its exceptions with their detail', (shiftId) async {
    final r = await repo.review(shiftId);
    expect(r.exceptions, isNotEmpty, reason: 'the seed has a deliberate over-pack');
    for (final e in r.exceptions) {
      expect(e.id, isNotEmpty);
      expect(e.type, isNotEmpty);
      expect(e.detail, isNotEmpty, reason: '${e.id} has no detail — the row would be blank');
      expect(e.partNo, isNotEmpty, reason: '${e.id} has no part number');
    }
  });

  contract('the MIS carries rows for every dimension (FR-10.2)', (shiftId) async {
    for (final dim in ['line', 'inv', 'table', 'member']) {
      final m = await repo.mis(shiftId: shiftId, dim: dim);
      expect(m.rows, isNotEmpty, reason: 'the $dim-wise MIS is empty');
      for (final row in m.rows) {
        expect(row.label, isNotEmpty, reason: 'a $dim row with no label');
      }
    }
  });

  contract('the audit trail carries actor, action and time (NFR-3.3)', (shiftId) async {
    final a = await repo.audit();
    expect(a.entries, isNotEmpty);
    for (final e in a.entries) {
      expect(e.action, isNotEmpty);
      expect(e.at, isNotNull, reason: 'an audit entry with no timestamp');
    }
    expect(a.actions, isNotEmpty, reason: 'the action filter would be empty');
  });

  contract('the config carries every FR-13.2 setting', (shiftId) async {
    final c = await repo.config();
    expect(c.threshold, greaterThan(0));
    expect(c.hourly, greaterThan(0));
    expect(c.refresh, greaterThan(0));
    expect(c.labelTpl, isNotEmpty);
    expect(c.emails, isNotEmpty);
    expect(c.grnCols.length, greaterThanOrEqualTo(3));
    expect(c.grnColsOptional, contains('MOQ'), reason: 'FR-3.5 reads MOQ from this list');
  });

  contract('the import history carries file, uploader and counts (FR-1.6)', (shiftId) async {
    final list = await repo.grnBatches();
    expect(list, isNotEmpty);
    for (final b in list) {
      expect(b.id, isNotEmpty);
      expect(b.fileName, isNotEmpty, reason: '${b.id} has no file name');
      expect(b.shiftLabel, isNotEmpty, reason: '${b.id} has no shift label');
      expect(b.uploadedByName, isNotEmpty, reason: '${b.id} has no uploader');
      expect(b.uploadedAt, isNotNull);
      expect(b.rowCount, greaterThan(0));
    }
  });

  contract('the user roster carries names, codes and roles (FR-13.1)', (shiftId) async {
    final users = await repo.users();
    expect(users, isNotEmpty);
    for (final u in users) {
      expect(u.id, isNotEmpty);
      expect(u.name, isNotEmpty, reason: '${u.id} has no name');
      expect(u.empCode, isNotEmpty, reason: '${u.id} has no employee code');
      expect(['Supervisor', 'Member', 'Administrator', 'Management'], contains(u.role));
    }
  });

  contract('the hourly reports carry their figures (FR-8.3)', (shiftId) async {
    final h = await repo.hourly(shiftId);
    expect(h.reports, isNotEmpty, reason: 'the seed writes hourly reports');
    for (final r in h.reports) {
      expect(r.id, isNotEmpty);
      expect(r.generatedAt, isNotNull, reason: '${r.id} has no generated time');
      // The email subject is built from this. A missing field does not show up
      // as a blank column here — it shows up as a gap inside a sentence:
      // "Hourly Status ·  · 10:58". The list query did not join it, though the
      // detail query always had.
      expect(r.shiftLabel, isNotEmpty,
          reason: '${r.id} has no shift label — the email subject would read '
              '"Hourly Status ·  · <time>"');
    }
  });

  contract('the MIS snapshots carry the shift they summarise', (shiftId) async {
    final m = await repo.mis(shiftId: shiftId);
    for (final s in m.snapshots) {
      expect(s.id, isNotEmpty);
      expect(s.shiftLabel, isNotEmpty, reason: '${s.id} has no shift label');
      expect(s.generatedAt, isNotNull);
    }
  });

  contract('the facets feed every filter dropdown', (shiftId) async {
    final f = await repo.facets(shiftId);
    expect(f.invoices, isNotEmpty, reason: 'the invoice filter would be empty');
    expect(f.tables, isNotEmpty, reason: 'the table filter would be empty');
  });
}
