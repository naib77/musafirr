import 'package:flutter/material.dart';

import '../repositories/musafir_repository.dart';
import '../widgets/info_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/section_title.dart';
import 'admin/verification_review_screen.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key, required this.repository});

  final MusafirRepository repository;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(
          title: 'Platform Overview',
          subtitle: 'Admin can review inventory, owners, and bookings.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            MetricCard(
              label: 'Total Listings',
              value: '${repository.listings.length}',
              icon: Icons.home_work_outlined,
            ),
            MetricCard(
              label: 'Available',
              value: '${repository.availableCount}',
              icon: Icons.check_circle_outline,
            ),
            MetricCard(
              label: 'Owners',
              value: '${repository.ownerCount}',
              icon: Icons.person_outline,
            ),
            MetricCard(
              label: 'Bookings',
              value: '${repository.bookings.length}',
              icon: Icons.calendar_month_outlined,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Verifications section
        const SectionTitle(
          title: 'Identity Verification',
          subtitle: 'Review pending owner verification requests.',
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.verified_user_outlined),
            ),
            title: const Text('Pending Verifications'),
            subtitle: const Text('Review and approve owner documents'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const VerificationReviewScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        const SectionTitle(
          title: 'Recent Bookings',
          subtitle:
              'In-memory data for now. Replace the repository later with a real backend.',
        ),
        const SizedBox(height: 12),
        if (repository.bookings.isEmpty)
          const InfoCard(
            message: 'No bookings yet. Tenant bookings will appear here.',
          )
        else
          ...repository.bookings.reversed.map(
            (booking) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                child: Icon(Icons.receipt_long_outlined),
              ),
              title: Text(
                '${booking.tenantName} booked ${booking.listingId}',
              ),
              subtitle: Text(
                '${booking.totalPrice.toStringAsFixed(0)} BDT for ${booking.unitLabel} booking',
              ),
            ),
          ),
      ],
    );
  }
}
