import 'package:flutter/material.dart';

import '../models/listing.dart';
import '../models/listing_type.dart';
import '../models/rental_plan.dart';

class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.listing,
    required this.onBook,
  });

  final Listing listing;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    listing.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text(listing.type.title)),
              ],
            ),
            const SizedBox(height: 6),
            Text(listing.address),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: listing.facilities
                  .map(
                    (facility) => Chip(
                      avatar: Icon(facility.icon, size: 16),
                      label: Text(facility.name),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text(
              'Rates: ${listing.offeredPlans.map((p) => '${listing.rateFor(p)!.toStringAsFixed(0)} / ${p.displayUnit}').join(', ')}',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: listing.available ? onBook : null,
              child: const Text('Book Now'),
            ),
          ],
        ),
      ),
    );
  }
}
