import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  late Future<List<StolenReport>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<StolenReport>> _load() async {
    final data = await context.read<ApiClient>().get('/stolen-reports') as Map<String, dynamic>;
    return (data['reports'] as List).map((e) => StolenReport.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'My Stolen Reports'),
      body: AsyncView<List<StolenReport>>(
        future: _future,
        onRetry: () => setState(() => _future = _load()),
        builder: (context, items) {
          if (items.isEmpty) {
            return const EmptyView(
              icon: Icons.verified_user_outlined,
              title: 'No reports',
              message: 'If a registered phone is stolen, open it from My Devices and tap "Report stolen".',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final r = items[i];
              return AppCard(
                accent: switch (r.status) { 'approved' => AppColors.red, 'pending' => AppColors.amber, _ => AppColors.outline },
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(r.deviceName, style: AppText.labelLg)), statusBadge(r.status)]),
                  const SizedBox(height: 4),
                  Text('${formatDate(r.incidentDate)} • ${r.location}', style: AppText.bodySm),
                  Text('Filed ${timeAgo(r.createdAt)}', style: AppText.bodySm),
                  if ((r.reviewNote ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Admin note: ${r.reviewNote}', style: AppText.bodyMd),
                  ],
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
