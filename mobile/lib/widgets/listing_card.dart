import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

/// Marketplace device card: 1:1 image, registry badge, PKR price, city footer.
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, required this.onTap});
  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Photo takes whatever height is left after the text, so the card never overflows.
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            NetImage(listing.coverUrl),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.verified, size: 16, color: AppColors.greenText),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${listing.brand} ${listing.model}', style: AppText.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              [listing.specLine, conditionLabel(listing.condition)].where((s) => s.isNotEmpty).join(' • '),
              style: AppText.bodySm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(formatPkr(listing.price), style: AppText.price.copyWith(fontSize: 16)),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 14, color: AppColors.slate),
              const SizedBox(width: 2),
              Expanded(child: Text(listing.city, style: AppText.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Horizontal row variant for "My listings" style screens.
class ListingRow extends StatelessWidget {
  const ListingRow({super.key, required this.listing, required this.onTap, this.trailing});
  final Listing listing;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(AppRadius.md), child: SizedBox(width: 72, height: 72, child: NetImage(listing.coverUrl, iconSize: 28))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(listing.title, style: AppText.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(formatPkr(listing.price), style: AppText.price.copyWith(fontSize: 15)),
            const SizedBox(height: 6),
            Row(children: [
              statusBadge(listing.status),
              if (listing.pendingRequests > 0) ...[
                const SizedBox(width: 6),
                StatusBadge('${listing.pendingRequests} request${listing.pendingRequests == 1 ? '' : 's'}', kind: BadgeKind.info),
              ],
            ]),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
