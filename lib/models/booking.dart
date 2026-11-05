/// Booking lifecycle:
///
///   pending --approve--> confirmed --complete--> completed
///   pending --reject---> rejected
///   pending/confirmed --student requests cancel--> cancelRequested
///   cancelRequested --instructor approves--> canceled
///   cancelRequested --instructor keeps----> back to previous status
///   pending/confirmed --either party proposes a change--> changeRequested
///   changeRequested --other party accepts--> confirmed or canceled
///   changeRequested --other party declines--> previous status
///
/// "In queue" is not a stored status: the queue position is computed from
/// active bookings (see BookingRepository.queuePosition).
enum BookingStatus {
  pending,
  confirmed,
  cancelRequested,
  changeRequested,
  completed,
  canceled,
  rejected,
}

extension BookingStatusX on BookingStatus {
  String get label => switch (this) {
    BookingStatus.pending => 'Pending',
    BookingStatus.confirmed => 'Confirmed',
    BookingStatus.cancelRequested => 'Cancellation requested',
    BookingStatus.changeRequested => 'Change requested',
    BookingStatus.completed => 'Completed',
    BookingStatus.canceled => 'Canceled',
    BookingStatus.rejected => 'Rejected',
  };

  /// Active bookings still hold a slot and count toward the queue.
  bool get isActive =>
      this == BookingStatus.pending ||
      this == BookingStatus.confirmed ||
      this == BookingStatus.cancelRequested ||
      this == BookingStatus.changeRequested;
}

class Booking {
  Booking({
    required this.id,
    required this.studentId,
    required this.instructorId,
    required this.slotId,
    required this.topic,
    required this.createdAt,
    this.fileName,
    this.status = BookingStatus.pending,
  });

  final String id;
  final String studentId;
  String instructorId;
  String slotId;
  final String topic;
  final String? fileName;
  final DateTime createdAt;
  BookingStatus status;

  /// Remembered so a rejected cancellation can restore the old status.
  BookingStatus statusBeforeCancel = BookingStatus.confirmed;

  String? changeRequestedBy;
  String? changeReason;
  String? proposedSlotId;
  BookingStatus statusBeforeChange = BookingStatus.confirmed;

  bool get changeIsCancellation =>
      status == BookingStatus.changeRequested && proposedSlotId == null;
}
