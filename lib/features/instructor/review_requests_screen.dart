// OWNER: Person 5 (Instructor)
// Use cases: "Review request" (approve/reject), review cancellation requests,
// mark sessions completed, instructor-side cancel.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../models/booking.dart';
import '../../state/app_state.dart';
import '../bookings/booking_change_dialog.dart';

class ReviewRequestsScreen extends StatelessWidget {
  const ReviewRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final all = state.repo.bookingsForInstructor(state.me.id);
    final pending = all
        .where((b) => b.status == BookingStatus.pending)
        .toList();
    final cancels = all
        .where((b) => b.status == BookingStatus.cancelRequested)
        .toList();
    final changes = all
        .where((b) => b.status == BookingStatus.changeRequested)
        .toList();
    final confirmed = all
        .where((b) => b.status == BookingStatus.confirmed)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InstructorOverview(
          name: state.me.name,
          pending: pending.length,
          cancellations: cancels.length + changes.length,
          confirmed: confirmed.length,
        ),
        if (pending.isEmpty &&
            cancels.isEmpty &&
            changes.isEmpty &&
            confirmed.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 28),
            child: EmptyState(
              icon: Icons.inbox,
              message:
                  'No requests yet.\nStudents will appear here once they book.',
            ),
          ),
        if (pending.isNotEmpty) ...[
          const SectionHeader('Pending requests'),
          ...pending.map((b) => _RequestCard(booking: b)),
        ],
        if (cancels.isNotEmpty) ...[
          const SectionHeader('Cancellation requests'),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Approving a cancellation ends the booking and releases its slot '
                'for another student. Keeping it restores the booking to its '
                'previous status and leaves the slot reserved.',
              ),
            ),
          ),
          ...cancels.map((b) => _RequestCard(booking: b)),
        ],
        if (changes.isNotEmpty) ...[
          const SectionHeader('Mutual change requests'),
          ...changes.map((b) => _RequestCard(booking: b)),
        ],
        if (confirmed.isNotEmpty) ...[
          const SectionHeader('Confirmed sessions'),
          ...confirmed.map((b) => _RequestCard(booking: b)),
        ],
      ],
    );
  }
}

class _InstructorOverview extends StatelessWidget {
  const _InstructorOverview({
    required this.name,
    required this.pending,
    required this.cancellations,
    required this.confirmed,
  });

  final String name;
  final int pending;
  final int cancellations;
  final int confirmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Instructor overview',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Welcome, $name',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Text(
                    _initials(name),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _OverviewCount(label: 'Pending', count: pending),
                _OverviewCount(label: 'Changes', count: cancellations),
                _OverviewCount(label: 'Confirmed', count: confirmed),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String value) {
    final parts = value.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts.isEmpty ? '?' : parts.first[0].toUpperCase();
  }
}

class _OverviewCount extends StatelessWidget {
  const _OverviewCount({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({required this.booking});

  final Booking booking;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() => _busy = true);
    try {
      await action();
      if (context.mounted) _toast(context, successMessage);
    } on FirebaseException catch (error) {
      if (context.mounted) _toast(context, 'Could not update request: $error');
    } on StateError catch (error) {
      if (context.mounted) _toast(context, 'Could not update request: $error');
    } on Exception catch (error) {
      if (context.mounted) _toast(context, 'Could not update request: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmCancellation(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final repo = state.repo;
    final booking = widget.booking;
    final slot = repo.slotById(booking.slotId);
    final student = repo.userById(booking.studentId);
    final theme = Theme.of(context);

    final List<Widget> actions = switch (booking.status) {
      BookingStatus.pending => [
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(
                  context,
                  () => state.reviewRequest(booking.id, approve: false),
                  'Request rejected. Student notified.',
                ),
          child: const Text('Reject'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  context,
                  () => state.reviewRequest(booking.id, approve: true),
                  'Request approved. Student notified.',
                ),
          child: const Text('Approve'),
        ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => showBookingChangeDialog(context, booking),
          icon: const Icon(Icons.edit_calendar),
          label: const Text('Request change'),
        ),
      ],
      BookingStatus.cancelRequested => [
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(
                  context,
                  () => state.reviewCancellation(booking.id, approve: false),
                  'Booking kept. Student notified.',
                ),
          child: const Text('Keep booking'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  if (await _confirmCancellation(
                        context,
                        title: 'Approve cancellation?',
                        message:
                            'This will cancel the booking and make its '
                            'time slot available for another student.',
                        confirmLabel: 'Approve cancellation',
                      ) &&
                      context.mounted) {
                    await _run(
                      context,
                      () => state.reviewCancellation(booking.id, approve: true),
                      'Cancellation approved. Slot is available again.',
                    );
                  }
                },
          child: const Text('Approve cancellation'),
        ),
      ],
      BookingStatus.changeRequested =>
        booking.changeRequestedBy == state.me.id
            ? <Widget>[const Chip(label: Text('Waiting for the student'))]
            : [
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => reviewBookingChangeWithFeedback(
                          context,
                          booking,
                          approve: false,
                        ),
                  child: Text(
                    booking.changeIsCancellation
                        ? 'Decline cancellation'
                        : 'Decline new time',
                  ),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => reviewBookingChangeWithFeedback(
                          context,
                          booking,
                          approve: true,
                        ),
                  child: Text(
                    booking.changeIsCancellation
                        ? 'Approve cancellation'
                        : 'Approve new time',
                  ),
                ),
              ],
      BookingStatus.confirmed => [
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => showBookingChangeDialog(context, booking),
          icon: const Icon(Icons.edit_calendar),
          label: const Text('Request change'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  context,
                  () => state.markCompleted(booking.id),
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
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                StatusChip(booking.status),
              ],
            ),
            const SizedBox(height: 8),
            if (slot != null)
              Text(
                '${fmtDate(slot.start)} · ${fmtRange(slot.start, slot.end)}',
              ),
            const SizedBox(height: 4),
            Text('Topic: ${booking.topic}'),
            if (booking.status == BookingStatus.cancelRequested)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Previously ${booking.statusBeforeCancel.label.toLowerCase()} · '
                  'slot remains reserved until you decide.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (booking.status == BookingStatus.changeRequested)
              _InstructorChangeDetails(booking: booking),
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
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

class _InstructorChangeDetails extends StatelessWidget {
  const _InstructorChangeDetails({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    final proposedSlot = booking.proposedSlotId == null
        ? null
        : repo.slotById(booking.proposedSlotId!);
    final requester = repo.userById(booking.changeRequestedBy ?? '');
    final proposal = booking.changeIsCancellation
        ? 'requests cancellation'
        : 'suggests ${proposedSlot == null ? 'a new time' : fmtDateTime(proposedSlot.start)}';
    final waitingForStudent = booking.changeRequestedBy == booking.instructorId;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        '${requester?.name ?? 'Participant'} $proposal.\n'
        'Reason: ${booking.changeReason ?? 'No reason provided.'}'
        '${waitingForStudent ? '\nWaiting for the student to approve. The current appointment remains active until then.' : ''}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
