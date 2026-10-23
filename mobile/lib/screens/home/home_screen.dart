import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_state.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/listing_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeData {
  final List<Listing> latest;
  final List<Map<String, dynamic>> brands;
  _HomeData(this.latest, this.brands);
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _future;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final api = context.read<ApiClient>();
    final auth = context.read<AuthState>();
    final results = await Future.wait([
      api.get('/listings', query: {'limit': 6, 'sort': 'newest'}),
      api.get('/listings/brands'),
    ]);
    auth.refreshMe().catchError((_) {});
    final listings = ((results[0] as Map)['listings'] as List).map((e) => Listing.fromJson(e as Map<String, dynamic>)).toList();
    final brands = ((results[1] as Map)['brands'] as List).cast<Map<String, dynamic>>();
    return _HomeData(listings, brands);
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() {
      _future = f;
    });
    await f;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.user;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // Header: location + notifications
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Salam, ${user?.fullName.split(' ').first ?? ''}', style: AppText.bodyMd),
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.location_on, size: 16, color: AppColors.blue),
                      const SizedBox(width: 4),
                      Text('${user?.city ?? 'Pakistan'}, PK', style: AppText.labelLg),
                    ]),
                  ]),
                ),
                _BellButton(count: auth.unreadNotifications),
              ]),
              const SizedBox(height: 20),
              Text('Find Your Next Phone', style: AppText.headlineXl),
              const SizedBox(height: 4),
              Text('Registered devices, real ownership history.', style: AppText.bodyMd),
              if (Provider.of<ApiClient>(context, listen: false).isDemo) ...[const SizedBox(height: 12), const DemoBanner()],
              const SizedBox(height: 16),
              // Search
              Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.md), boxShadow: AppShadows.raised),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (q) => context.go('/explore?q=${Uri.encodeQueryComponent(q.trim())}'),
                  decoration: fieldDecoration(
                    hint: 'Search iPhone, Galaxy, Redmi…',
                    icon: Icons.search_rounded,
                    suffix: IconButton(
                      tooltip: 'Scan IMEI',
                      icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.blue),
                      onPressed: () => context.go('/check'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Verify banner
              _VerifyBanner(onTap: () => context.go('/check')),
              // Quick actions
              const SizedBox(height: 20),
              Row(children: [
                _QuickAction(icon: Icons.phone_android_rounded, label: 'My devices', badge: auth.deviceCount, onTap: () => context.push('/devices')),
                _QuickAction(icon: Icons.handshake_outlined, label: 'Requests', onTap: () => context.push('/requests')),
                _QuickAction(icon: Icons.swap_horiz_rounded, label: 'Transfers', onTap: () => context.push('/transfers')),
                _QuickAction(icon: Icons.gpp_maybe_outlined, label: 'Report', color: AppColors.redText, onTap: () => context.push('/devices')),
              ]),
              FutureBuilder<_HomeData>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const LoadingView();
                  if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _refresh);
                  final data = snap.data!;
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (data.brands.isNotEmpty) ...[
                      SectionHeader('Top Brands', action: 'View All', onAction: () => context.go('/explore')),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: data.brands.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final b = data.brands[i];
                            return ActionChip(
                              avatar: const Icon(Icons.smartphone_rounded, size: 16, color: AppColors.navy),
                              label: Text('${b['name']} (${b['count']})'),
                              backgroundColor: AppColors.surface,
                              side: const BorderSide(color: AppColors.outline),
                              shape: const StadiumBorder(),
                              onPressed: () => context.go('/explore?brand=${Uri.encodeQueryComponent(b['name'] as String)}'),
                            );
                          },
                        ),
                      ),
                    ],
                    // Sell CTA
                    const SizedBox(height: 20),
                    AppCard(
                      onTap: () => context.go('/sell'),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.blueBg, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.sell_rounded, color: AppColors.blue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Sell Your Phone', style: AppText.labelLg),
                            const SizedBox(height: 2),
                            Text('Register its IMEI, list it, and transfer ownership in-app.', style: AppText.bodySm),
                          ]),
                        ),
                        const Icon(Icons.arrow_forward_rounded, color: AppColors.blue),
                      ]),
                    ),
                    SectionHeader('Latest Registered Phones', action: 'See all', onAction: () => context.go('/explore')),
                    if (data.latest.isEmpty)
                      const EmptyView(
                        icon: Icons.storefront_outlined,
                        title: 'No listings yet',
                        message: 'Be the first to list a registered phone in the marketplace.',
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: data.latest.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: 292,
                        ),
                        itemBuilder: (_, i) => ListingCard(listing: data.latest[i], onTap: () => context.push('/listing/${data.latest[i].id}')),
                      ),
                    const SizedBox(height: 24),
                    const _WhyCard(),
                  ]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, border: Border.all(color: AppColors.hairline), boxShadow: AppShadows.card),
        child: IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none_rounded, color: AppColors.navy),
          onPressed: () => context.push('/notifications'),
        ),
      ),
      if (count > 0)
        Positioned(
          right: 2,
          top: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(999)),
            child: Text(count > 9 ? '9+' : '$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ),
    ]);
  }
}

class _VerifyBanner extends StatelessWidget {
  const _VerifyBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.navy, Color(0xFF1B3A66)]),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.shield_rounded, color: Color(0xFF6E9BFF), size: 18),
          const SizedBox(width: 6),
          Text('DEVICETRUST REGISTRY', style: AppText.labelSm.copyWith(color: const Color(0xFFB5C7EB))),
        ]),
        const SizedBox(height: 8),
        Text('Verify Before You Buy', style: AppText.headlineLg.copyWith(color: Colors.white)),
        const SizedBox(height: 4),
        Text('Check if an IMEI is registered or reported stolen in our registry.', style: AppText.bodyMd.copyWith(color: const Color(0xFFB5C7EB))),
        const SizedBox(height: 14),
        AppButton(label: 'Check IMEI Now', icon: Icons.manage_search_rounded, onPressed: onTap, expand: false),
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap, this.badge = 0, this.color = AppColors.navy});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.hairline), boxShadow: AppShadows.card),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 6),
            Text(label, style: AppText.labelMd),
          ]),
        ),
      ),
    );
  }
}

class _WhyCard extends StatelessWidget {
  const _WhyCard();

  @override
  Widget build(BuildContext context) {
    Widget row(IconData i, String t, String s) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, color: AppColors.blue, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: AppText.labelLg),
                const SizedBox(height: 2),
                Text(s, style: AppText.bodySm),
              ]),
            ),
          ]),
        );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Why DeviceTrust?', style: AppText.headlineMd),
        row(Icons.fingerprint_rounded, 'One IMEI, one owner', 'An IMEI can only be registered once, so duplicate or cloned listings are blocked.'),
        row(Icons.security_rounded, 'Stolen reports, reviewed', 'Owners can report theft; once approved, the device can\'t be listed or transferred.'),
        row(Icons.handshake_rounded, 'Two-sided handoff', 'Ownership changes only when both buyer and seller confirm, with a permanent history.'),
      ]),
    );
  }
}
