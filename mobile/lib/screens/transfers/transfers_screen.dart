import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  late Future<List<Transfer>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Transfer>> _load() async {
    final data = await context.read<ApiClient>().get('/transfers') as Map<String, dynamic>;
    return (data['transfers'] as List).map((e) => Transfer.fromJson(e as Map<String, dynamic>)).toList();
  }

  void _reload() => setState(() {
      _future = _load();
    });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'Ownership Transfers'),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AsyncView<List<Transfer>>(
          future: _future,
          onRetry: _reload,
          builder: (context, items) {
            if (items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                EmptyView(
                  icon: Icons.swap_horiz_rounded,
                  title: 'No transfers yet',
                  message: 'Transfers appear here when a sale is accepted or you send a phone to someone directly.',
                ),
              ]);
            }
            final active = items.where((t) => t.status == 'pending' || t.status == 'disputed').toList();
            final past = items.where((t) => !(t.status == 'pending' || t.status == 'disputed')).toList();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              if (active.isNotEmpty) ...[const SectionHeader('Needs attention'), ...active.map(_tile)],
              if (past.isNotEmpty) ...[const SectionHeader('History'), ...past.map(_tile)],
            ]);
          },
        ),
      ),
    );
  }

  Widget _tile(Transfer t) {
    final needsYou = t.status == 'pending' && !t.youConfirmed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        accent: needsYou ? AppColors.amber : null,
        onTap: () async {
          await context.push('/transfers/${t.id}');
          _reload();
        },
        child: Row(children: [
          Icon(t.isSender ? Icons.north_east_rounded : Icons.south_west_rounded, color: t.isSender ? AppColors.blue : AppColors.greenText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.deviceName, style: AppText.labelLg),
              Text(t.isSender ? 'To ${t.toName}' : 'From ${t.fromName}', style: AppText.bodySm),
              Text(formatDate(t.createdAt), style: AppText.bodySm),
              if (needsYou) ...[
                const SizedBox(height: 6),
                const StatusBadge('Your confirmation needed', kind: BadgeKind.warning, icon: Icons.touch_app_outlined),
              ],
            ]),
          ),
          statusBadge(t.status),
        ]),
      ),
    );
  }
}
