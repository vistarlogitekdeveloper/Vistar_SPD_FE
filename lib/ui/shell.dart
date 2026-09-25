import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/providers.dart';
import '../models/models.dart';
import 'widgets/common.dart';

/// One sidebar entry.
class NavItem {
  const NavItem(this.route, this.title, this.icon);

  final String route, title;
  final IconData icon;
}

class NavGroup {
  const NavGroup(this.title, this.items);

  final String title;
  final List<NavItem> items;
}

/// `NAV` — the same groups and order as the prototype, per role.
const navByRole = <String, List<NavGroup>>{
  'supervisor': [
    NavGroup('Overview', [NavItem('/dashboard', 'Live Dashboard', Icons.grid_view_rounded)]),
    NavGroup('GRN', [
      NavItem('/grn', 'GRN Upload', Icons.upload_rounded),
      NavItem('/lines', 'Invoice / Part Lines', Icons.format_list_bulleted_rounded),
      NavItem('/labels', 'ID Labels', Icons.sell_outlined),
    ]),
    NavGroup('Floor', [
      NavItem('/allocation', 'Table Allocation', Icons.table_chart_outlined),
      NavItem('/review', 'Review & Finalise', Icons.visibility_outlined),
      NavItem('/hourly', 'Hourly Reports', Icons.mail_outline_rounded),
    ]),
    NavGroup('Reports', [
      NavItem('/mis', 'MIS Report', Icons.show_chart_rounded),
      NavItem('/audit', 'Audit Trail', Icons.shield_outlined),
    ]),
  ],
  'member': [
    NavGroup('My Table', [
      NavItem('/my/work', 'My Work Queue', Icons.grid_view_rounded),
      NavItem('/my/pack', 'Pack', Icons.play_arrow_rounded),
      NavItem('/my/history', 'My Submissions', Icons.format_list_bulleted_rounded),
    ]),
  ],
  'admin': [
    NavGroup('Administration', [
      NavItem('/admin/users', 'Users & Roles', Icons.group_outlined),
      NavItem('/admin/config', 'Masters & Config', Icons.tune_rounded),
      NavItem('/audit', 'Audit Trail', Icons.shield_outlined),
    ]),
  ],
  'viewer': [
    NavGroup('Management View', [
      NavItem('/dashboard', 'Live Dashboard', Icons.grid_view_rounded),
      NavItem('/mis', 'MIS Report', Icons.show_chart_rounded),
    ]),
  ],
};

/// `#app` — the sidebar/topbar/canvas frame every screen sits inside.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _search = TextEditingController();
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width <= 980;
    final role = ref.watch(viewRoleProvider);

    return Scaffold(
      key: _scaffold,
      backgroundColor: Colors.transparent,
      drawer: narrow ? Drawer(width: 262, backgroundColor: Colors.transparent, child: _Sidebar(role: role)) : null,
      body: SafeArea(
        child: Row(children: [
          if (!narrow) SizedBox(width: 248, child: _Sidebar(role: role)),
          Expanded(
            child: Column(children: [
              _TopBar(
                search: _search,
                onMenu: narrow ? () => _scaffold.currentState?.openDrawer() : null,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(narrow ? 15 : 26, narrow ? 18 : 26, narrow ? 15 : 26, 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1420),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// `#side` — brand row, grouped nav with live counts, signed-in footer.
class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.role});

  final String role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = navByRole[role] ?? const <NavGroup>[];
    final location = GoRouterState.of(context).matchedLocation;
    final counts = _counts(ref, role);
    final user = ref.watch(sessionProvider).user;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: Brand.sideFill,
        border: Border(right: BorderSide(color: Brand.line)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // .brandrow
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Brand.line))),
          child: Row(children: [
            const SMark(width: 34, height: 36),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Vistar SPD', style: display(size: 17, height: 1.1)),
                Text('PRE-PACKING AUTOMATION', style: eyebrow(size: 10, tracking: 1.2)),
              ]),
            ),
          ]),
        ),
        // #nav
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            children: [
              for (final g in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
                  child: Text(g.title.toUpperCase(), style: eyebrow(size: 10, tracking: 1.1)),
                ),
                for (final item in g.items)
                  _NavRow(
                    item: item,
                    selected: location == item.route,
                    count: counts[item.route],
                    onTap: () {
                      if (MediaQuery.sizeOf(context).width <= 980) Navigator.of(context).maybePop();
                      context.go(item.route);
                    },
                  ),
              ],
            ],
          ),
        ),
        // .sidefoot
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
          child: Row(children: [
            Avatar(user?.name ?? '—'),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.name ?? '—',
                    style: body(size: 12.8, weight: FontWeight.w700, height: 1.25),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  role == 'member'
                      ? 'Table Member · ${ref.watch(previewTableProvider)}'
                      : '${user?.role ?? ''} · ${user?.empCode ?? ''}',
                  style: body(size: 10.5, weight: FontWeight.w600, color: Brand.txt3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            IconButton(
              tooltip: 'Sign out',
              iconSize: 16,
              color: Brand.txt3,
              icon: const Icon(Icons.logout_rounded),
              onPressed: () async {
                await ref.read(sessionProvider.notifier).signOut();
                if (context.mounted) context.go('/login');
              },
            ),
          ]),
        ),
      ]),
    );
  }

  /// The badges beside nav entries — open exceptions, line count, report count.
  Map<String, int> _counts(WidgetRef ref, String role) {
    final out = <String, int>{};
    if (role == 'supervisor') {
      final dash = ref.watch(dashboardProvider).value;
      if (dash != null) {
        if (dash.stats.excOpen > 0) out['/review'] = dash.stats.excOpen;
        if (dash.stats.lines > 0) out['/lines'] = dash.stats.lines;
        if (dash.hourlyCount > 0) out['/hourly'] = dash.hourlyCount;
      }
    } else if (role == 'member') {
      final q = ref.watch(myQueueProvider).value;
      if (q != null) {
        final open = q.openLines.length;
        if (open > 0) out['/my/work'] = open;
      }
      final h = ref.watch(myHistoryProvider).value;
      if (h != null && h.isNotEmpty) out['/my/history'] = h.length;
    }
    return out;
  }
}

/// `.nav` — one sidebar row, with the ribbon tab when selected.
class _NavRow extends StatefulWidget {
  const _NavRow({required this.item, required this.selected, required this.onTap, this.count});

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          child: Stack(clipBehavior: Clip.none, children: [
            // .nav.on::before — the ribbon tab that bleeds off the left edge
            if (on)
              Positioned(
                left: -12,
                top: 7,
                bottom: 7,
                width: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: Brand.ribbon,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              decoration: BoxDecoration(
                gradient: on ? Brand.navOnFill : null,
                color: !on && _hover ? Brand.surface2 : null,
                border: Border.all(color: on ? Brand.pink.withValues(alpha: 0.16) : Colors.transparent),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(children: [
                Opacity(
                  opacity: 0.85,
                  child: Icon(widget.item.icon, size: 16, color: on ? Brand.txt : Brand.txt2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.item.title,
                    style: body(
                      size: 13.2,
                      weight: on ? FontWeight.w700 : FontWeight.w600,
                      color: on ? Brand.txt : (_hover ? Brand.txt : Brand.txt2),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.count != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: on
                          ? Brand.pink.withValues(alpha: Brand.isLight ? 0.16 : 0.24)
                          : Brand.txt3.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: body(
                        size: 10.5,
                        weight: FontWeight.w800,
                        color: on
                            ? (Brand.isLight ? const Color(0xFFB0136A) : const Color(0xFFFBC7E2))
                            : Brand.txt2,
                      ),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// `#top` — search, shift picker, the live pill, theme, "View as", bell, avatar.
class _TopBar extends ConsumerWidget {
  const _TopBar({required this.search, this.onMenu});

  final TextEditingController search;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final narrow = MediaQuery.sizeOf(context).width <= 980;
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    final selected = ref.watch(selectedShiftProvider);
    final live = ref.watch(liveProvider);
    final user = ref.watch(sessionProvider).user;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Brand.topFill,
        border: Border(bottom: BorderSide(color: Brand.line)),
      ),
      child: Row(children: [
        if (onMenu != null) ...[
          IconTile(icon: Icons.menu_rounded, onTap: onMenu),
          const SizedBox(width: 12),
        ],
        if (!narrow) ...[
          SizedBox(
            width: 330,
            child: TextField(
              controller: search,
              style: body(size: 13),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search invoice, part…',
                prefixIcon: Icon(Icons.search_rounded, size: 17, color: Brand.txt3),
                prefixIconConstraints: const BoxConstraints(minWidth: 36),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide(color: Brand.fieldLine),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide(color: Brand.pink.withValues(alpha: 0.5)),
                ),
              ),
              onSubmitted: (q) => _showSearch(context, ref, q),
            ),
          ),
          const Spacer(),
        ] else
          const Spacer(),

        // .exercise-pick — the shift picker
        // The shift scopes every screen, so it stays reachable on a table
        // tablet even when the search box and the "View as" preview fold away.
        if (shifts.isNotEmpty)
          _TopPicker(
            label: 'Shift',
            flexible: true,
            child: DropdownButton<String>(
              value: selected,
              underline: const SizedBox.shrink(),
              isDense: true,
              isExpanded: true,
              dropdownColor: Brand.surface2,
              borderRadius: BorderRadius.circular(13),
              icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Brand.txt3),
              style: body(size: 12.5, weight: FontWeight.w700),
              // The closed control gets a single ellipsized line; the open menu
              // keeps the full label. Without this the selected shift wraps to
              // two lines inside the 64px top bar and the second one is cut off.
              selectedItemBuilder: (context) => [
                for (final s in shifts)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      s.pickerLabel,
                      style: body(size: 12.5, weight: FontWeight.w700),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              items: [
                for (final s in shifts)
                  DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      s.pickerLabel,
                      style: body(size: 12.5, weight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                ref.read(shiftIdProvider.notifier).set(v);
                invalidateAll(ref);
              },
            ),
          ),
        const SizedBox(width: 10),

        // .netpill — FR-11.4 auto-refresh, on a toggle
        _LivePill(
          live: live,
          onTap: () {
            final seconds = ref.read(dashboardProvider).value?.refreshSeconds ?? 60;
            ref.read(liveProvider.notifier).toggle(seconds);
            if (!live) {
              Toast.ok(context, 'Live refresh on',
                  'The console now reloads every ${seconds}s — the dashboard, allocation board and review screen update as the floor submits.');
            }
          },
        ),
        const SizedBox(width: 10),

        IconTile(
          icon: Brand.isLight ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
          tooltip: 'Switch light / dark theme',
          onTap: () => ref.read(themeLightProvider.notifier).toggle(),
        ),
        const SizedBox(width: 10),

        // "View as" — an Administrator previews another role's screens.
        if (!narrow && user?.role == 'Administrator') ...[
          _TopPicker(
            label: 'View as',
            child: DropdownButton<String>(
              value: ref.watch(viewRoleProvider),
              underline: const SizedBox.shrink(),
              isDense: true,
              dropdownColor: Brand.surface2,
              borderRadius: BorderRadius.circular(13),
              icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Brand.txt3),
              style: body(size: 12.5, weight: FontWeight.w700),
              items: const [
                DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
                DropdownMenuItem(value: 'member', child: Text('Table Member')),
                DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                DropdownMenuItem(value: 'viewer', child: Text('Management')),
              ],
              onChanged: (v) {
                if (v == null) return;
                ref.read(viewRoleProvider.notifier).set(v);
                context.go(homeFor(v));
              },
            ),
          ),
          const SizedBox(width: 10),
        ],

        IconTile(
          icon: Icons.notifications_none_rounded,
          dot: true,
          tooltip: 'Notifications',
          onTap: () => _showNotifications(context, ref),
        ),
        const SizedBox(width: 12),
        Avatar(user?.name ?? '—'),
      ]),
    );
  }

  Future<void> _showSearch(BuildContext context, WidgetRef ref, String q) async {
    if (q.trim().isEmpty) return;
    final shiftId = ref.read(selectedShiftProvider);
    if (shiftId == null) return;
    final results = await ref.read(repositoryProvider).search(shiftId: shiftId, q: q);
    if (!context.mounted) return;
    await showSpdModal<void>(
      context,
      title: 'Search · “$q”',
      subtitle: '${results.length} match${results.length == 1 ? '' : 'es'} in this shift',
      wide: true,
      content: (context, setModalState) => SpdTable(
        columns: const [
          SpdCol('Invoice'),
          SpdCol('Part'),
          SpdCol('Description', width: 220),
          SpdCol('GRN Qty', right: true),
          SpdCol('Pending', right: true),
          SpdCol('Status'),
        ],
        rows: [
          for (final l in results)
            SpdRow([
              monoCell(l.invoiceNo),
              strongCell(l.partNo),
              cell(l.partDesc),
              monoCell('${nf(l.grnQty)} ${l.uom}'),
              monoCell(nf(l.pending)),
              StatusPill(l.status),
            ]),
        ],
        emptyMessage: 'Nothing matched “$q”.',
      ),
      actions: (context, _) => [GhostButton(label: 'Close', onPressed: () => Navigator.pop(context))],
    );
  }

  Future<void> _showNotifications(BuildContext context, WidgetRef ref) async {
    final shiftId = ref.read(selectedShiftProvider);
    if (shiftId == null) return;
    final notes = await ref.read(repositoryProvider).notifications(shiftId);
    final shift = ref.read(currentShiftProvider);
    if (!context.mounted) return;
    await showSpdModal<void>(
      context,
      title: 'Notifications',
      subtitle: shift?.label,
      content: (context, setModalState) => Column(children: [
        for (final n in notes)
          ListRow(children: [
            Pill(
              switch ('${n['severity']}') { 'bad' => 'Action', 'warn' => 'Watch', _ => 'Info' },
              tone: switch ('${n['severity']}') {
                'bad' => PillTone.bad,
                'warn' => PillTone.amber,
                _ => PillTone.info,
              },
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('${n['text']}', style: body(size: 13))),
          ]),
      ]),
      actions: (context, _) => [GhostButton(label: 'Close', onPressed: () => Navigator.pop(context))],
    );
  }
}

/// `.exercise-pick` — the bordered label+control group in the top bar.
class _TopPicker extends StatelessWidget {
  const _TopPicker({required this.label, required this.child, this.flexible = false});

  final String label;
  final Widget child;

  /// Lets the control give up width on a narrow top bar rather than overflow.
  final bool flexible;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      constraints: flexible ? const BoxConstraints(maxWidth: 260) : null,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Brand.field,
        border: Border.all(color: Brand.fieldLine),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label.toUpperCase(), style: eyebrow(size: 10, tracking: 0.8)),
        const SizedBox(width: 8),
        flexible ? Flexible(child: child) : child,
      ]),
    );
    return flexible ? Flexible(child: box) : box;
  }
}

/// `.netpill` — the "Floor live" toggle.
class _LivePill extends StatelessWidget {
  const _LivePill({required this.live, required this.onTap});

  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = live ? Brand.ok : Brand.warn;
    return Tooltip(
      message: live
          ? 'The console reloads on a timer — the floor updates as tables submit'
          : 'Auto-refresh paused — the figures stay still while you read them',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: live ? Brand.surface : Brand.amber.withValues(alpha: 0.08),
            border: Border.all(color: live ? Brand.fieldLine : Brand.amber.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: colour,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: colour, blurRadius: 8)],
              ),
            ),
            const SizedBox(width: 7),
            Text(live ? 'Floor live' : 'Floor paused',
                style: body(size: 12, weight: FontWeight.w700, color: colour)),
          ]),
        ),
      ),
    );
  }
}
