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
  /* The four role chips are gone.

     They never decided anything. The account decides the role — the server
     reads it off spd.users and signs it into the token — so the chip was a
     claim the server ignored, and picking the wrong one changed nothing
     except which word the password field was labelled with. It also cleared
     both boxes on every tap, which on a shop-floor tablet meant a mis-tap
     cost you what you had already typed.

     What is left is what the server actually asks for: who you are and your
     secret. */

  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _show = false;
  bool _remember = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final id = _user.text.trim();
    if (id.isEmpty) {
      setState(() => _error = 'Enter your user ID to continue');
      return;
    }
    if (_pass.text.isEmpty) {
      setState(() => _error = 'Enter your password or PIN to continue');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    /* A short all-digit secret could be either a Member’s PIN or somebody
       else's numeric password, and with the role chips gone the console no
       longer has even a claim about which. So it sends BOTH fields: the
       server uses the PIN only for a Member and the password for everyone
       else, which is the one place that actually knows the role.

       The fallback below stays for the Member whose secret happens to be a
       short numeric PASSWORD — the server would try it as a PIN, find no
       pin_hash, and refuse something that is in fact correct. */
    final looksLikePin = _pass.text.length <= 6 && int.tryParse(_pass.text) != null;
    /* No table is sent. The console used to ask for one here, from a picker
       filled by a pre-authentication call that listed the whole floor to
       anybody who loaded the page — and a member is on exactly one table in a
       shift, so the server was being asked to confirm the only answer it could
       have given. It resolves it from the Supervisor's seating instead, which
       is what builds before the picker always relied on. */
    var ok = await ref.read(sessionProvider.notifier).signIn(
          userId: id,
          password: _pass.text,
          pin: looksLikePin ? _pass.text : null,
          remember: _remember,
        );
    if (!ok && looksLikePin) {
      // The Member whose secret is a short numeric password rather than a
      // PIN: tried as a PIN it is refused, and it is not wrong.
      ok = await ref.read(sessionProvider.notifier).signIn(
            userId: id, password: _pass.text, remember: _remember);
    }

    if (!mounted) return;
    if (ok) {
      final role = ref.read(sessionProvider).user!.roleKey;
      ref.read(viewRoleProvider.notifier).set(role);
      if (role == 'member') {
        final table = ref.read(sessionProvider).user?.tableNo;
        if (table != null) {
          ref.read(previewTableProvider.notifier).set(table);
          /* Who is actually at the bench is asked here rather than on this
             screen: it is a question for the people already standing at the
             table, it has more than one answer, and most of those people have
             no account to pick from a list. The shell opens it on the screen
             the member lands on — see operatorPromptProvider. */
          ref.read(operatorPromptProvider.notifier).set(table);
        }
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
                    autocorrect: false,
                    autofillHints: const [],
                    enableSuggestions: false,
                    style: body(size: 14),
                    onSubmitted: (_) => _signIn(),
                  ),
                ),
                Field(
                  label: 'Password or PIN',
                  bottom: 10,
                  child: TextField(
                    controller: _pass,
                    obscureText: !_show,
                    style: body(size: 14),
                    onSubmitted: (_) => _signIn(),
                    decoration: InputDecoration(
                      /* A four-digit PIN typed on a tablet, in a stores
                         bay, with gloves on. Being unable to see what you
                         typed is what turns one fat-fingered digit into
                         three failed attempts and a locked account — the
                         account limiter stops at thirty. */
                      suffixIcon: IconButton(
                        icon: Icon(
                          _show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 18,
                          color: Brand.txt3,
                        ),
                        tooltip: _show ? 'Hide' : 'Show',
                        onPressed: () => setState(() => _show = !_show),
                      ),
                    ),
                  ),
                ),

                /* Stay signed in across a minimise.

                   On a phone the browser evicts a backgrounded page, and the
                   session lived only in memory — so coming back to the app
                   was a fresh load and another sign-in, mid-shift, every
                   time. On by default because that is the behaviour anyone
                   expects; a shared bench tablet that should forget its
                   operator turns it off here.

                   What is kept is the token, which the server already
                   expires after twelve hours. Signing out clears it. */
                _RememberBox(
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v),
                ),
                const SizedBox(height: 14),

                /* Two pickers used to stand here: a roster a Table Member
                   found their own name in, and the table they were on today.
                   Both are gone.

                   The roster was a list of every operator in the company,
                   served to anyone who could load the login page, scrolled
                   past rather than read on a shared tablet — and it could name
                   exactly one person, when a bench often has three. The table
                   was the only answer the server could have given anyway: a
                   member is seated at one table in a shift, so it resolves it
                   from the Supervisor's seating and refuses anything else.

                   Who is at the bench is now asked after sign-in, at the
                   bench, of the people standing there, and it takes as many
                   names as there are. See [showOperatorPrompt]. */

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

/// "Keep me signed in" — a checkbox and its reason, in the prototype’s hand.
class _RememberBox extends StatelessWidget {
  const _RememberBox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  activeColor: Brand.pink,
                  side: BorderSide(color: Brand.fieldLine, width: 1.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Keep me signed in on this device',
                  style: body(size: 13, color: Brand.txt2),
                ),
              ),
            ]),
          ),
        ),
      );
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
