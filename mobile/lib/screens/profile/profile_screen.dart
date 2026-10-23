import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_state.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final u = auth.user;
    if (u == null) return const Scaffold(body: LoadingView());

    Widget tile(IconData icon, String title, String route, {String? trailing, Color? color}) => ListTile(
          leading: Icon(icon, color: color ?? AppColors.navy),
          title: Text(title, style: AppText.labelLg.copyWith(color: color)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (trailing != null) Text(trailing, style: AppText.bodySm),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ]),
          onTap: () => context.push(route),
        );

    return Scaffold(
      appBar: appBar(context, 'Profile', back: false),
      body: RefreshIndicator(
        onRefresh: () => auth.refreshMe(),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          AppCard(
            child: Row(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.navy,
                child: Text(u.initials, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(u.fullName, style: AppText.headlineMd, overflow: TextOverflow.ellipsis)),
                    if (Provider.of<ApiClient>(context, listen: false).isDemo) ...[const SizedBox(width: 8), const DemoBadge()],
                  ]),
                  Text(u.email, style: AppText.bodySm),
                  if (u.phone != null) Text(u.phone!, style: AppText.bodySm),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, children: [
                    if (u.city != null) StatusBadge(u.city!, icon: Icons.location_on_outlined),
                    StatusBadge('Since ${formatDate(u.createdAt)}', kind: BadgeKind.info),
                  ]),
                ]),
              ),
              IconButton(onPressed: () => context.push('/profile/edit'), icon: const Icon(Icons.edit_outlined)),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _Stat(label: 'Devices', value: auth.deviceCount),
            const SizedBox(width: 12),
            _Stat(label: 'Active listings', value: auth.activeListings),
            const SizedBox(width: 12),
            _Stat(label: 'Unread', value: auth.unreadNotifications),
          ]),
          const SectionHeader('My activity'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              tile(Icons.phone_android_rounded, 'My devices', '/devices'),
              tile(Icons.storefront_outlined, 'My listings', '/listings/mine'),
              tile(Icons.handshake_outlined, 'Purchase requests', '/requests'),
              tile(Icons.swap_horiz_rounded, 'Ownership transfers', '/transfers'),
              tile(Icons.gpp_maybe_outlined, 'Stolen reports', '/reports'),
              tile(Icons.notifications_none_rounded, 'Notifications', '/notifications', trailing: auth.unreadNotifications > 0 ? '${auth.unreadNotifications} new' : null),
            ]),
          ),
          const SectionHeader('Settings'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              tile(Icons.person_outline, 'Edit profile', '/profile/edit'),
              tile(Icons.lock_outline_rounded, 'Change password', '/profile/password'),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded, color: AppColors.navy),
                title: Text('About DeviceTrust', style: AppText.labelLg),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'DeviceTrust',
                  applicationVersion: '1.0.0',
                  children: [
                    const Text('Community mobile device registry and verified marketplace. '
                        'Registry results are not official PTA/DIRBS checks.'),
                    const SizedBox(height: 8),
                    Text(AppConfig.demoMode ? 'Mode: offline demo (sample data)' : 'Server: ${AppConfig.apiBaseUrl}', style: AppText.monoData),
                  ],
                ),
              ),
            ]),
          ),
          if (Provider.of<ApiClient>(context, listen: false).isDemo) ...[
            const SectionHeader('Demo'),
            const DemoBanner(),
            const SizedBox(height: 10),
            AppButton(
              label: 'Reset demo data',
              kind: ButtonKind.ghost,
              icon: Icons.restart_alt_rounded,
              onPressed: () async {
                if (!await confirmDialog(context,
                    title: 'Reset demo data?',
                    message: 'All sample phones, listings and requests return to their original state. Accounts you created on this phone are removed.',
                    confirm: 'Reset',
                    danger: true)) {
                  return;
                }
                if (!context.mounted) return;
                await context.read<ApiClient>().demo!.reset();
                await auth.logout();
              },
            ),
          ],
          const SizedBox(height: 20),
          AppButton(
            label: 'Log out',
            kind: ButtonKind.dangerOutline,
            icon: Icons.logout_rounded,
            onPressed: () async {
              if (await confirmDialog(context, title: 'Log out?', message: 'You will need to sign in again.', confirm: 'Log out', danger: true)) {
                await auth.logout();
              }
            },
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(children: [
          Text('$value', style: AppText.headlineLg),
          Text(label, style: AppText.bodySm, textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
