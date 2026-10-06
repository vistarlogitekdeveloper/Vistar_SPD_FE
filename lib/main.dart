import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/telemetry.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Usage analytics: off unless the build carries ET_APP_ID + ET_WRITE_KEY
  // (core/telemetry.dart). Waits at most 2 s, never throws.
  await Telemetry.init();

  // The three typefaces ship in assets/google_fonts/. Refusing the runtime
  // fetch is the point of bundling them: the SRS puts this console on the
  // organisation's own LAN (§2.6), and a table device with no route to
  // fonts.gstatic.com would silently fall back to the platform font and lose
  // the approved design. Switching fetching off also turns a missing weight
  // into a loud error during development rather than a quiet download that
  // only works at a desk.
  GoogleFonts.config.allowRuntimeFetching = false;
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF070611),
  ));

  // Loaded before the first frame so the remembered theme is the one that
  // paints, rather than a dark flash corrected a moment later. If storage is
  // unavailable the app still starts — it just forgets the choice, which is a
  // far better outcome than a shift that cannot sign in.
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (err) {
    debugPrint('[spd] local storage unavailable — the theme will not persist: $err');
  }

  // The container is built here rather than left to ProviderScope so the
  // retry policy is explicit: ProviderScope does not expose one, and the
  // default holds a failure behind a loader for some thirty-eight seconds.
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    retry: spdRetry,
  );

  runApp(UncontrolledProviderScope(
    container: container,
    child: const SpdApp(),
  ));
}
