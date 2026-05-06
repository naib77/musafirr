import 'package:flutter/material.dart';

import '../models/listing.dart';
import '../models/listing_type.dart';

class AreaMapPreview extends StatelessWidget {
  const AreaMapPreview({
    super.key,
    required this.centerLat,
    required this.centerLng,
    required this.listings,
  });

  final double centerLat;
  final double centerLng;
  final List<Listing> listings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFDFF5F2), Color(0xFFF5FBFA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: GridPainter(),
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            child: Text(
              'Map area around ${centerLat.toStringAsFixed(3)}, '
              '${centerLng.toStringAsFixed(3)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ...listings.map((listing) {
            final left = ((listing.longitude - centerLng + 0.12) / 0.24)
                .clamp(0.08, 0.88);
            final top = ((listing.latitude - centerLat + 0.12) / 0.24)
                .clamp(0.12, 0.82);
            return Positioned(
              left: left * 300,
              top: (1 - top) * 180,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0B7285),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      listing.type.title,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x330B7285)
      ..strokeWidth = 1;

    for (var i = 1; i < 6; i++) {
      final dx = size.width / 6 * i;
      final dy = size.height / 6 * i;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
