import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../core/format.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/booking.dart';
import '../models/booking_change_policy.dart';
import '../models/instructor_availability.dart';
import '../models/slot.dart';
import 'booking_repository.dart';

/// Firebase (Auth + Cloud Firestore) implementation.
///
/// After login it opens Firestore listeners and keeps the results in memory,
/// so the synchronous reads in the contract stay instant. Every snapshot
/// emits on [changes], which makes AppState refresh the screens.
///
/// Collections: users, slots, bookings, notifications (see firestore.rules).
/// Times are stored as UTC Timestamps; `Timestamp.toDate()` returns local time.
class FirebaseBookingRepository implements BookingRepository {
  FirebaseBookingRepository({FirebaseAuth? auth, FirebaseFirestore? db})
    : _auth = auth ?? FirebaseAuth.instance,
      _db = db ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  final _changes = StreamController<void>.broadcast();
  final List<StreamSubscription<dynamic>> _subs = [];

  List<AppUser> _users = [];
  List<Slot> _slots = [];
  List<Booking> _bookings = [];
  List<AppNotification> _notifications = [];
  List<InstructorAvailability> _availability = [];

  @override
  Stream<void> get changes => _changes.stream;

  @override
  String? get loginHint => null;

  // ---------------------------------------------------------------- auth

  @override
  Future<AppUser?> restoreSession() async {
    final fbUser = await _auth.authStateChanges().first;
    if (fbUser == null) return null;
    try {
      return await _loadProfile(fbUser);
    } catch (e) {
      debugPrint('restoreSession failed: $e');
      return null;
    }
  }

  @override
  Future<AppUser> signIn(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return await _loadProfile(cred.user!);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_authMessage(e.code));
    }
  }

  @override
  Future<void> signOut() async {
    await _stopSync();
    await _auth.signOut();
  }

  String _authMessage(String code) => switch (code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' ||
    'invalid-email' => 'Wrong email or password.',
    'user-disabled' => 'This account has been disabled.',
    'too-many-requests' => 'Too many attempts. Try again later.',
    'network-request-failed' =>
      'No connection. Check your internet and try again.',
    _ => 'Could not sign in ($code).',
  };

  Future<AppUser> _loadProfile(User fbUser) async {
    final doc = await _db.collection('users').doc(fbUser.uid).get();
    final me = doc.exists ? _userFrom(doc) : null;
    if (me == null || doc.data()?['active'] == false) {
      await _auth.signOut();
      throw AuthFailure(
        'This account is not set up or has been deactivated. Contact your administrator.',
      );
    }
    await _startSync(me);
    return me;
  }

  // ---------------------------------------------------------------- sync

  Future<void> _startSync(AppUser me) async {
    await _stopSync();
    final byMe = me.role == UserRole.student ? 'studentId' : 'instructorId';
    final listeners = <Future<void>>[
      _listen(_db.collection('users'), (snap) {
        _users = snap.docs
            .where((d) => d.data()['active'] != false)
            .map(_userFrom)
            .whereType<AppUser>()
            .toList();
        _availability = [
          for (final doc in snap.docs)
            if (doc.data()['role'] == 'instructor')
              if (doc.data()['availabilitySchedules']
                  case final Map<String, dynamic> schedules)
                for (final entry in schedules.entries)
                  if (int.tryParse(entry.key) case final int weekday)
                    if (entry.value case final Map<String, dynamic> values)
                      if (weekday >= DateTime.monday &&
                          weekday <= DateTime.sunday)
                        _availabilityFrom(doc.id, weekday, values),
        ];
      }),
      _listen(_db.collection('slots'), (snap) {
        _slots = snap.docs.map(_slotFrom).toList();
      }),
      _listen(_db.collection('bookings').where(byMe, isEqualTo: me.id), (snap) {
        _bookings = snap.docs.map(_bookingFrom).toList();
      }),
      _listen(
        _db.collection('notifications').where('userId', isEqualTo: me.id),
        (snap) {
          _notifications = snap.docs.map(_notificationFrom).toList();
        },
      ),
    ];
    await Future.wait(listeners);
  }

  Future<void> _stopSync() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    // _users = [];
    _slots = [];
    _bookings = [];
    _notifications = [];
    _availability = [];
  }

  /// Subscribes to a query. The returned future completes after the first
  /// snapshot, so login can wait until data is ready.
  Future<void> _listen(
    Query<Map<String, dynamic>> query,
    void Function(QuerySnapshot<Map<String, dynamic>> snap) apply,
  ) {
    final first = Completer<void>();
    _subs.add(
      query.snapshots().listen(
        (snap) {
          apply(snap);
          _changes.add(null);
          if (!first.isCompleted) first.complete();
        },
        onError: (Object e) {
          debugPrint('Firestore listener error: $e');
          if (!first.isCompleted) first.completeError(e);
        },
      ),
    );
    return first.future;
  }

  // ------------------------------------------------------------- parsing

  AppUser? _userFrom(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    if (m == null) return null;
    final role = switch (m['role']) {
      'student' => UserRole.student,
      'instructor' => UserRole.instructor,
      _ => null, // e.g. admin: not handled by the app yet
    };
    if (role == null) return null;
    return AppUser(
      id: d.id,
      name: m['name'] as String? ?? 'Unknown',
      role: role,
      department: m['department'] as String? ?? '',
    );
  }

  Slot _slotFrom(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return Slot(
      id: d.id,
      instructorId: m['instructorId'] as String,
      start: (m['start'] as Timestamp).toDate(),
      end: (m['end'] as Timestamp).toDate(),
      isLocked: m['isLocked'] == true,
      inQueue: m['inQueue'] == true,
    );
  }

  BookingStatus _status(Object? v, BookingStatus fallback) =>
      BookingStatus.values.where((s) => s.name == v).firstOrNull ?? fallback;

  Booking _bookingFrom(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return Booking(
        id: d.id,
        studentId: m['studentId'] as String,
        instructorId: m['instructorId'] as String,
        slotId: m['slotId'] as String,
        topic: m['topic'] as String? ?? '',
        fileName: m['fileName'] as String?,
        createdAt: (m['createdAt'] as Timestamp).toDate(),
        status: _status(m['status'], BookingStatus.pending),
      )
      ..statusBeforeCancel = _status(
        m['statusBeforeCancel'],
        BookingStatus.confirmed,
      )
      ..changeRequestedBy = m['changeRequestedBy'] as String?
      ..changeReason = m['changeReason'] as String?
      ..proposedSlotId = m['proposedSlotId'] as String?
      ..statusBeforeChange = _status(
        m['statusBeforeChange'],
        BookingStatus.confirmed,
      );
  }

  InstructorAvailability _availabilityFrom(
    String instructorId,
    int weekday,
    Map<String, dynamic> data,
  ) {
    return InstructorAvailability(
      instructorId: instructorId,
      weekday: weekday,
      isAvailable: data['isAvailable'] as bool? ?? false,
      startMinute:
          data['startMinute'] as int? ??
          InstructorAvailability.defaultStartMinute,
      endMinute:
          data['endMinute'] as int? ?? InstructorAvailability.defaultEndMinute,
      slotMinutes:
          data['slotMinutes'] as int? ??
          InstructorAvailability.defaultSlotMinutes,
    );
  }

  AppNotification _notificationFrom(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return AppNotification(
      id: d.id,
      userId: m['userId'] as String,
      message: m['message'] as String? ?? '',
      createdAt: (m['createdAt'] as Timestamp).toDate(),
      read: m['read'] == true,
    );
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

  DocumentReference<Map<String, dynamic>> _slotRef(String id) =>
      _db.collection('slots').doc(id);

  DocumentReference<Map<String, dynamic>> _bookingRef(String id) =>
      _db.collection('bookings').doc(id);

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
  List<InstructorAvailability> availabilityFor(String instructorId) {
    final savedByDay = {
      for (final entry in _availability)
        if (entry.instructorId == instructorId) entry.weekday: entry,
    };
    return List.unmodifiable([
      for (final fallback in InstructorAvailability.defaults(instructorId))
        savedByDay[fallback.weekday] ?? fallback,
    ]);
  }

  @override
  Future<void> saveAvailability(InstructorAvailability availability) async {
    final ref = _db.collection('users').doc(availability.instructorId);
    await ref.update({
      'availabilitySchedules.${availability.weekday}': {
        'isAvailable': availability.isAvailable,
        'startMinute': availability.startMinute,
        'endMinute': availability.endMinute,
        'slotMinutes': availability.slotMinutes,
      },
    });
    _availability = [
      ..._availability.where(
        (entry) =>
            entry.instructorId != availability.instructorId ||
            entry.weekday != availability.weekday,
      ),
      availability,
    ]..sort((a, b) => a.weekday.compareTo(b.weekday));
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
    final ref = _db.collection('slots').doc();
    await ref.set({
      'instructorId': instructorId,
      'start': Timestamp.fromDate(start.toUtc()),
      'end': Timestamp.fromDate(end.toUtc()),
      'isLocked': false,
      'inQueue': false,
    });
    final slot = Slot(
      id: ref.id,
      instructorId: instructorId,
      start: start,
      end: end,
    );
    _slots.add(slot);
    _changes.add(null);
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
    await _slotRef(slotId).update({
      'start': Timestamp.fromDate(start.toUtc()),
      'end': Timestamp.fromDate(end.toUtc()),
    });
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
    await _slotRef(slotId).delete();
    _slots.removeWhere((entry) => entry.id == slotId);
    _changes.add(null);
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

  Map<String, dynamic> _notif(String userId, String message) => {
    'userId': userId,
    'message': message,
    'read': false,
    'createdAt': Timestamp.fromDate(DateTime.now().toUtc()),
  };

  DocumentReference<Map<String, dynamic>> _newNotifRef() =>
      _db.collection('notifications').doc();

  /// Frees a slot (booking rejected, canceled or moved away).
  Map<String, dynamic> get _freed => {'isLocked': false, 'inQueue': false};

  @override
  Future<Booking> book({
    required String studentId,
    required String slotId,
    required String topic,
    String? fileName,
  }) async {
    final slotRef = _slotRef(slotId);
    final bookingRef = _db.collection('bookings').doc();
    final createdAt = DateTime.now();
    late Booking booking;

    // The transaction makes "check unlocked + lock + create booking" atomic,
    // so two students racing for one slot can't both win.
    await _db.runTransaction((tx) async {
      final snap = await tx.get(slotRef);
      if (!snap.exists || snap.data()!['isLocked'] == true) {
        throw SlotUnavailableException();
      }
      final slot = _slotFrom(snap);
      tx.update(slotRef, {'isLocked': true, 'inQueue': true});
      tx.set(bookingRef, {
        'studentId': studentId,
        'instructorId': slot.instructorId,
        'slotId': slotId,
        'topic': topic,
        'fileName': fileName,
        'status': BookingStatus.pending.name,
        'statusBeforeCancel': BookingStatus.confirmed.name,
        'createdAt': Timestamp.fromDate(createdAt.toUtc()),
      });
      tx.set(
        _newNotifRef(),
        _notif(
          slot.instructorId,
          'New request from ${_name(studentId)} for ${fmtDateTime(slot.start)}.',
        ),
      );
      tx.set(
        _newNotifRef(),
        _notif(
          studentId,
          'Request sent to ${_name(slot.instructorId)} for ${fmtDateTime(slot.start)}. Waiting for approval.',
        ),
      );
      booking = Booking(
        id: bookingRef.id,
        studentId: studentId,
        instructorId: slot.instructorId,
        slotId: slotId,
        topic: topic,
        fileName: fileName,
        createdAt: createdAt,
      );
    });
    return booking;
  }

  @override
  Future<void> requestBookingChange({
    required String bookingId,
    required String requesterId,
    required String reason,
    String? proposedSlotId,
  }) async {
    final bookingRef = _bookingRef(bookingId);
    final proposedSlotRef = proposedSlotId == null
        ? null
        : _slotRef(proposedSlotId);
    final reasonError = bookingChangeReasonError(reason);
    if (reasonError != null) throw StateError(reasonError);

    await _db.runTransaction((tx) async {
      final bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) {
        throw StateError('The appointment could not be found.');
      }
      final booking = _bookingFrom(bookingSnap);
      final currentSlotRef = _slotRef(booking.slotId);
      final currentSlotSnap = await tx.get(currentSlotRef);
      final proposedSlotSnap = proposedSlotRef == null
          ? null
          : await tx.get(proposedSlotRef);
      if (!currentSlotSnap.exists) {
        throw StateError('The appointment could not be found.');
      }

      if (booking.status != BookingStatus.pending &&
          booking.status != BookingStatus.confirmed) {
        throw StateError('This booking cannot be changed right now.');
      }
      if (requesterId != booking.studentId &&
          requesterId != booking.instructorId) {
        throw StateError(
          'Only the student or instructor can request a change.',
        );
      }
      final currentSlot = _slotFrom(currentSlotSnap);
      if (!isBeforeBookingChangeCutoff(currentSlot.start)) {
        throw StateError(
          'Changes must be requested at least 3 hours before the appointment.',
        );
      }

      Slot? proposedSlot;
      if (proposedSlotId != null) {
        if (proposedSlotSnap == null || !proposedSlotSnap.exists) {
          throw SlotUnavailableException(
            'That instructor time is no longer available.',
          );
        }
        proposedSlot = _slotFrom(proposedSlotSnap);
        if (proposedSlot.instructorId != booking.instructorId ||
            proposedSlot.isLocked ||
            !isBeforeBookingChangeCutoff(proposedSlot.start)) {
          throw SlotUnavailableException(
            'That instructor time is no longer available.',
          );
        }
        tx.update(proposedSlotRef!, {'isLocked': true, 'inQueue': false});
      }

      final recipientId = requesterId == booking.studentId
          ? booking.instructorId
          : booking.studentId;
      final action = proposedSlot == null
          ? 'cancel the appointment'
          : 'reschedule to ${fmtDateTime(proposedSlot.start)}';
      final normalizedReason = reason.trim();
      tx.update(bookingRef, {
        'statusBeforeChange': booking.status.name,
        'status': BookingStatus.changeRequested.name,
        'changeRequestedBy': requesterId,
        'changeReason': normalizedReason,
        'proposedSlotId': proposedSlotId,
      });
      tx.set(
        _newNotifRef(),
        _notif(
          recipientId,
          '${_name(requesterId)} requested to $action. Reason: $normalizedReason',
        ),
      );
      tx.set(
        _newNotifRef(),
        _notif(
          requesterId,
          'Your request to $action was sent to ${_name(recipientId)} for approval.',
        ),
      );
    });
  }

  @override
  Future<void> reviewBookingChange({
    required String bookingId,
    required String reviewerId,
    required bool approve,
  }) async {
    final bookingRef = _bookingRef(bookingId);

    await _db.runTransaction((tx) async {
      final bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) {
        throw StateError('The appointment could not be found.');
      }
      final booking = _bookingFrom(bookingSnap);
      final currentSlotRef = _slotRef(booking.slotId);
      final currentSlotSnap = await tx.get(currentSlotRef);
      if (!currentSlotSnap.exists) {
        throw StateError('The appointment could not be found.');
      }
      if (booking.status != BookingStatus.changeRequested) {
        throw StateError('There is no pending booking change to review.');
      }
      if ((reviewerId != booking.studentId &&
              reviewerId != booking.instructorId) ||
          reviewerId == booking.changeRequestedBy) {
        throw StateError('Only the other participant can review this request.');
      }

      final currentSlot = _slotFrom(currentSlotSnap);
      final proposedSlotRef = booking.proposedSlotId == null
          ? null
          : _slotRef(booking.proposedSlotId!);
      final proposedSlotSnap = proposedSlotRef == null
          ? null
          : await tx.get(proposedSlotRef);
      if (booking.proposedSlotId != null &&
          (proposedSlotSnap == null || !proposedSlotSnap.exists)) {
        throw StateError('The proposed appointment slot could not be found.');
      }
      final proposedSlot = proposedSlotSnap == null
          ? null
          : _slotFrom(proposedSlotSnap);
      if (approve &&
          (!isBeforeBookingChangeCutoff(currentSlot.start) ||
              (proposedSlot != null &&
                  !isBeforeBookingChangeCutoff(proposedSlot.start)))) {
        throw StateError(
          'The request can only be approved at least 3 hours before the appointment.',
        );
      }

      final requesterId = booking.changeRequestedBy!;
      final action = proposedSlot == null
          ? 'cancellation'
          : 'reschedule to ${fmtDateTime(proposedSlot.start)}';
      final response = approve ? 'approved' : 'declined';
      final update = <String, Object?>{
        'changeRequestedBy': null,
        'changeReason': null,
        'proposedSlotId': null,
      };
      if (approve) {
        if (proposedSlot == null) {
          update['status'] = BookingStatus.canceled.name;
          tx.update(currentSlotRef, _freed);
        } else {
          update
            ..['slotId'] = proposedSlot.id
            ..['status'] = BookingStatus.confirmed.name;
          tx.update(currentSlotRef, _freed);
          tx.update(proposedSlotRef!, {'isLocked': true, 'inQueue': true});
        }
      } else {
        update['status'] = booking.statusBeforeChange.name;
        if (proposedSlotRef != null) {
          tx.update(proposedSlotRef, _freed);
        }
      }
      tx.update(bookingRef, update);
      tx.set(
        _newNotifRef(),
        _notif(
          requesterId,
          '${_name(reviewerId)} $response your $action request.',
        ),
      );
      tx.set(
        _newNotifRef(),
        _notif(reviewerId, 'You $response the $action request.'),
      );
    });
  }

  // --------------------------------------------------- instructor actions

  @override
  Future<void> reviewRequest(String bookingId, {required bool approve}) async {
    final b = _booking(bookingId);
    if (b.status != BookingStatus.pending) return;
    final slot = slotById(b.slotId)!;
    final batch = _db.batch();
    if (approve) {
      batch
        ..update(_bookingRef(b.id), {'status': BookingStatus.confirmed.name})
        ..set(
          _newNotifRef(),
          _notif(
            b.studentId,
            '${_name(b.instructorId)} approved your consultation on ${fmtDateTime(slot.start)}.',
          ),
        );
    } else {
      batch
        ..update(_bookingRef(b.id), {'status': BookingStatus.rejected.name})
        ..update(_slotRef(slot.id), _freed)
        ..set(
          _newNotifRef(),
          _notif(
            b.studentId,
            '${_name(b.instructorId)} declined your request for ${fmtDateTime(slot.start)}.',
          ),
        );
    }
    await batch.commit();
  }

  @override
  Future<void> reviewCancellation(
    String bookingId, {
    required bool approve,
  }) async {
    final b = _booking(bookingId);
    if (b.status != BookingStatus.cancelRequested) return;
    final slot = slotById(b.slotId)!;
    final batch = _db.batch();
    if (approve) {
      batch
        ..update(_bookingRef(b.id), {'status': BookingStatus.canceled.name})
        ..update(_slotRef(slot.id), _freed)
        ..set(
          _newNotifRef(),
          _notif(
            b.studentId,
            '${_name(b.instructorId)} approved your cancellation for ${fmtDateTime(slot.start)}.',
          ),
        )
        ..set(
          _newNotifRef(),
          _notif(
            b.instructorId,
            'You approved ${_name(b.studentId)} cancellation for ${fmtDateTime(slot.start)}.',
          ),
        );
    } else {
      batch
        ..update(_bookingRef(b.id), {'status': b.statusBeforeCancel.name})
        ..set(
          _newNotifRef(),
          _notif(
            b.studentId,
            '${_name(b.instructorId)} declined your cancellation for ${fmtDateTime(slot.start)}. The booking stays.',
          ),
        )
        ..set(
          _newNotifRef(),
          _notif(
            b.instructorId,
            'You declined ${_name(b.studentId)} cancellation for ${fmtDateTime(slot.start)}.',
          ),
        );
    }
    await batch.commit();
  }

  @override
  Future<void> markCompleted(String bookingId) async {
    final b = _booking(bookingId);
    if (b.status != BookingStatus.confirmed) return;
    final batch = _db.batch()
      ..update(_bookingRef(b.id), {'status': BookingStatus.completed.name})
      ..update(_slotRef(b.slotId), {'inQueue': false})
      ..set(
        _newNotifRef(),
        _notif(
          b.studentId,
          'Your consultation with ${_name(b.instructorId)} is marked completed.',
        ),
      );
    await batch.commit();
  }

  // --------------------------------------------------------------- queue

  @override
  List<Slot> queueFor(String instructorId, DateTime day) {
    final list = _slots
        .where(
          (s) =>
              s.instructorId == instructorId &&
              s.inQueue &&
              sameDay(s.start, day),
        )
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
    final unread = _notifications
        .where((n) => n.userId == userId && !n.read)
        .toList();
    if (unread.isEmpty) return;
    final batch = _db.batch();
    for (final n in unread) {
      batch.update(_db.collection('notifications').doc(n.id), {'read': true});
    }
    await batch.commit();
  }

  // -------------------------------------------------------- developer options

  /// Seeds Firestore with initial demo users, slots, and bookings.
  @override
  Future<void> seedFirestore() async {
    final batch = _db.batch();

    // 1. Seed Users (matching the demo accounts)
    final demoUsers = [
      {
        'id': 's1',
        'name': 'Ana Villanueva',
        'role': 'student',
        'department': 'BS Information Technology',
        'active': true,
      },
      {
        'id': 's2',
        'name': 'Ben Ramos',
        'role': 'student',
        'department': 'BS Information Technology',
        'active': true,
      },
      {
        'id': 's3',
        'name': 'Carla Mendoza',
        'role': 'student',
        'department': 'BS Information Technology',
        'active': true,
      },
      {
        'id': 'i1',
        'name': 'Prof. Reyes',
        'role': 'instructor',
        'department': 'IT Department',
        'active': true,
      },
      {
        'id': 'i2',
        'name': 'Prof. Santos',
        'role': 'instructor',
        'department': 'IT Department',
        'active': true,
      },
      {
        'id': 'i3',
        'name': 'Prof. Dela Cruz',
        'role': 'instructor',
        'department': 'IT Department',
        'active': true,
      },
    ];

    for (final u in demoUsers) {
      final ref = _db.collection('users').doc(u['id'] as String);
      final data = Map<String, dynamic>.from(u);
      if (u['role'] == 'instructor') {
        data['availabilitySchedules'] = {
          for (final schedule in InstructorAvailability.defaults(
            u['id'] as String,
          ))
            '${schedule.weekday}': {
              'isAvailable': schedule.isAvailable,
              'startMinute': schedule.startMinute,
              'endMinute': schedule.endMinute,
              'slotMinutes': schedule.slotMinutes,
            },
        };
      }
      batch.set(ref, data, SetOptions(merge: true));
    }

    // 2. Seed the default four-week weekday schedule.
    final today = DateTime.now();
    final instructorIds = ['i1', 'i2', 'i3'];
    for (final instId in instructorIds) {
      for (var dayOffset = 1; dayOffset <= 28; dayOffset++) {
        final day = DateTime(today.year, today.month, today.day + dayOffset);
        final schedule = InstructorAvailability.defaults(
          instId,
        )[day.weekday - 1];
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
          final end = start.add(Duration(minutes: schedule.slotMinutes));

          final slotId = 'slot_${instId}_${dayOffset}_$minute';
          final slotRef = _db.collection('slots').doc(slotId);

          batch.set(slotRef, {
            'instructorId': instId,
            'start': Timestamp.fromDate(start.toUtc()),
            'end': Timestamp.fromDate(end.toUtc()),
            'isLocked': false,
            'inQueue': false,
          }, SetOptions(merge: true));
        }
      }
    }

    await batch.commit();
    debugPrint('Firestore database seeded successfully!');
  }

  Future<void> loadDemoUsers() async {
    final snapshot = await _db.collection('users').get();

    _users = snapshot.docs
        .where((d) => d.data()['active'] != false)
        .map(_userFrom)
        .whereType<AppUser>()
        .toList();

    _changes.add(null);

    debugPrint('Loaded ${_users.length} users');
  }

  @override
  Future<AppUser> signInDemo(String userId) async {
    try {
      // Find the selected user in Firestore.
      final doc = await _db.collection('users').doc(userId).get();

      if (!doc.exists || doc.data()?['active'] == false) {
        throw AuthFailure('Demo account not found or inactive.');
      }

      final user = _userFrom(doc);

      if (user == null) {
        throw AuthFailure('Invalid demo account.');
      }

      // Start Firestore listeners for this user.
      await _startSync(user);

      return user;
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure('Could not load demo account: $e');
    }
  }
}
