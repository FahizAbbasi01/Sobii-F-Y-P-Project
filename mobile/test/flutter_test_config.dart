import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file: load the app's real bundled fonts so text in widget
/// tests has the same width as on a phone (the default test font is much wider).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final inter = FontLoader('Inter');
  for (final w in ['400Regular', '500Medium', '600SemiBold', '700Bold', '800ExtraBold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter_$w.ttf'));
  }
  await inter.load();
  final mono = FontLoader('JetBrainsMono')
    ..addFont(rootBundle.load('assets/fonts/JetBrainsMono_400Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/JetBrainsMono_500Medium.ttf'));
  await mono.load();
  final roboto = FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Inter_400Regular.ttf'));
  await roboto.load();
  await testMain();
}
