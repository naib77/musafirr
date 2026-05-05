import 'package:flutter/material.dart';

import '../models/listing.dart';
import '../models/listing_type.dart';

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
        subtitle: Text(
          '${listing.address}\n${listing.hourlyRate.toStringAsFixed(0)} BDT / hour',
        ),
        isThreeLine: true,
        trailing: Chip(
          label: Text(listing.available ? 'Available' : 'Booked'),
        ),
      ),
    );
  }
}
