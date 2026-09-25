import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const SpdApp(),
  ));
}
