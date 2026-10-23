import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/listing_card.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  late Future<List<Listing>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Listing>> _load() async {
    final data = await context.read<ApiClient>().get('/listings/mine') as Map<String, dynamic>;
    return (data['listings'] as List).map((e) => Listing.fromJson(e as Map<String, dynamic>)).toList();
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(context, 'My Listings'),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AsyncView<List<Listing>>(
          future: _future,
          onRetry: _reload,
          builder: (context, items) {
            if (items.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 80),
                EmptyView(
                  icon: Icons.storefront_outlined,
                  title: 'No listings yet',
                  message: 'List a registered phone to reach buyers.',
                  action: 'Sell a phone',
                  onAction: () => context.go('/sell'),
                ),
              ]);
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final l in items)
                  ListingRow(
                    listing: l,
                    onTap: () async {
                      await context.push('/listing/${l.id}');
                      _reload();
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
