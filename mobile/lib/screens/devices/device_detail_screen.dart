import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class _DeviceData {
  final Device device;
  final List<OwnershipRecord> history;
  _DeviceData(this.device, this.history);
}

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late Future<_DeviceData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DeviceData> _load() async {
    final data = await context.read<ApiClient>().get('/devices/${widget.id}') as Map<String, dynamic>;
    return _DeviceData(
      Device.fromJson(data['device'] as Map<String, dynamic>),
      (data['ownershipHistory'] as List).map((e) => OwnershipRecord.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _go(String route) async {
    await context.push(route);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'Device'),
      body: AsyncView<_DeviceData>(
        future: _future,
        onRetry: _reload,
        builder: (context, data) {
          final d = data.device;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
              AppCard(
                accent: d.isStolen ? AppColors.red : AppColors.green,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(d.name, style: AppText.headlineLg)),
                    statusBadge(d.registryStatus),
                  ]),
                  if (d.subtitle.isNotEmpty) Text(d.subtitle, style: AppText.bodyMd),
                  const SizedBox(height: 12),
                  for (final i in d.imeis) ImeiText(i.imei, label: 'IMEI ${i.slot}'),
                  const SizedBox(height: 4),
                  Text('Registered ${formatDate(d.registeredAt)}', style: AppText.bodySm),
                ]),
              ),
              const SizedBox(height: 16),
              ..._statusNotes(d),
              const SectionHeader('Actions'),
              ..._actions(d),
              const SectionHeader('Ownership history'),
              AppCard(
                child: Column(children: [
                  for (var i = 0; i < data.history.length; i++) _HistoryRow(record: data.history[i], last: i == data.history.length - 1),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }

  List<Widget> _statusNotes(Device d) {
    Widget note(BadgeKind kind, IconData icon, String text, {String? action, VoidCallback? onTap}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            onTap: onTap,
            child: Row(children: [
              StatusBadge('', kind: kind, icon: icon),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: AppText.bodyMd)),
              if (action != null) Text(action, style: AppText.labelLg.copyWith(color: AppColors.blue)),
            ]),
          ),
        );
    return [
      if (d.isStolen) note(BadgeKind.danger, Icons.gpp_bad, 'This device is flagged stolen. It cannot be listed or transferred.'),
      if (d.reportPending) note(BadgeKind.warning, Icons.schedule, 'Your stolen report is being reviewed by an admin.', action: 'View', onTap: () => _go('/reports')),
      if (d.pendingTransferId != null)
        note(BadgeKind.warning, Icons.swap_horiz, 'An ownership transfer is in progress.', action: 'Open', onTap: () => _go('/transfers/${d.pendingTransferId}')),
      if (d.liveListing != null)
        note(BadgeKind.info, Icons.storefront_outlined, 'Listed for ${formatPkr(d.liveListing!['price'] as num?)} (${d.liveListing!['status']}).',
            action: 'View', onTap: () => _go('/listing/${d.liveListing!['id']}')),
    ];
  }

  List<Widget> _actions(Device d) {
    final canTrade = !d.isStolen && !d.isBusy;
    return [
      AppButton(
        label: 'Sell on marketplace',
        icon: Icons.sell_outlined,
        onPressed: canTrade ? () => _go('/listings/new?deviceId=${d.id}') : null,
      ),
      const SizedBox(height: 10),
      AppButton(
        label: 'Transfer ownership directly',
        kind: ButtonKind.ghost,
        icon: Icons.swap_horiz_rounded,
        onPressed: canTrade ? () => _go('/devices/${d.id}/transfer') : null,
      ),
      const SizedBox(height: 10),
      AppButton(
        label: 'Report stolen',
        kind: ButtonKind.dangerOutline,
        icon: Icons.gpp_maybe_outlined,
        onPressed: (!d.isStolen && !d.reportPending) ? () => _go('/devices/${d.id}/report') : null,
      ),
      if (!canTrade && !d.isStolen)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Selling and transfers are unavailable while a listing, transfer or report is active.', style: AppText.bodySm),
        ),
    ];
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record, required this.last});
  final OwnershipRecord record;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final current = record.releasedAt == null;
    final via = {'registration': 'Registered', 'transfer': 'Received by transfer', 'admin_adjustment': 'Admin adjustment'}[record.acquiredVia] ?? record.acquiredVia;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(color: current ? AppColors.green : AppColors.outline, shape: BoxShape.circle),
          ),
          if (!last) Expanded(child: Container(width: 2, color: AppColors.outline)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${record.isYou ? 'You' : record.ownerName}${current ? ' (current owner)' : ''}', style: AppText.labelLg),
              Text('$via • ${formatDate(record.acquiredAt)}${current ? '' : ' → ${formatDate(record.releasedAt)}'}', style: AppText.bodySm),
            ]),
          ),
        ),
      ]),
    );
  }
}
