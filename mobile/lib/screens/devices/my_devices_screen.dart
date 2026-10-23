import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

Future<List<Device>> fetchMyDevices(ApiClient api) async {
  final data = await api.get('/devices') as Map<String, dynamic>;
  return (data['devices'] as List).map((e) => Device.fromJson(e as Map<String, dynamic>)).toList();
}

class MyDevicesScreen extends StatefulWidget {
  const MyDevicesScreen({super.key});

  @override
  State<MyDevicesScreen> createState() => _MyDevicesScreenState();
}

class _MyDevicesScreenState extends State<MyDevicesScreen> {
  late Future<List<Device>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchMyDevices(context.read<ApiClient>());
  }

  void _reload() => setState(() => _future = fetchMyDevices(context.read<ApiClient>()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'My Devices', actions: [
        IconButton(tooltip: 'My stolen reports', icon: const Icon(Icons.history_rounded), onPressed: () => context.push('/reports')),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        onPressed: () async {
          await context.push('/devices/new');
          _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Register device'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AsyncView<List<Device>>(
          future: _future,
          onRetry: _reload,
          builder: (context, devices) {
            if (devices.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                EmptyView(
                  icon: Icons.phone_android_rounded,
                  title: 'No registered devices',
                  message: 'Register your phone\'s IMEI to prove ownership, sell it, or report it if stolen.',
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: devices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => DeviceTile(
                device: devices[i],
                onTap: () async {
                  await context.push('/devices/${devices[i].id}');
                  _reload();
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class DeviceTile extends StatelessWidget {
  const DeviceTile({super.key, required this.device, required this.onTap, this.trailing});
  final Device device;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final d = device;
    return AppCard(
      onTap: onTap,
      accent: d.isStolen ? AppColors.red : (d.reportPending || d.pendingTransferId != null ? AppColors.amber : AppColors.green),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: d.isStolen ? AppColors.redBg : AppColors.blueBg, borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.smartphone_rounded, color: d.isStolen ? AppColors.redText : AppColors.blue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name, style: AppText.labelLg),
            if (d.subtitle.isNotEmpty) Text(d.subtitle, style: AppText.bodySm),
            if (d.primaryImei != null) ...[
              const SizedBox(height: 4),
              Text(formatImei(d.primaryImei!), style: AppText.monoData),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              statusBadge(d.registryStatus),
              if (d.liveListing != null) StatusBadge('Listed • ${d.liveListing!['status']}', kind: BadgeKind.info, icon: Icons.storefront_outlined),
              if (d.pendingTransferId != null) const StatusBadge('Transfer pending', kind: BadgeKind.warning, icon: Icons.swap_horiz),
              if (d.reportPending) const StatusBadge('Report under review', kind: BadgeKind.warning, icon: Icons.schedule),
            ]),
          ]),
        ),
        trailing ?? const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
      ]),
    );
  }
}
