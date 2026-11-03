// OWNER: Person 5 (Instructor)
// Use cases: "Review request" (approve/reject), review cancellation requests,
// mark sessions completed, instructor-side cancel.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../models/booking.dart';
import '../../state/app_state.dart';

class ReviewRequestsScreen extends StatelessWidget {
  const ReviewRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final all = state.repo.bookingsForInstructor(state.me.id);
    final pending =
        all.where((b) => b.status == BookingStatus.pending).toList();
    final cancels =
        all.where((b) => b.status == BookingStatus.cancelRequested).toList();
    final confirmed =
        all.where((b) => b.status == BookingStatus.confirmed).toList();

    if (pending.isEmpty && cancels.isEmpty && confirmed.isEmpty) {
      return const EmptyState(
        icon: Icons.inbox,
        message: 'No requests yet.\nStudents will appear here once they book.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pending.isNotEmpty) ...[
          const SectionHeader('Pending requests'),
          ...pending.map((b) => _RequestCard(booking: b)),
        ],
        if (cancels.isNotEmpty) ...[
          const SectionHeader('Cancellation requests'),
          ...cancels.map((b) => _RequestCard(booking: b)),
        ],
        if (confirmed.isNotEmpty) ...[
          const SectionHeader('Confirmed sessions'),
          ...confirmed.map((b) => _RequestCard(booking: b)),
        ],
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.booking});

  final Booking booking;

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runAction(
    BuildContext context,
    Future<void> action,
    String successMessage,
  ) async {
    try {
      await action;
      if (context.mounted) _toast(context, successMessage);
    } on StateError catch (e) {
      if (context.mounted) _toast(context, e.message);
    } on Exception catch (e) {
      if (context.mounted) _toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final repo = state.repo;
    final slot = repo.slotById(booking.slotId);
    final student = repo.userById(booking.studentId);
    final theme = Theme.of(context);

    final List<Widget> actions = switch (booking.status) {
      BookingStatus.pending => [
          OutlinedButton(
            onPressed: () => _runAction(
              context,
              state.reviewRequest(booking.id, approve: false),
              'Request rejected. Student notified.',
            ),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => _runAction(
              context,
              state.reviewRequest(booking.id, approve: true),
              'Request approved. Student notified.',
            ),
            child: const Text('Approve'),
          ),
        ],
      BookingStatus.cancelRequested => [
          OutlinedButton(
            onPressed: () => _runAction(
              context,
              state.reviewCancellation(booking.id, approve: false),
              'Booking kept. Student notified.',
            ),
            child: const Text('Keep booking'),
          ),
          FilledButton(
            onPressed: () => _runAction(
              context,
              state.reviewCancellation(booking.id, approve: true),
              'Cancellation approved. Student notified.',
            ),
            child: const Text('Approve cancellation'),
          ),
        ],
      BookingStatus.confirmed => [
          OutlinedButton(
            onPressed: () => _runAction(
              context,
              state.cancelByInstructor(booking.id),
              'Booking canceled. Student notified.',
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _runAction(
              context,
              state.markCompleted(booking.id),
              'Marked as completed.',
            ),
            child: const Text('Mark completed'),
          ),
        ],
      _ => <Widget>[],
    };

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
                    student?.name ?? 'Student',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                StatusChip(booking.status),
              ],
            ),
            const SizedBox(height: 8),
            if (slot != null)
              Text('${fmtDate(slot.start)} · ${fmtRange(slot.start, slot.end)}'),
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
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
