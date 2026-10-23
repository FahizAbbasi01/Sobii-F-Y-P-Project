import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class PurchaseRequestsScreen extends StatelessWidget {
  const PurchaseRequestsScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Purchase Requests', style: AppText.headlineMd),
          backgroundColor: AppColors.canvas,
          surfaceTintColor: Colors.transparent,
          bottom: TabBar(
            labelColor: AppColors.blue,
            unselectedLabelColor: AppColors.slate,
            indicatorColor: AppColors.blue,
            labelStyle: AppText.labelLg,
            tabs: const [Tab(text: 'Buying'), Tab(text: 'Selling')],
          ),
        ),
        body: const TabBarView(children: [_RequestList(role: 'buyer'), _RequestList(role: 'seller')]),
      ),
    );
  }
}

class _RequestList extends StatefulWidget {
  const _RequestList({required this.role});
  final String role;

  @override
  State<_RequestList> createState() => _RequestListState();
}

class _RequestListState extends State<_RequestList> with AutomaticKeepAliveClientMixin {
  late Future<List<PurchaseRequest>> _future;
  String? _busyId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<PurchaseRequest>> _load() async {
    final data = await context.read<ApiClient>().get('/purchase-requests', query: {'role': widget.role}) as Map<String, dynamic>;
    return (data['requests'] as List).map((e) => PurchaseRequest.fromJson(e as Map<String, dynamic>)).toList();
  }

  void _reload() => setState(() {
      _future = _load();
    });

  Future<void> _act(PurchaseRequest r, String action) async {
    final prompts = {
      'accept': ('Accept this request?', 'The listing becomes reserved and a transfer is created. Ownership only moves after you BOTH confirm in the app.', 'Accept', false),
      'reject': ('Decline this request?', 'The buyer will be notified.', 'Decline', true),
      'cancel': ('Withdraw your request?', 'If the seller already accepted, the pending transfer is cancelled.', 'Withdraw', true),
    };
    final p = prompts[action]!;
    if (!await confirmDialog(context, title: p.$1, message: p.$2, confirm: p.$3, danger: p.$4)) return;
    setState(() => _busyId = r.id);
    try {
      final res = await context.read<ApiClient>().post('/purchase-requests/${r.id}/$action');
      if (!mounted) return;
      if (action == 'accept' && res is Map && res['transferId'] != null) {
        showSnack(context, 'Accepted. Meet the buyer, then confirm the transfer.');
        await context.push('/transfers/${res['transferId']}');
      } else {
        showSnack(context, action == 'reject' ? 'Request declined' : 'Request withdrawn');
      }
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: AsyncView<List<PurchaseRequest>>(
        future: _future,
        onRetry: _reload,
        builder: (context, items) {
          if (items.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 80),
              EmptyView(
                icon: Icons.handshake_outlined,
                title: widget.role == 'buyer' ? 'No requests sent' : 'No requests received',
                message: widget.role == 'buyer' ? 'Find a phone in Explore and tap "Request to Buy".' : 'Buyers\' requests for your listings appear here.',
              ),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _card(items[i]),
          );
        },
      ),
    );
  }

  Widget _card(PurchaseRequest r) {
    final seller = r.role == 'seller';
    final busy = _busyId == r.id;
    return AppCard(
      onTap: () => context.push('/listing/${r.listingId}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(r.deviceName, style: AppText.labelLg)),
          statusBadge(r.status),
        ]),
        const SizedBox(height: 2),
        Text(r.listingTitle, style: AppText.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 10),
        Row(children: [
          Text('Offer ', style: AppText.bodySm),
          Text(formatPkr(r.offerPrice), style: AppText.price.copyWith(fontSize: 16)),
          if (r.offerPrice != r.listingPrice) Text('  (asking ${formatPkr(r.listingPrice)})', style: AppText.bodySm),
        ]),
        const SizedBox(height: 6),
        Text(
          seller ? 'From ${r.buyerName}${r.buyerCity != null ? ' • ${r.buyerCity}' : ''} • ${timeAgo(r.createdAt)}' : 'Seller: ${r.sellerName} • ${timeAgo(r.createdAt)}',
          style: AppText.bodySm,
        ),
        if ((r.message ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.surfaceLow, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Text('"${r.message}"', style: AppText.bodyMd),
          ),
        ],
        if (seller && r.status == 'pending') ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: AppButton(label: 'Decline', kind: ButtonKind.ghost, onPressed: busy ? null : () => _act(r, 'reject'))),
            const SizedBox(width: 8),
            Expanded(child: AppButton(label: 'Accept', icon: Icons.check_rounded, loading: busy, onPressed: () => _act(r, 'accept'))),
          ]),
        ],
        if (!seller && (r.status == 'pending' || r.status == 'accepted')) ...[
          const SizedBox(height: 12),
          AppButton(label: 'Withdraw request', kind: ButtonKind.ghost, loading: busy, onPressed: () => _act(r, 'cancel')),
        ],
        if (r.transferId != null && r.transferStatus == 'pending') ...[
          const SizedBox(height: 8),
          AppButton(
            label: 'Open ownership transfer',
            icon: Icons.swap_horiz_rounded,
            kind: ButtonKind.navy,
            onPressed: () async {
              await context.push('/transfers/${r.transferId}');
              _reload();
            },
          ),
        ],
      ]),
    );
  }
}
