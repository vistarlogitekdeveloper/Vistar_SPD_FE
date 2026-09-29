import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spd_frontend/app.dart';
import 'package:spd_frontend/data/providers.dart';

/// These run the real widget tree, so they catch the framework assertions that
/// a release build silently strips — which is how a tear-down bug reached a
/// developer's `flutter run` after the release bundle had been signed off.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget harness() => ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: const SpdApp(),
      );

  testWidgets('boots, leaves the splash and reaches the login screen', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    // The splash holds for 2.2s before routing to /login.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('Sign in to SPD'), findsOneWidget);
  });

  testWidgets('switching the theme does not tear the tree down under its dependents', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    );

    container.read(themeLightProvider.notifier).toggle();
    await tester.pumpAndSettle();
    expect(container.read(themeLightProvider), isTrue);

    container.read(themeLightProvider.notifier).toggle();
    await tester.pumpAndSettle();
    expect(container.read(themeLightProvider), isFalse);
  });
}
