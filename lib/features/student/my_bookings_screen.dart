// OWNER: Person 4 (Student bookings)
// Use cases: "Reschedule booking", "Request cancellation", "Track queue position".

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../models/booking.dart';
import '../../state/app_state.dart';
import 'instructor_slots_screen.dart';

class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final bookings = state.repo.bookingsForStudent(state.me.id);

    if (bookings.isEmpty) {
      return const EmptyState(
        icon: Icons.event_busy,
        message: 'No bookings yet.\nFind a slot in the Find tab.',
      );
    }

    final active = bookings.where((b) => b.status.isActive).toList();
    final history = bookings.where((b) => !b.status.isActive).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (active.isNotEmpty) ...[
          const SectionHeader('Upcoming'),
          ...active.map((b) => _BookingCard(booking: b)),
        ],
        if (history.isNotEmpty) ...[
          const SectionHeader('History'),
          ...history.map((b) => _BookingCard(booking: b)),
        ],
      ],
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final repo = state.repo;
    final slot = repo.slotById(booking.slotId);
    final instructor = repo.userById(booking.instructorId);
    final position = repo.queuePosition(booking.id);
    final canModify =
        booking.status == BookingStatus.pending || booking.status == BookingStatus.confirmed;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    instructor?.name ?? 'Instructor',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                StatusChip(booking.status),
              ],
            ),
            const SizedBox(height: 8),
            if (slot != null) Text('${fmtDate(slot.start)} · ${fmtRange(slot.start, slot.end)}'),
            const SizedBox(height: 4),
            Text('Topic: ${booking.topic}'),
            if (booking.fileName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 16),
                    const SizedBox(width: 4),
                    Text(booking.fileName!),
                  ],
                ),
              ),
            if (position > 0) ...[
              const SizedBox(height: 8),
              ActionChip(
                avatar: const Icon(Icons.format_list_numbered, size: 18),
                label: Text('Queue position #$position'),
                onPressed: () => _showQueue(context),
              ),
            ],
            if (booking.status == BookingStatus.cancelRequested)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Waiting for the instructor to review your cancellation.'),
              ),
            if (canModify)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: instructor == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => InstructorSlotsScreen(
                                  instructor: instructor,
                                  rescheduleBookingId: booking.id,
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.edit_calendar),
                      label: const Text('Reschedule'),
                    ),
                    TextButton.icon(
                      onPressed: () => _confirmCancel(context),
                      style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Request cancellation'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request cancellation?'),
        content: const Text(
          'Your instructor will review the request before the booking is canceled.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep booking')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    context.read<AppState>().requestCancellation(booking.id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Cancellation request sent.')));
  }

  void _showQueue(BuildContext context) {
    final repo = context.read<AppState>().repo;
    final slot = repo.slotById(booking.slotId);
    if (slot == null) return;
    final queue = repo.queueFor(booking.instructorId, slot.start);
    final instructorName = repo.userById(booking.instructorId)?.name ?? 'Instructor';

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader('$instructorName - queue for ${fmtDate(slot.start)}'),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < queue.length; i++)
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                        title: Text(
                          queue[i].id == booking.id ? 'You' : 'Another student',
                          style: TextStyle(
                            fontWeight: queue[i].id == booking.id
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(fmtTime(repo.slotById(queue[i].id)!.start)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
