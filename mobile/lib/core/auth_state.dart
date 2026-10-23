import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_client.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// App-wide session state. Drives router redirects.
class AuthState extends ChangeNotifier {
  AuthState(this.api, this.tokens) {
    api.onSessionExpired = _expire;
  }

  final ApiClient api;
  final TokenStore tokens;

  AuthStatus status = AuthStatus.unknown;
  AppUser? user;
  bool onboardingSeen = false;
  String? startupError;
  int unreadNotifications = 0;
  int deviceCount = 0;
  int activeListings = 0;

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
    await tokens.load();
    if (tokens.refreshToken == null && tokens.accessToken == null) {
      status = AuthStatus.signedOut;
    } else {
      try {
        await refreshMe();
        status = AuthStatus.signedIn;
      } on ApiException catch (e) {
        // Server unreachable: keep stored tokens so signing in later is seamless,
        // but show the login screen with the reason.
        if (!e.isNetwork) await tokens.clear();
        startupError = e.isNetwork ? e.message : null;
        status = AuthStatus.signedOut;
      }
    }
    notifyListeners();
  }

  Future<void> markOnboardingSeen() async {
    onboardingSeen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    notifyListeners();
  }

  Future<void> refreshMe() async {
    final data = await api.get('/auth/me') as Map<String, dynamic>;
    user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    final stats = (data['stats'] ?? {}) as Map<String, dynamic>;
    unreadNotifications = (stats['unreadNotifications'] as num?)?.toInt() ?? 0;
    deviceCount = (stats['devices'] as num?)?.toInt() ?? 0;
    activeListings = (stats['activeListings'] as num?)?.toInt() ?? 0;
    notifyListeners();
  }

  Future<void> _applySession(Map<String, dynamic> data) async {
    await tokens.save(data['accessToken'] as String, data['refreshToken'] as String);
    user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    status = AuthStatus.signedIn;
    await markOnboardingSeen();
    try {
      await refreshMe();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final data = await api.post('/auth/login', {'email': email, 'password': password});
    await _applySession(data as Map<String, dynamic>);
  }

  Future<void> register({required String email, required String password, required String fullName, String? phone, String? city}) async {
    final data = await api.post('/auth/register', {
      'email': email,
      'password': password,
      'fullName': fullName,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (city != null && city.isNotEmpty) 'city': city,
    });
    await _applySession(data as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final refresh = tokens.refreshToken;
    if (refresh != null) {
      try {
        await api.post('/auth/logout', {'refreshToken': refresh});
      } catch (_) {}
    }
    await tokens.clear();
    user = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  void _expire() {
    tokens.clear();
    user = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  void setUnread(int n) {
    unreadNotifications = n;
    notifyListeners();
  }
}
