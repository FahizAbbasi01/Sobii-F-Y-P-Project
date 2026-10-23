import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/auth_state.dart';
import 'core/config.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'demo/demo_backend.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark));
  runApp(buildApp(demo: AppConfig.demoMode ? DemoBackend() : null));
}

/// Builds the whole app. With [demo] set, all data comes from the in-app demo backend
/// (no server, no internet). Without it, the app talks to the real API at AppConfig.apiBaseUrl.
Widget buildApp({DemoBackend? demo}) {
  final tokens = TokenStore(secure: demo == null);
  final api = ApiClient(tokens, demo: demo);
  final auth = AuthState(api, tokens);
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<AuthState>.value(value: auth),
    ],
    child: DeviceTrustApp(auth: auth),
  );
}

class DeviceTrustApp extends StatefulWidget {
  const DeviceTrustApp({super.key, required this.auth});
  final AuthState auth;

  @override
  State<DeviceTrustApp> createState() => _DeviceTrustAppState();
}

class _DeviceTrustAppState extends State<DeviceTrustApp> {
  late final router = buildRouter(widget.auth);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'DeviceTrust',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
    );
  }
}
