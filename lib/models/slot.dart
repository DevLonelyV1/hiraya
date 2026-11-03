/// A consultation time slot published by an instructor.
///
/// `isLocked` is true while a booking holds the slot (prevents double-booking).
/// `inQueue` is true while that booking is still active (pending, confirmed or
/// cancelRequested). It lets every student compute queue positions without
/// being allowed to read other students' bookings.
class Slot {
  Slot({
    required this.id,
    required this.instructorId,
    required this.start,
    required this.end,
    this.isLocked = false,
    this.inQueue = false,
  });

  final String id;
  final String instructorId;
  DateTime start;
  DateTime end;
  bool isLocked;
  bool inQueue;
}
