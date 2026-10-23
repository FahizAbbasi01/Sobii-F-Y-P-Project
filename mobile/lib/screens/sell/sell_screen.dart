import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../devices/my_devices_screen.dart';

/// Step 1 of selling: choose a registered device (or register a new one).
class SellScreen extends StatefulWidget {
  const SellScreen({super.key});

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  late Future<List<Device>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchMyDevices(context.read<ApiClient>());
  }

  void _reload() => setState(() {
      _future = fetchMyDevices(context.read<ApiClient>());
    });

  Future<void> _go(String route) async {
    await context.push(route);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'Sell Your Phone', back: false, actions: [
        TextButton.icon(onPressed: () => _go('/listings/mine'), icon: const Icon(Icons.list_alt_rounded), label: const Text('My listings')),
      ]),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          _Steps(),
          const SizedBox(height: 8),
          AppButton(label: 'Register a new phone & sell it', icon: Icons.add_circle_outline, onPressed: () => _go('/devices/new?sell=1')),
          const SectionHeader('Or choose a registered phone'),
          FutureBuilder<List<Device>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const LoadingView();
              if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
              final devices = snap.data!;
              if (devices.isEmpty) {
                return Text('You have no registered phones yet. Register one above to start selling.', style: AppText.bodyMd);
              }
              return Column(children: [
                for (final d in devices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DeviceTile(
                      device: d,
                      onTap: () {
                        if (d.isStolen) {
                          showSnack(context, 'Stolen-flagged devices cannot be sold.', error: true);
                        } else if (d.liveListing != null) {
                          _go('/listing/${d.liveListing!['id']}');
                        } else if (d.isBusy) {
                          _go('/devices/${d.id}');
                        } else {
                          _go('/listings/new?deviceId=${d.id}');
                        }
                      },
                      trailing: (!d.isStolen && !d.isBusy)
                          ? const StatusBadge('Sell', kind: BadgeKind.info, icon: Icons.sell_outlined)
                          : null,
                    ),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget step(int n, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 13, backgroundColor: AppColors.navy, child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppText.labelLg),
                Text(body, style: AppText.bodySm),
              ]),
            ),
          ]),
        );
    return AppCard(
      child: Column(children: [
        step(1, 'Register the IMEI', 'Proves the phone is yours. Each IMEI can only be registered once.'),
        step(2, 'Create a listing', 'Add price, condition, city and photos.'),
        step(3, 'Accept a buyer & confirm', 'Both of you confirm in the app, and ownership moves to the buyer.'),
      ]),
    );
  }
}
