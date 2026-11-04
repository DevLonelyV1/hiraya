import 'dart:async';

import '../core/format.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/booking.dart';
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
    AppUser(id: 'i1', name: 'Prof. Reyes', role: UserRole.instructor, department: 'IT Department'),
    AppUser(id: 'i2', name: 'Prof. Santos', role: UserRole.instructor, department: 'IT Department'),
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
  final _changes = StreamController<void>.broadcast();
  AppUser? _current;
  int _idCounter = 100;

  String _nextId(String prefix) => '$prefix${_idCounter++}';

  // ---------------------------------------------------------------- auth

  @override
  Stream<void> get changes => _changes.stream;

  @override
  String? get loginHint => 'Demo logins (password: $_password):\n${_logins.keys.join(', ')}';

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
  Future<void> signOut() async => _current = null;

  // ---------------------------------------------------------------- seed

  void _seed() {
    final today = DateTime.now();
    const startTimes = [
      [9, 0],
      [9, 30],
      [10, 0],
      [13, 0],
      [13, 30],
      [14, 0],
    ];
    for (final inst in instructors) {
      for (var d = 1; d <= 4; d++) {
        final day = DateTime(today.year, today.month, today.day + d);
        for (var i = 0; i < startTimes.length; i++) {
          final start = DateTime(day.year, day.month, day.day, startTimes[i][0], startTimes[i][1]);
          _slots.add(
            Slot(
              id: 'slot_${inst.id}_${d}_$i',
              instructorId: inst.id,
              start: start,
              end: start.add(const Duration(minutes: 30)),
            ),
          );
        }
      }
    }

    // Demo bookings so the queue and review screens aren't empty.
    _seedBooking('s2', 'slot_i1_1_0', 'Grade discussion for Quiz 2', BookingStatus.confirmed);
    _seedBooking('s3', 'slot_i1_1_1', 'Excuse for missed assignment', BookingStatus.pending);
  }

  void _seedBooking(String studentId, String slotId, String topic, BookingStatus status) {
    final slot = slotById(slotId)!;
    slot.isLocked = true;
    slot.inQueue = true;
    _bookings.add(
      Booking(
        id: _nextId('b'),
        studentId: studentId,
        instructorId: slot.instructorId,
        slotId: slotId,
        topic: topic,
        status: status,
        createdAt: DateTime.now(),
      ),
    );
  }

  // --------------------------------------------------------------- users

  @override
  List<AppUser> get users => List.unmodifiable(_users);

  @override
  List<AppUser> get instructors => _users.where((u) => u.role == UserRole.instructor).toList();

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
  Future<Slot> addSlot(String instructorId, DateTime start, DateTime end) async {
    final overlaps = _slots.any(
      (s) => s.instructorId == instructorId && s.start.isBefore(end) && start.isBefore(s.end),
    );
    if (overlaps) {
      throw SlotUnavailableException('That time overlaps an existing slot.');
    }
    final slot = Slot(id: _nextId('slot_'), instructorId: instructorId, start: start, end: end);
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
      throw SlotUnavailableException('This slot is booked. Cancel the booking first.');
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
    final list = _bookings.where((b) => b.instructorId == instructorId).toList();
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
  Future<void> reschedule(String bookingId, String newSlotId) async {
    final b = _booking(bookingId);
    if (b.status != BookingStatus.pending && b.status != BookingStatus.confirmed) {
      throw StateError('Only pending or confirmed bookings can be moved.');
    }
    final newSlot = slotById(newSlotId);
    if (newSlot == null || newSlot.isLocked) throw SlotUnavailableException();

    final old = slotById(b.slotId);
    old?.isLocked = false;
    old?.inQueue = false;
    newSlot.isLocked = true;
    newSlot.inQueue = true;
    b.slotId = newSlot.id;
    b.instructorId = newSlot.instructorId;
    b.status = BookingStatus.pending;

    _notify(
      b.instructorId,
      '${_name(b.studentId)} rescheduled to ${fmtDateTime(newSlot.start)}. Please review.',
    );
    _notify(b.studentId, 'Booking moved to ${fmtDateTime(newSlot.start)}. Waiting for approval.');
  }

  @override
  Future<void> requestCancellation(String bookingId) async {
    final b = _booking(bookingId);
    if (b.status != BookingStatus.pending && b.status != BookingStatus.confirmed) {
      throw StateError('This booking cannot be canceled.');
    }
    b.statusBeforeCancel = b.status;
    b.status = BookingStatus.cancelRequested;
    final when = fmtDateTime(slotById(b.slotId)!.start);
    _notify(b.instructorId, '${_name(b.studentId)} requested to cancel the $when consultation.');
    _notify(b.studentId, 'Cancellation requested. Waiting for instructor review.');
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
  Future<void> reviewCancellation(String bookingId, {required bool approve}) async {
    final b = _booking(bookingId);
    if (b.status != BookingStatus.cancelRequested) return;
    final slot = slotById(b.slotId)!;
    if (approve) {
      b.status = BookingStatus.canceled;
      _release(slot);
      _notify(b.studentId, 'Your cancellation for ${fmtDateTime(slot.start)} was approved.');
    } else {
      b.status = b.statusBeforeCancel;
      _notify(
        b.studentId,
        'Your cancellation for ${fmtDateTime(slot.start)} was not approved. The booking stays.',
      );
    }
  }

  @override
  Future<void> markCompleted(String bookingId) async {
    final b = _booking(bookingId);
    if (b.status != BookingStatus.confirmed) return;
    b.status = BookingStatus.completed;
    slotById(b.slotId)?.inQueue = false;
    _notify(b.studentId, 'Your consultation with ${_name(b.instructorId)} is marked completed.');
  }

  @override
  Future<void> cancelByInstructor(String bookingId) async {
    final b = _booking(bookingId);
    if (b.status != BookingStatus.pending && b.status != BookingStatus.confirmed) {
      return;
    }
    final slot = slotById(b.slotId)!;
    b.status = BookingStatus.canceled;
    _release(slot);
    _notify(
      b.studentId,
      '${_name(b.instructorId)} canceled your consultation on ${fmtDateTime(slot.start)}.',
    );
  }

  // --------------------------------------------------------------- queue

  @override
  List<Slot> queueFor(String instructorId, DateTime day) {
    final list = _bookings
        .where(
          (b) => b.instructorId == instructorId && b.status.isActive && sameDay(_slotStart(b), day),
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
