import 'package:flutter/material.dart';

import '../models/booking.dart';

/// Shared widgets used by every feature. Owner: Person 1 (Lead).

MaterialColor statusColor(BookingStatus s) => switch (s) {
  BookingStatus.pending => Colors.orange,
  BookingStatus.confirmed => Colors.green,
  BookingStatus.cancelRequested => Colors.deepOrange,
  BookingStatus.changeRequested => Colors.deepOrange,
  BookingStatus.completed => Colors.blueGrey,
  BookingStatus.canceled => Colors.red,
  BookingStatus.rejected => Colors.red,
};

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.shade200),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: c.shade800,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
