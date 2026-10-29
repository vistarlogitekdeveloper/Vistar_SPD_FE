import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spd_frontend/core/api.dart';
import 'package:spd_frontend/core/theme.dart';
import 'package:spd_frontend/data/providers.dart';
import 'package:spd_frontend/data/repository.dart';
import 'package:spd_frontend/models/models.dart';
import 'package:spd_frontend/ui/login_screen.dart';

/// The sign-in screen and the session behind it.
///
/// Both changed together for one reason: a shift that is interrupted. The role
/// chips decided nothing and cleared the form when mis-tapped; the secret could
/// not be read back while being typed on a tablet; and the session lived only
/// in memory, so minimising the browser on a phone signed the operator out
/// mid-shift. None of that shows up in a render test — it is all behaviour.
void main() {
  Future<void> pumpLogin(WidgetTester tester, {SharedPreferences? prefs}) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        if (prefs != null) sharedPrefsProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(theme: buildTheme(light: false), home: const LoginScreen()),
    ));
    await tester.pump();
  }

  group('the sign-in form', () {
    testWidgets('offers no role to choose', (tester) async {
      /* The account decides the role — the server reads it off spd.users and
         signs it into the token. The chips were a claim it ignored, and tapping
         one cleared both boxes, so a mis-tap on a shop-floor tablet cost you
         what you had already typed. */
      await pumpLogin(tester);
      for (final chip in ['Supervisor', 'Table Member', 'Administrator', 'Management']) {
        expect(find.text(chip), findsNothing, reason: '$chip is still offered as a choice');
      }
      expect(find.text('Sign in as'), findsNothing);

      // What is left is what the server actually asks for.
      expect(find.text('USER ID'), findsOneWidget);
      expect(find.text('PASSWORD OR PIN'), findsOneWidget);
    });

    testWidgets('the secret can be revealed while it is typed', (tester) async {
      await pumpLogin(tester);
      final field = find.byType(TextField).last;
      await tester.enterText(field, '4821');
      await tester.pump();

      TextField secret() => tester.widget<TextField>(field);
      expect(secret().obscureText, isTrue, reason: 'it starts hidden');

      await tester.tap(find.byTooltip('Show'));
      await tester.pump();
      expect(secret().obscureText, isFalse, reason: 'the eye did not reveal it');

      await tester.tap(find.byTooltip('Hide'));
      await tester.pump();
      expect(secret().obscureText, isTrue, reason: 'and it must hide again');
    });

    testWidgets('keeping the session signed in is offered, and on by default', (tester) async {
      await pumpLogin(tester);
      expect(find.text('Keep me signed in on this device'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue,
          reason: 'a minimised phone signing the floor out mid-shift is the bug this fixes');
    });
  });

  group('restoring a kept session', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    ProviderContainer containerWith(SpdRepository repo, SharedPreferences prefs) {
      final c = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        repositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('with nothing stored it asks for a sign-in', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = containerWith(_OkRepo(), prefs);
      expect(await c.read(sessionProvider.notifier).restore(), isNull);
    });

    test('a stored token that the server still honours comes back signed in', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('spd.auth.token', 'kept-token');
      final c = containerWith(_OkRepo(), prefs);

      expect(await c.read(sessionProvider.notifier).restore(), 'member');
      expect(c.read(sessionProvider).signedIn, isTrue);
      /* The user is re-read rather than stored, so a role or table an
         Administrator changed overnight is the one that takes effect. */
      expect(c.read(sessionProvider).user!.name, 'Anita Varma');
    });

    test('an expired token is cleared, not left to fail on every screen', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('spd.auth.token', 'stale-token');
      final c = containerWith(_ExpiredRepo(), prefs);

      expect(await c.read(sessionProvider.notifier).restore(), isNull);
      expect(prefs.getString('spd.auth.token'), isNull,
          reason: 'a token the server refuses must not be tried again');
    });

    test('an unreachable server keeps the token for the next try', () async {
      /* Discarding it here would sign out a whole floor over one bad minute of
         wifi, and the token is good for twelve hours. */
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('spd.auth.token', 'good-token');
      final c = containerWith(_OfflineRepo(), prefs);

      expect(await c.read(sessionProvider.notifier).restore(), isNull);
      expect(prefs.getString('spd.auth.token'), 'good-token');
    });

    test('signing out forgets the device', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('spd.auth.token', 'kept-token');
      final c = containerWith(_OkRepo(), prefs);

      await c.read(sessionProvider.notifier).restore();
      await c.read(sessionProvider.notifier).signOut();
      expect(prefs.getString('spd.auth.token'), isNull);
      expect(c.read(sessionProvider).signedIn, isFalse);
    });
  });
}

class _OkRepo extends SpdRepository {
  _OkRepo() : super(ApiClient(baseUrl: 'http://127.0.0.1:1/api'));

  @override
  Future<SpdUser> me() async => SpdUser(const {
        'id': 'tm.anita', 'name': 'Anita Varma', 'emp_code': 'E-001',
        'role': 'Member', 'table_no': 'T-01', 'active': true,
      });
}

class _ExpiredRepo extends SpdRepository {
  _ExpiredRepo() : super(ApiClient(baseUrl: 'http://127.0.0.1:1/api'));

  @override
  Future<SpdUser> me() async => throw ApiException('Session expired', statusCode: 401);
}

class _OfflineRepo extends SpdRepository {
  _OfflineRepo() : super(ApiClient(baseUrl: 'http://127.0.0.1:1/api'));

  @override
  Future<SpdUser> me() async => throw StateError('no route to host');
}
