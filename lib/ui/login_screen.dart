import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../core/theme.dart';
import '../data/providers.dart';
import 'widgets/common.dart';

/// `#login` — the two-panel sign-in: brand art on the left, the form on the
/// right, collapsing to the form alone below 980px.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _roles = [
    ('supervisor', 'Supervisor', 'GRN, labels, review, MIS', 'sup.rmenon'),
    ('member', 'Table Member', 'Start & submit packing', null),
    ('admin', 'Administrator', 'Users, tables, config', 'adm.itcell'),
    ('viewer', 'Management', 'Dashboard & MIS', 'mgt.avohra'),
  ];

  final _user = TextEditingController(text: 'sup.rmenon');
  final _pass = TextEditingController(text: 'vistar@2026');
  String _role = 'supervisor';
  String? _memberId;
  List<Map<String, dynamic>> _members = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  /// FR-5.1 — the member picker is filled before anyone signs in, so a shop-floor
  /// operator selects their name instead of typing a login ID.
  Future<void> _loadMembers() async {
    try {
      final list = await ref.read(repositoryProvider).members();
      if (!mounted) return;
      setState(() {
        _members = list;
        _memberId = list.isEmpty ? null : '${list.first['id']}';
      });
    } catch (_) {
      // The roster is a convenience; a member can still type their ID.
    }
  }

  Future<void> _signIn() async {
    final isMember = _role == 'member';
    final id = isMember ? (_memberId ?? _user.text.trim()) : _user.text.trim();
    if (id.isEmpty) {
      setState(() => _error = 'Enter your user ID, or select your name from the list');
      return;
    }
    if (_pass.text.isEmpty) {
      setState(() => _error = isMember ? 'Enter your PIN to continue' : 'Enter your password to continue');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    // A Member's credential may be a PIN or a password, and the shop floor uses
    // whichever it was given — so the shorter, all-digit entry is offered as a
    // PIN and anything else as a password.
    final looksLikePin = isMember && _pass.text.length <= 6 && int.tryParse(_pass.text) != null;
    var ok = await ref.read(sessionProvider.notifier).signIn(
          userId: id,
          password: looksLikePin ? null : _pass.text,
          pin: looksLikePin ? _pass.text : null,
        );
    if (!ok && isMember && looksLikePin) {
      // Fall back to treating it as a password rather than telling a member
      // their PIN is wrong when the account simply has no PIN set.
      ok = await ref.read(sessionProvider.notifier).signIn(userId: id, password: _pass.text);
    }

    if (!mounted) return;
    if (ok) {
      final role = ref.read(sessionProvider).user!.roleKey;
      ref.read(viewRoleProvider.notifier).set(role);
      if (role == 'member') {
        final table = ref.read(sessionProvider).user?.tableNo;
        if (table != null) ref.read(previewTableProvider.notifier).set(table);
      }
      context.go(homeFor(role));
    } else {
      setState(() {
        _busy = false;
        _error = ref.read(sessionProvider).error ?? 'Sign in failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 980;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: wide
            ? Row(children: [
                Expanded(flex: 105, child: _Art()),
                Expanded(flex: 95, child: _form(context)),
              ])
            : _form(context),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final isMember = _role == 'member';
    return Container(
      color: Brand.bg2,
      child: Stack(children: [
        Positioned(
          top: 18,
          right: 18,
          child: IconTile(
            icon: Brand.isLight ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            tooltip: 'Switch light / dark theme',
            onTap: () => ref.read(themeLightProvider.notifier).toggle(),
          ),
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 52),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 392),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SMark(width: 38, height: 41),
                const SizedBox(height: 20),
                Text('Sign in to SPD', style: display(size: 26)),
                const SizedBox(height: 7),
                Text(
                  'Vistarlogitek · Stores / Special Packing Division',
                  style: body(size: 13.5, color: Brand.txt3),
                ),
                const SizedBox(height: 26),

                Field(
                  label: 'User ID',
                  child: TextField(
                    controller: _user,
                    enabled: !isMember,
                    autocorrect: false,
                    style: body(size: 14),
                    onSubmitted: (_) => _signIn(),
                  ),
                ),
                Field(
                  label: isMember ? 'PIN or password' : 'Password',
                  child: TextField(
                    controller: _pass,
                    obscureText: true,
                    style: body(size: 14),
                    onSubmitted: (_) => _signIn(),
                  ),
                ),

                Field(
                  label: 'Sign in as',
                  bottom: 9,
                  child: LayoutBuilder(builder: (context, c) {
                    final w = (c.maxWidth - 10) / 2;
                    return Wrap(spacing: 10, runSpacing: 10, children: [
                      for (final (key, title, sub, uid) in _roles)
                        SizedBox(width: w, child: _RoleChip(
                          title: title,
                          subtitle: sub,
                          selected: _role == key,
                          onTap: () => setState(() {
                            _role = key;
                            _error = null;
                            _user.text = uid ?? (_memberId ?? '');
                            _pass.text = key == 'member' ? '' : 'vistar@2026';
                          }),
                        )),
                    ]);
                  }),
                ),
                const SizedBox(height: 6),

                // #counter-pick — only shown for a Table Member (FR-5.1).
                if (isMember)
                  Field(
                    label: 'Table member',
                    child: SpdDropdown<String>(
                      value: _memberId,
                      items: [
                        for (final m in _members)
                          DropdownMenuItem(
                            value: '${m['id']}',
                            child: Text(
                              '${m['name']} · ${m['emp_code']}${m['table_no'] != null ? ' · ${m['table_no']}' : ''}',
                              style: body(size: 13.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        _memberId = v;
                        _user.text = v ?? '';
                      }),
                    ),
                  ),

                if (_error != null) ...[
                  AlertBox(tone: AlertTone.bad, title: 'Sign in failed', message: _error!),
                  const SizedBox(height: 14),
                ],

                GradButton(
                  label: _busy ? 'Signing in…' : 'Start the shift',
                  icon: Icons.login_rounded,
                  expand: true,
                  onPressed: _busy ? null : _signIn,
                ),
                const SizedBox(height: 22),
                Center(
                  child: Text(
                    'Role-based access · every action is audit-logged',
                    style: body(size: 11.5, color: Brand.txt3, height: 1.6),
                    textAlign: TextAlign.center,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// `.role-chip`
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.title, required this.subtitle, required this.selected, required this.onTap});

  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? Colors.white : Brand.txt;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            gradient: selected ? Brand.ribbon : null,
            color: selected ? null : Brand.surface,
            border: Border.all(color: selected ? Colors.transparent : Brand.line),
            borderRadius: BorderRadius.circular(13),
            boxShadow: selected
                ? [BoxShadow(color: Brand.pink.withValues(alpha: 0.6), blurRadius: 34, spreadRadius: -16, offset: const Offset(0, 14))]
                : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: body(size: 13.5, weight: FontWeight.w800, color: ink)),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: body(size: 11.5, color: selected ? Colors.white.withValues(alpha: 0.85) : Brand.txt3),
              maxLines: 2,
            ),
          ]),
        ),
      ),
    );
  }
}

/// `#login .art` — the brand panel with the headline and the three stats.
class _Art extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.64, -0.84),
          radius: 1.1,
          colors: [Brand.purple.withValues(alpha: Brand.isLight ? 0.16 : 0.34), Colors.transparent],
          stops: const [0, 0.62],
        ),
      ),
      child: Stack(children: [
        // .bigS — the oversized, rotated brand mark behind the copy.
        Positioned.fill(
          child: IgnorePointer(
            child: LayoutBuilder(builder: (context, c) {
              final s = c.maxHeight * 0.78;
              return Stack(children: [
                Positioned(
                  left: c.maxWidth * 0.44 - s / 2,
                  top: (c.maxHeight - s) / 2,
                  width: s,
                  height: s,
                  child: Opacity(
                    opacity: Brand.isLight ? 0.14 : 0.16,
                    child: Transform.rotate(
                      angle: -0.192,
                      child: Image.asset('assets/brand/vistar_s.png', fit: BoxFit.contain),
                    ),
                  ),
                ),
              ]);
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 52),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Wordmark(size: 36),
            const Spacer(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('From GRN to MIS.', style: display(size: 44, height: 1.08)),
                Row(children: [
                  Text('Zero ', style: display(size: 44, height: 1.08)),
                  GradientText('re-typing', style: display(size: 44, height: 1.08)),
                  Text('.', style: display(size: 44, height: 1.08)),
                ]),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 452),
                  child: Text(
                    'The SAP GRN report goes in once — the system validates it, prints the ID '
                    'labels, maps tables, captures every Start / Submit on the floor with time '
                    'stamps, reconciles packed vs GRN quantity live, emails the hourly status '
                    'and writes the MIS the moment the shift is finalised.',
                    style: body(size: 14.5, color: Brand.txt2, height: 1.65),
                  ),
                ),
              ]),
            ),
            const Spacer(),
            Wrap(spacing: 38, runSpacing: 18, children: const [
              _Stat('~1 hr', 'Supervisor time saved / shift'),
              _Stat('0', 'Paper sheets on the floor'),
              _Stat('Hourly', 'Status in the inbox'),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.caption);

  final String value, caption;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GradientText(value, style: display(size: 27, height: 1)),
          const SizedBox(height: 7),
          Text(caption.toUpperCase(), style: eyebrow(size: 11, tracking: 0.8)),
        ],
      );
}
