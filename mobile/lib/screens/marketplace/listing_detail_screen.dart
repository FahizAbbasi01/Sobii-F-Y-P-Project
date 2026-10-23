import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class _Detail {
  final Listing listing;
  final bool isSeller;
  final Map<String, dynamic>? myRequest;
  _Detail(this.listing, this.isSeller, this.myRequest);
}

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  late Future<_Detail> _future;
  int _imageIndex = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load(); // not lazily in build: context.read is not allowed during build
  }

  Future<_Detail> _load() async {
    final data = await context.read<ApiClient>().get('/listings/${widget.id}') as Map<String, dynamic>;
    return _Detail(
      Listing.fromJson(data['listing'] as Map<String, dynamic>),
      data['isSeller'] == true,
      data['myRequest'] as Map<String, dynamic>?,
    );
  }

  void _reload() => setState(() {
      _future = _load();
    });

  Future<void> _requestToBuy(Listing l) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (_) => _RequestSheet(listing: l),
    );
    if (sent == true && mounted) {
      showSnack(context, 'Purchase request sent to the seller');
      _reload();
    }
  }

  Future<void> _cancelRequest(String requestId) async {
    if (!await confirmDialog(context, title: 'Withdraw request?', message: 'The seller will be notified. If they already accepted, the pending transfer is cancelled.', confirm: 'Withdraw', danger: true)) return;
    await _run(() => context.read<ApiClient>().post('/purchase-requests/$requestId/cancel'), 'Request withdrawn');
  }

  Future<void> _withdraw(Listing l) async {
    if (!await confirmDialog(context, title: 'Withdraw listing?', message: 'It will be hidden from the marketplace and open requests will be declined.', confirm: 'Withdraw', danger: true)) return;
    await _run(() => context.read<ApiClient>().post('/listings/${l.id}/withdraw'), 'Listing withdrawn');
  }

  Future<void> _run(Future<dynamic> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showSnack(context, success);
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'Phone details'),
      body: FutureBuilder<_Detail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          final d = snap.data!;
          final l = d.listing;
          return Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                _gallery(l),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      statusBadge(l.registryStatus),
                      StatusBadge(conditionLabel(l.condition), kind: BadgeKind.info),
                      if (l.status != 'active') statusBadge(l.status),
                    ]),
                    const SizedBox(height: 10),
                    Text(l.title, style: AppText.headlineLg),
                    const SizedBox(height: 4),
                    Text('${l.brand} ${l.model}${l.specLine.isEmpty ? '' : ' • ${l.specLine}'}', style: AppText.bodyMd),
                    const SizedBox(height: 12),
                    Text(formatPkr(l.price), style: AppText.price.copyWith(fontSize: 26)),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.location_on_outlined, size: 16, color: AppColors.slate),
                      const SizedBox(width: 4),
                      Text('${l.city} • listed ${timeAgo(l.createdAt)}', style: AppText.bodySm),
                    ]),
                    const SizedBox(height: 16),
                    AppCard(
                      accent: l.registryStatus == 'registered' ? AppColors.green : AppColors.red,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.verified_user_rounded, color: AppColors.greenText, size: 20),
                          const SizedBox(width: 8),
                          Text('Registry record', style: AppText.labelLg),
                        ]),
                        const SizedBox(height: 12),
                        _kv('IMEI (last 4)', l.imeiLast4 == null ? '—' : '•••• •••• •••• ${l.imeiLast4}', mono: true),
                        _kv('Registry status', l.registryStatus == 'registered' ? 'Registered to seller' : 'Reported stolen'),
                        _kv('Recorded owners', '${l.ownerCount}'),
                        const SizedBox(height: 8),
                        const PtaDisclaimer(
                          text: 'This is DeviceTrust\'s internal ownership registry, not PTA tax/DIRBS status. '
                              'Before paying, check the full IMEI on the phone (*#06#) matches, and verify PTA status by SMS to 8484.',
                        ),
                      ]),
                    ),
                    if ((l.description ?? '').isNotEmpty) ...[
                      const SectionHeader('Description'),
                      Text(l.description!, style: AppText.bodyLg.copyWith(color: AppColors.slate)),
                    ],
                    const SectionHeader('Seller'),
                    AppCard(
                      child: Row(children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.navy,
                          child: Text(l.sellerName.isEmpty ? '?' : l.sellerName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(l.sellerName, style: AppText.labelLg),
                            Text(
                              '${l.sellerCity ?? 'Pakistan'} • member since ${formatDate(l.sellerSince)} • ${l.sellerSoldCount} sold',
                              style: AppText.bodySm,
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
            _actionBar(d),
          ]);
        },
      ),
    );
  }

  Widget _gallery(Listing l) {
    if (l.images.isEmpty) return const AspectRatio(aspectRatio: 1.2, child: NetImage(null, iconSize: 72));
    return AspectRatio(
      aspectRatio: 1.1,
      child: Stack(children: [
        PageView.builder(
          itemCount: l.images.length,
          onPageChanged: (i) => setState(() => _imageIndex = i),
          itemBuilder: (_, i) => NetImage(l.images[i].url, fit: BoxFit.cover),
        ),
        if (l.images.length > 1)
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0x99000D23), borderRadius: BorderRadius.circular(999)),
              child: Text('${_imageIndex + 1}/${l.images.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
      ]),
    );
  }

  Widget _kv(String k, String v, {bool mono = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 120, child: Text(k, style: AppText.bodySm)),
          Expanded(child: Text(v, style: mono ? AppText.monoImei.copyWith(fontSize: 14) : AppText.labelLg)),
        ]),
      );

  Widget _actionBar(_Detail d) {
    final l = d.listing;
    final req = d.myRequest;
    Widget content;
    if (d.isSeller) {
      content = Row(children: [
        if (l.status == 'active')
          Expanded(child: AppButton(label: 'Edit', kind: ButtonKind.ghost, icon: Icons.edit_outlined, onPressed: () async {
            await context.push('/listings/${l.id}/edit');
            _reload();
          })),
        if (l.status == 'active') const SizedBox(width: 8),
        Expanded(
          child: AppButton(
            label: 'View requests',
            icon: Icons.handshake_outlined,
            onPressed: () => context.push('/requests?tab=selling'),
          ),
        ),
        if (l.status == 'active') ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Withdraw listing',
            onPressed: _busy ? null : () => _withdraw(l),
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.redText),
          ),
        ],
      ]);
    } else if (req != null && (req['status'] == 'pending' || req['status'] == 'accepted')) {
      final accepted = req['status'] == 'accepted';
      content = Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          statusBadge(req['status'] as String),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              accepted ? 'Seller accepted — meet, inspect, then confirm the transfer.' : 'Your offer of ${formatPkr(req['offerPrice'] as num?)} is with the seller.',
              style: AppText.bodySm,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: AppButton(label: 'Withdraw', kind: ButtonKind.ghost, loading: _busy, onPressed: () => _cancelRequest(req['id'] as String))),
          const SizedBox(width: 8),
          Expanded(child: AppButton(label: accepted ? 'Open transfer' : 'My requests', onPressed: () => context.push(accepted ? '/transfers' : '/requests'))),
        ]),
      ]);
    } else if (l.status == 'active' && l.registryStatus == 'registered') {
      content = AppButton(label: 'Request to Buy', icon: Icons.shopping_bag_outlined, kind: ButtonKind.navy, onPressed: () => _requestToBuy(l));
    } else {
      content = Text('This listing is not available for purchase.', style: AppText.bodyMd, textAlign: TextAlign.center);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.hairline))),
      child: SafeArea(top: false, child: content),
    );
  }
}

class _RequestSheet extends StatefulWidget {
  const _RequestSheet({required this.listing});
  final Listing listing;

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  late final _offer = TextEditingController(text: widget.listing.price.round().toString());
  final _message = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;

  @override
  void dispose() {
    _offer.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post('/purchase-requests', {
        'listingId': widget.listing.id,
        'offerPrice': int.parse(_offer.text),
        if (_message.text.trim().isNotEmpty) 'message': _message.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Request to buy', style: AppText.headlineLg),
              const SizedBox(height: 4),
              Text('Asking price: ${formatPkr(widget.listing.price)}. The seller will see your offer and message.', style: AppText.bodyMd),
              const SizedBox(height: 16),
              AppField(
                label: 'Your offer (PKR)',
                controller: _offer,
                icon: Icons.payments_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter a valid amount' : null,
              ),
              AppField(label: 'Message (optional)', controller: _message, hint: 'When and where can we meet?', maxLines: 3, maxLength: 500),
              AppButton(label: 'Send request', icon: Icons.send_rounded, loading: _busy, onPressed: _send),
              const SizedBox(height: 8),
              Text('No money is handled by DeviceTrust. Pay only after inspecting the phone in person.', style: AppText.bodySm),
            ]),
          ),
        ),
      ),
    );
  }
}
