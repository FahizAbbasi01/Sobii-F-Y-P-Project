import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/devices/device_detail_screen.dart';
import '../screens/devices/my_devices_screen.dart';
import '../screens/devices/register_device_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/imei/imei_check_screen.dart';
import '../screens/marketplace/browse_screen.dart';
import '../screens/marketplace/listing_detail_screen.dart';
import '../screens/marketplace/listing_form_screen.dart';
import '../screens/marketplace/my_listings_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/onboarding/splash_screen.dart';
import '../screens/profile/change_password_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/purchases/purchase_requests_screen.dart';
import '../screens/reports/my_reports_screen.dart';
import '../screens/reports/stolen_report_screen.dart';
import '../screens/sell/sell_screen.dart';
import '../screens/shell.dart';
import '../screens/transfers/new_transfer_screen.dart';
import '../screens/transfers/transfer_detail_screen.dart';
import '../screens/transfers/transfers_screen.dart';
import 'auth_state.dart';

const _publicRoutes = {'/splash', '/onboarding', '/login', '/register'};

GoRouter buildRouter(AuthState auth) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      switch (auth.status) {
        case AuthStatus.unknown:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.signedOut:
          if (_publicRoutes.contains(loc) && loc != '/splash') return null;
          return auth.onboardingSeen ? '/login' : '/onboarding';
        case AuthStatus.signedIn:
          return _publicRoutes.contains(loc) ? '/home' : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/explore',
              builder: (_, state) => BrowseScreen(initialQuery: state.uri.queryParameters['q'], initialBrand: state.uri.queryParameters['brand']),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/check', builder: (_, state) => ImeiCheckScreen(initialImei: state.uri.queryParameters['imei'])),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/sell', builder: (_, __) => const SellScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen())]),
        ],
      ),
      GoRoute(path: '/listing/:id', builder: (_, s) => ListingDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/listings/mine', builder: (_, __) => const MyListingsScreen()),
      GoRoute(
        path: '/listings/new',
        builder: (_, s) => ListingFormScreen(deviceId: s.uri.queryParameters['deviceId']),
      ),
      GoRoute(path: '/listings/:id/edit', builder: (_, s) => ListingFormScreen(listingId: s.pathParameters['id'])),
      GoRoute(path: '/devices', builder: (_, __) => const MyDevicesScreen()),
      GoRoute(path: '/devices/new', builder: (_, s) => RegisterDeviceScreen(thenSell: s.uri.queryParameters['sell'] == '1')),
      GoRoute(path: '/devices/:id', builder: (_, s) => DeviceDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/devices/:id/transfer', builder: (_, s) => NewTransferScreen(deviceId: s.pathParameters['id']!)),
      GoRoute(path: '/devices/:id/report', builder: (_, s) => StolenReportScreen(deviceId: s.pathParameters['id']!)),
      GoRoute(path: '/requests', builder: (_, s) => PurchaseRequestsScreen(initialTab: s.uri.queryParameters['tab'] == 'selling' ? 1 : 0)),
      GoRoute(path: '/transfers', builder: (_, __) => const TransfersScreen()),
      GoRoute(path: '/transfers/:id', builder: (_, s) => TransferDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/reports', builder: (_, __) => const MyReportsScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/profile/edit', builder: (_, __) => const EditProfileScreen()),
      GoRoute(path: '/profile/password', builder: (_, __) => const ChangePasswordScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
}
