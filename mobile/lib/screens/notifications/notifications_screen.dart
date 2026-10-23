import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<AppNotification>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AppNotification>> _load() async {
    final data = await context.read<ApiClient>().get('/notifications') as Map<String, dynamic>;
    if (mounted) context.read<AuthState>().setUnread((data['unreadCount'] as num).toInt());
    return (data['notifications'] as List).map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
  }

  void _reload() => setState(() {
      _future = _load();
    });

  Future<void> _readAll() async {
    try {
      await context.read<ApiClient>().post('/notifications/read-all');
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  /// Deep-link from a notification to the screen it's about.
  String? _routeFor(AppNotification n) {
    final d = n.data;
    if (d['transferId'] != null) return '/transfers/${d['transferId']}';
    if (n.type.startsWith('purchase.')) return n.type == 'purchase.new' ? '/requests?tab=selling' : '/requests';
    if (d['listingId'] != null) return '/listing/${d['listingId']}';
    if (d['deviceId'] != null) return '/devices/${d['deviceId']}';
    if (n.type.startsWith('report.')) return '/reports';
    return null;
  }

  Future<void> _open(AppNotification n) async {
    final api = context.read<ApiClient>();
    if (!n.read) api.post('/notifications/${n.id}/read').catchError((_) {});
    final route = _routeFor(n);
    if (route != null) await context.push(route);
    _reload();
  }

  IconData _icon(String type) {
    if (type.startsWith('transfer')) return Icons.swap_horiz_rounded;
    if (type.startsWith('purchase')) return Icons.handshake_outlined;
    if (type.startsWith('report')) return Icons.gpp_maybe_outlined;
    if (type.startsWith('listing')) return Icons.storefront_outlined;
    if (type.startsWith('document')) return Icons.description_outlined;
    return Icons.notifications_none_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'Notifications', actions: [TextButton(onPressed: _readAll, child: const Text('Mark all read'))]),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AsyncView<List<AppNotification>>(
          future: _future,
          onRetry: _reload,
          builder: (context, items) {
            if (items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                EmptyView(icon: Icons.notifications_off_outlined, title: 'All caught up', message: 'Updates about your requests, transfers and reports appear here.'),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) {
                final n = items[i];
                return ListTile(
                  onTap: () => _open(n),
                  tileColor: n.read ? null : const Color(0x0A246BFD),
                  leading: CircleAvatar(
                    backgroundColor: n.type.contains('reject') || n.type.contains('removed') || n.type.contains('disputed') ? AppColors.redBg : AppColors.blueBg,
                    child: Icon(_icon(n.type), color: AppColors.navy, size: 20),
                  ),
                  title: Text(n.title, style: AppText.labelLg.copyWith(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 2),
                    Text(n.body, style: AppText.bodyMd),
                    const SizedBox(height: 4),
                    Text(timeAgo(n.createdAt), style: AppText.bodySm),
                  ]),
                  trailing: n.read ? null : const Icon(Icons.circle, size: 10, color: AppColors.blue),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
