import 'package:flutter/material.dart';

import '../models/listing.dart';
import '../models/listing_type.dart';
import '../models/rental_plan.dart';

class ListingSummaryCard extends StatelessWidget {
  const ListingSummaryCard({super.key, required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(child: Text(listing.type.title[0])),
        title: Text(listing.title),
        // Area, never the door: this card is fed from the whole listing
        // catalogue, so it can't assume the reader owns what it's showing.
        subtitle: Text(
          '${listing.approximateAddress}\n${listing.displayPrice.toStringAsFixed(0)} BDT / ${listing.cheapestPlan?.displayUnit ?? ''}',
        ),
        isThreeLine: true,
        trailing: Chip(
          label: Text(listing.available ? 'Available' : 'Booked'),
        ),
      ),
    );
  }
}
