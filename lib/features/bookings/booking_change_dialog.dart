import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/booking_repository.dart';
import '../../models/booking.dart';
import '../../models/booking_change_policy.dart';
import '../../state/app_state.dart';

Future<void> showBookingChangeDialog(
  BuildContext context,
  Booking booking,
) async {
  final request = await showDialog<_BookingChangeRequest>(
    context: context,
    builder: (_) => _BookingChangeDialog(booking: booking),
  );
  if (request == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await context.read<AppState>().requestBookingChange(
      bookingId: booking.id,
      reason: request.reason,
      proposedSlotId: request.proposedSlotId,
    );
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Request sent. The other person must approve it.'),
        ),
      );
    }
  } on SlotUnavailableException catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  } on StateError catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  } on FirebaseException catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not send request: ${error.message ?? error.code}',
          ),
        ),
      );
    }
  }
}

Future<void> reviewBookingChangeWithFeedback(
  BuildContext context,
  Booking booking, {
  required bool approve,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await context.read<AppState>().reviewBookingChange(
      booking.id,
      approve: approve,
    );
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Booking change approved.' : 'Booking change declined.',
          ),
        ),
      );
    }
  } on SlotUnavailableException catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  } on StateError catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not review request: ${error.message}')),
      );
    }
  } on FirebaseException catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not review request: ${error.message ?? error.code}',
          ),
        ),
      );
    }
  }
}

class _BookingChangeRequest {
  const _BookingChangeRequest({
    required this.reason,
    required this.proposedSlotId,
  });

  final String reason;
  final String? proposedSlotId;
}

class _BookingChangeDialog extends StatefulWidget {
  const _BookingChangeDialog({required this.booking});

  final Booking booking;

  @override
  State<_BookingChangeDialog> createState() => _BookingChangeDialogState();
}

class _BookingChangeDialogState extends State<_BookingChangeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  bool _cancelInstead = false;
  String? _proposedSlotId;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final currentSlot = state.repo.slotById(widget.booking.slotId);
    final canRequest =
        currentSlot != null && isBeforeBookingChangeCutoff(currentSlot.start);
    final availableSlots = state.repo
        .slotsFor(widget.booking.instructorId, onlyAvailable: true)
        .where((slot) => isBeforeBookingChangeCutoff(slot.start))
        .toList();
    if (_proposedSlotId != null &&
        !availableSlots.any((slot) => slot.id == _proposedSlotId)) {
      _proposedSlotId = null;
    }
    if (_proposedSlotId == null && availableSlots.isNotEmpty) {
      _proposedSlotId = availableSlots.first.id;
    }

    return AlertDialog(
      title: const Text('Request a booking change'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose to cancel or suggest another time. The other person '
                  'must approve before anything changes.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Requests and approvals are available until 3 hours before '
                  'the current appointment.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Reschedule'),
                      icon: Icon(Icons.edit_calendar),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Cancel'),
                      icon: Icon(Icons.event_busy),
                    ),
                  ],
                  selected: {_cancelInstead},
                  onSelectionChanged: canRequest
                      ? (selection) =>
                            setState(() => _cancelInstead = selection.first)
                      : null,
                ),
                if (!_cancelInstead)
                  DropdownButtonFormField<String>(
                    key: ValueKey(_proposedSlotId),
                    initialValue:
                        availableSlots.any((slot) => slot.id == _proposedSlotId)
                        ? _proposedSlotId
                        : null,
                    isExpanded: true,
                    menuMaxHeight: 420,
                    decoration: const InputDecoration(
                      labelText: 'Proposed instructor time',
                    ),
                    items: [
                      for (final slot in availableSlots)
                        DropdownMenuItem(
                          value: slot.id,
                          child: Text(
                            '${fmtDate(slot.start)} · ${fmtRange(slot.start, slot.end)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: canRequest && availableSlots.isNotEmpty
                        ? (value) => setState(() => _proposedSlotId = value)
                        : null,
                    validator: (value) => !_cancelInstead && value == null
                        ? 'Choose an open instructor time.'
                        : null,
                  ),
                TextFormField(
                  controller: _reasonController,
                  maxLength: 300,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    hintText: 'Explain why you need to change the appointment',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => bookingChangeReasonError(value ?? ''),
                ),
                if (!canRequest)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'This appointment is within the 3-hour cutoff. Changes are no longer available.',
                    ),
                  )
                else if (!_cancelInstead && availableSlots.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'There are no open instructor times at least 3 hours from now. You can still request cancellation.',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: canRequest
              ? () {
                  if (!_formKey.currentState!.validate()) return;
                  Navigator.pop(
                    context,
                    _BookingChangeRequest(
                      reason: _reasonController.text.trim(),
                      proposedSlotId: _cancelInstead ? null : _proposedSlotId,
                    ),
                  );
                }
              : null,
          child: const Text('Send for approval'),
        ),
      ],
    );
  }
}
