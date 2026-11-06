import 'dart:async';

import '../core/format.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/booking.dart';
import '../models/booking_change_policy.dart';
import '../models/instructor_availability.dart';
import '../models/slot.dart';
import 'booking_repository.dart';

/// In-memory implementation with demo data. Resets when the app restarts.
class InMemoryBookingRepository implements BookingRepository {
  InMemoryBookingRepository() {
    _seed();
  }

  static const _password = 'demo123';
  static const _logins = {
    'ana@demo.test': 's1',
    'ben@demo.test': 's2',
    'carla@demo.test': 's3',
    'reyes@demo.test': 'i1',
    'santos@demo.test': 'i2',
    'delacruz@demo.test': 'i3',
  };

  final List<AppUser> _users = const [
    AppUser(
      id: 's1',
      name: 'Ana Villanueva',
      role: UserRole.student,
      department: 'BS Information Technology',
    ),
    AppUser(
      id: 's2',
      name: 'Ben Ramos',
      role: UserRole.student,
      department: 'BS Information Technology',
    ),
    AppUser(
      id: 's3',
      name: 'Carla Mendoza',
      role: UserRole.student,
      department: 'BS Information Technology',
    ),
    AppUser(
      id: 'i1',
      name: 'Prof. Reyes',
      role: UserRole.instructor,
      department: 'IT Department',
    ),
    AppUser(
      id: 'i2',
      name: 'Prof. Santos',
      role: UserRole.instructor,
      department: 'IT Department',
    ),
    AppUser(
      id: 'i3',
      name: 'Prof. Dela Cruz',
      role: UserRole.instructor,
      department: 'IT Department',
    ),
  ];

  final List<Slot> _slots = [];
  final List<Booking> _bookings = [];
  final List<AppNotification> _notifications = [];
  final Map<String, InstructorAvailability> _availability = {};
  final _changes = StreamController<void>.broadcast();
  AppUser? _current;
  int _idCounter = 100;

  String _nextId(String prefix) => '$prefix${_idCounter++}';

  // ---------------------------------------------------------------- auth

  @override
  Stream<void> get changes => _changes.stream;

  @override
  String? get loginHint =>
      'Demo logins (password: $_password):\n${_logins.keys.join(', ')}';

  @override
  Future<AppUser?> restoreSession() async => _current;

  @override
  Future<AppUser> signIn(String email, String password) async {
    final id = _logins[email.trim().toLowerCase()];
    if (id == null || password != _password) {
      throw AuthFailure('Wrong email or password.');
    }
    _current = userById(id);
    return _current!;
  }

  @override
  Future<AppUser> signInDemo(String userId) async {
    final user = userById(userId);
    if (user == null) throw AuthFailure('Demo account not found.');
    _current = user;
    return user;
  }

  @override
  Future<void> signOut() async => _current = null;

  // ---------------------------------------------------------------- seed

  void _seed() {
    final today = DateTime.now();
    for (final inst in instructors) {
      for (final schedule in InstructorAvailability.defaults(inst.id)) {
        _availability['${inst.id}_${schedule.weekday}'] = schedule;
      }

      for (var dayOffset = 1; dayOffset <= 28; dayOffset++) {
        final day = DateTime(today.year, today.month, today.day + dayOffset);
        final schedule = _availability['${inst.id}_${day.weekday}']!;
        if (!schedule.isAvailable) continue;

        for (
          var minute = schedule.startMinute;
          minute + schedule.slotMinutes <= schedule.endMinute;
          minute += schedule.slotMinutes
        ) {
          final start = DateTime(
            day.year,
            day.month,
            day.day,
            minute ~/ 60,
            minute % 60,
          );
          _slots.add(
            Slot(
              id: 'slot_${inst.id}_${dayOffset}_$minute',
              instructorId: inst.id,
              start: start,
              end: start.add(Duration(minutes: schedule.slotMinutes)),
            ),
          );
        }
      }
    }

    // Demo bookings so the queue and review screens aren't empty.
    _seedBooking(
      's2',
      _slotAt('i1', 1, 9 * 60),
      'Grade discussion for Quiz 2',
      BookingStatus.confirmed,
    );
    _seedBooking(
      's3',
      _slotAt('i1', 1, 9 * 60 + 30),
      'Excuse for missed assignment',
      BookingStatus.pending,
    );
    _seedBooking(
      's1',
      _slotAt('i1', 1, 10 * 60),
      'Follow-up consultation',
      BookingStatus.changeRequested,
      changeRequestedBy: 'i1',
      changeReason:
          'I have an urgent faculty commitment and need to cancel this appointment.',
    );
    _seedBooking(
      's1',
      _slotAt('i2', 2, 9 * 60),
      'Help with database normalization',
      BookingStatus.pending,
    );
    _seedBooking(
      's2',
      _slotAt('i2', 2, 9 * 60 + 30),
      'Project proposal review',
      BookingStatus.confirmed,
    );
    _seedBooking(
      's3',
      _slotAt('i3', 3, 9 * 60),
      'Guidance on mobile app testing',
      BookingStatus.pending,
    );
    _seedBooking(
      's1',
      _slotAt('i3', 3, 9 * 60 + 30),
      'Capstone project check-in',
      BookingStatus.confirmed,
    );
  }

  String _slotAt(String instructorId, int businessDayNumber, int minute) =>
      (_slots
              .where(
                (slot) =>
                    slot.instructorId == instructorId &&
                    slot.start.weekday <= DateTime.friday &&
                    slot.start.hour * 60 + slot.start.minute == minute,
              )
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start)))
          .elementAt(businessDayNumber - 1)
          .id;

  Booking _seedBooking(
    String studentId,
    String slotId,
    String topic,
    BookingStatus status, {
    String? changeRequestedBy,
    String? changeReason,
  }) {
    final slot = slotById(slotId)!;
    slot.isLocked = true;
    slot.inQueue = true;
    final booking =
        Booking(
            id: _nextId('b'),
            studentId: studentId,
            instructorId: slot.instructorId,
            slotId: slotId,
            topic: topic,
            status: status,
            createdAt: DateTime.now(),
          )
          ..statusBeforeCancel = status == BookingStatus.cancelRequested
              ? BookingStatus.confirmed
              : status
          ..changeRequestedBy = changeRequestedBy
          ..changeReason = changeReason
          ..statusBeforeChange = status == BookingStatus.changeRequested
              ? BookingStatus.confirmed
              : status;
    _bookings.add(booking);
    if (status == BookingStatus.changeRequested &&
        changeRequestedBy != null &&
        changeReason != null) {
      final recipientId = changeRequestedBy == studentId
          ? slot.instructorId
          : studentId;
      _notify(
        recipientId,
        '${_name(changeRequestedBy)} requested to cancel the appointment. '
        'Reason: $changeReason',
      );
      _notify(
        changeRequestedBy,
        'Your cancellation request was sent to ${_name(recipientId)} for approval.',
      );
    }
    return booking;
  }

  // --------------------------------------------------------------- users

  @override
  List<AppUser> get users => List.unmodifiable(_users);

  @override
  List<AppUser> get instructors =>
      _users.where((u) => u.role == UserRole.instructor).toList();

  @override
  AppUser? userById(String id) => _users.where((u) => u.id == id).firstOrNull;

  String _name(String userId) => userById(userId)?.name ?? 'Unknown';

  // --------------------------------------------------------------- slots

  @override
  List<Slot> slotsFor(String instructorId, {bool onlyAvailable = false}) {
    final now = DateTime.now();
    final list = _slots.where((s) {
      if (s.instructorId != instructorId) return false;
      if (onlyAvailable) return !s.isLocked && s.start.isAfter(now);
      return true;
    }).toList();
    list.sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  @override
  Slot? slotById(String id) => _slots.where((s) => s.id == id).firstOrNull;

  @override
  List<InstructorAvailability> availabilityFor(String instructorId) =>
      List.unmodifiable([
        for (final fallback in InstructorAvailability.defaults(instructorId))
          _availability['${instructorId}_${fallback.weekday}'] ?? fallback,
      ]);

  @override
  Future<void> saveAvailability(InstructorAvailability availability) async {
    _availability['${availability.instructorId}_${availability.weekday}'] =
        availability;
    _changes.add(null);
  }

  @override
  Future<Slot> addSlot(
    String instructorId,
    DateTime start,
    DateTime end,
  ) async {
    final overlaps = _slots.any(
      (s) =>
          s.instructorId == instructorId &&
          s.start.isBefore(end) &&
          start.isBefore(s.end),
    );
    if (overlaps) {
      throw SlotUnavailableException('That time overlaps an existing slot.');
    }
    final slot = Slot(
      id: _nextId('slot_'),
      instructorId: instructorId,
      start: start,
      end: end,
    );
    _slots.add(slot);
    return slot;
  }

  @override
  Future<void> updateSlot(String slotId, DateTime start, DateTime end) async {
    final slot = slotById(slotId);
    if (slot == null) return;
    if (slot.isLocked) {
      throw SlotUnavailableException('This slot is booked. Cancel the booking first.');
    }
    final overlaps = _slots.any(
      (other) =>
          other.id != slotId &&
          other.instructorId == slot.instructorId &&
          other.start.isBefore(end) &&
          start.isBefore(other.end),
    );
    if (overlaps) {
      throw SlotUnavailableException('That time overlaps an existing slot.');
    }
    slot.start = start;
    slot.end = end;
  }

  @override
  Future<void> removeSlot(String slotId) async {
    final slot = slotById(slotId);
    if (slot == null) return;
    if (slot.isLocked) {
      throw SlotUnavailableException(
        'This slot is booked. Cancel the booking first.',
      );
    }
    _slots.remove(slot);
  }

  // ------------------------------------------------------------ bookings

  Booking _booking(String id) => _bookings.firstWhere((b) => b.id == id);

  DateTime _slotStart(Booking b) => slotById(b.slotId)?.start ?? b.createdAt;

  @override
  List<Booking> bookingsForStudent(String studentId) {
    final list = _bookings.where((b) => b.studentId == studentId).toList();
    list.sort((a, b) => _slotStart(a).compareTo(_slotStart(b)));
    return list;
  }

  @override
  List<Booking> bookingsForInstructor(String instructorId) {
    final list = _bookings
        .where((b) => b.instructorId == instructorId)
        .toList();
    list.sort((a, b) => _slotStart(a).compareTo(_slotStart(b)));
    return list;
  }

  @override
  Future<Booking> book({
    required String studentId,
    required String slotId,
    required String topic,
    String? fileName,
  }) async {
    final slot = slotById(slotId);
    if (slot == null || slot.isLocked) throw SlotUnavailableException();
    slot.isLocked = true;
    slot.inQueue = true;
    final booking = Booking(
      id: _nextId('b'),
      studentId: studentId,
      instructorId: slot.instructorId,
      slotId: slotId,
      topic: topic,
      fileName: fileName,
      createdAt: DateTime.now(),
    );
    _bookings.add(booking);
    _notify(
      slot.instructorId,
      'New request from ${_name(studentId)} for ${fmtDateTime(slot.start)}.',
    );
    _notify(
      studentId,
      'Request sent to ${_name(slot.instructorId)} for ${fmtDateTime(slot.start)}. Waiting for approval.',
    );
    return booking;
  }

  @override
  Future<void> requestBookingChange({
    required String bookingId,
    required String requesterId,
    required String reason,
    String? proposedSlotId,
  }) async {
    final b = _booking(bookingId);
    if (b.status != BookingStatus.pending &&
        b.status != BookingStatus.confirmed) {
      throw StateError('This booking cannot be changed right now.');
    }
    if (requesterId != b.studentId && requesterId != b.instructorId) {
      throw StateError('Only the student or instructor can request a change.');
    }
    final reasonError = bookingChangeReasonError(reason);
    if (reasonError != null) throw StateError(reasonError);
    final currentSlot = slotById(b.slotId);
    if (currentSlot == null ||
        !isBeforeBookingChangeCutoff(currentSlot.start)) {
      throw StateError(
        'Changes must be requested at least 3 hours before the appointment.',
      );
    }

    Slot? proposedSlot;
    if (proposedSlotId != null) {
      proposedSlot = slotById(proposedSlotId);
      if (proposedSlot == null ||
          proposedSlot.instructorId != b.instructorId ||
          proposedSlot.isLocked ||
          !isBeforeBookingChangeCutoff(proposedSlot.start)) {
        throw SlotUnavailableException(
          'That instructor time is no longer available.',
        );
      }
      proposedSlot.isLocked = true;
      proposedSlot.inQueue = false;
    }

    b.statusBeforeChange = b.status;
    b.status = BookingStatus.changeRequested;
    b.changeRequestedBy = requesterId;
    b.changeReason = reason.trim();
    b.proposedSlotId = proposedSlotId;
    final recipientId = requesterId == b.studentId
        ? b.instructorId
        : b.studentId;
    final action = proposedSlot == null
        ? 'cancel the appointment'
        : 'reschedule to ${fmtDateTime(proposedSlot.start)}';
    _notify(
      recipientId,
      '${_name(requesterId)} requested to $action. Reason: ${b.changeReason}',
    );
    _notify(
      requesterId,
      'Your request to $action was sent to ${_name(recipientId)} for approval.',
    );
  }

  @override
  Future<void> reviewBookingChange({
    required String bookingId,
    required String reviewerId,
    required bool approve,
  }) async {
    final b = _booking(bookingId);
    if (b.status != BookingStatus.changeRequested) {
      throw StateError('There is no pending booking change to review.');
    }
    if (reviewerId != b.studentId && reviewerId != b.instructorId ||
        reviewerId == b.changeRequestedBy) {
      throw StateError('Only the other participant can review this request.');
    }
    final currentSlot = slotById(b.slotId);
    if (currentSlot == null) {
      throw StateError('The original appointment slot could not be found.');
    }
    final proposedSlot = b.proposedSlotId == null
        ? null
        : slotById(b.proposedSlotId!);
    if (b.proposedSlotId != null && proposedSlot == null) {
      throw StateError('The proposed appointment slot could not be found.');
    }
    if (approve &&
        (!isBeforeBookingChangeCutoff(currentSlot.start) ||
            (proposedSlot != null &&
                !isBeforeBookingChangeCutoff(proposedSlot.start)))) {
      throw StateError(
        'The request can only be approved at least 3 hours before the appointment.',
      );
    }

    final requesterId = b.changeRequestedBy!;
    final action = proposedSlot == null
        ? 'cancellation'
        : 'reschedule to ${fmtDateTime(proposedSlot.start)}';
    if (approve) {
      if (proposedSlot == null) {
        b.status = BookingStatus.canceled;
        _release(currentSlot);
      } else {
        _release(currentSlot);
        b.slotId = proposedSlot.id;
        b.status = BookingStatus.confirmed;
        proposedSlot.inQueue = true;
      }
    } else {
      if (proposedSlot != null) _release(proposedSlot);
      b.status = b.statusBeforeChange;
    }
    b.changeRequestedBy = null;
    b.changeReason = null;
    b.proposedSlotId = null;

    final response = approve ? 'approved' : 'declined';
    final message = '${_name(reviewerId)} $response your $action request.';
    _notify(requesterId, message);
    _notify(reviewerId, 'You $response the $action request.');
  }

  // --------------------------------------------------- instructor actions

  void _release(Slot slot) {
    slot.isLocked = false;
    slot.inQueue = false;
  }

  @override
  Future<void> reviewRequest(String bookingId, {required bool approve}) async {
    final b = _booking(bookingId);
    if (b.status != BookingStatus.pending) return;
    final slot = slotById(b.slotId)!;
    if (approve) {
      b.status = BookingStatus.confirmed;
      _notify(
        b.studentId,
        '${_name(b.instructorId)} approved your consultation on ${fmtDateTime(slot.start)}.',
      );
    } else {
      b.status = BookingStatus.rejected;
      _release(slot);
      _notify(
        b.studentId,
        '${_name(b.instructorId)} declined your request for ${fmtDateTime(slot.start)}.',
      );
    }
  }

  @override
  Future<void> reviewCancellation(
    String bookingId, {
    required bool approve,
  }) async {
    final b = _booking(bookingId);
    if (b.status != BookingStatus.cancelRequested) return;
    final slot = slotById(b.slotId)!;
    if (approve) {
      b.status = BookingStatus.canceled;
      _release(slot);
      _notify(
        b.studentId,
        '${_name(b.instructorId)} approved your cancellation for ${fmtDateTime(slot.start)}.',
      );
      _notify(
        b.instructorId,
        'You approved ${_name(b.studentId)} cancellation for ${fmtDateTime(slot.start)}.',
      );
    } else {
      b.status = b.statusBeforeCancel;
      _notify(
        b.studentId,
        '${_name(b.instructorId)} declined your cancellation for ${fmtDateTime(slot.start)}. The booking stays.',
      );
      _notify(
        b.instructorId,
        'You declined ${_name(b.studentId)} cancellation for ${fmtDateTime(slot.start)}.',
      );
    }
  }

  @override
  Future<void> markCompleted(String bookingId) async {
    final b = _booking(bookingId);
    if (b.status != BookingStatus.confirmed) return;
    b.status = BookingStatus.completed;
    slotById(b.slotId)?.inQueue = false;
    _notify(
      b.studentId,
      'Your consultation with ${_name(b.instructorId)} is marked completed.',
    );
  }

  // --------------------------------------------------------------- queue

  @override
  List<Slot> queueFor(String instructorId, DateTime day) {
    final list = _bookings
        .where(
          (b) =>
              b.instructorId == instructorId &&
              b.status.isActive &&
              sameDay(_slotStart(b), day),
        )
        .map((b) => slotById(b.slotId))
        .whereType<Slot>()
        .toList();
    list.sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  @override
  int queuePosition(String bookingId) {
    final b = _booking(bookingId);
    if (!b.status.isActive) return 0;
    final slot = slotById(b.slotId);
    if (slot == null) return 0;
    final queue = queueFor(b.instructorId, slot.start);
    return queue.indexWhere((s) => s.id == slot.id) + 1;
  }

  // -------------------------------------------------------- notifications

  void _notify(String userId, String message) {
    _notifications.add(
      AppNotification(
        id: _nextId('n'),
        userId: userId,
        message: message,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  List<AppNotification> notificationsFor(String userId) {
    final list = _notifications.where((n) => n.userId == userId).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  int unreadCount(String userId) =>
      _notifications.where((n) => n.userId == userId && !n.read).length;

  @override
  Future<void> markAllRead(String userId) async {
    for (final n in _notifications) {
      if (n.userId == userId) n.read = true;
    }
  }

  @override
  Future<void> seedFirestore() {
    // TODO: implement seedFirestore
    throw UnimplementedError();
  }
}
