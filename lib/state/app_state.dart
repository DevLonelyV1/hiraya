import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/booking_repository.dart';
import '../models/app_user.dart';
import '../models/booking.dart';
import '../models/instructor_availability.dart';
import '../models/slot.dart';

/// App-wide state. Screens read data via `state.repo` after calling
/// `context.watch<AppState>()`, and change data ONLY through the methods
/// below. Actions are async: `await` them inside try/catch in the screen.
/// The screens refresh when the repository emits `changes` (and after every
/// action, which covers the mock repository).
class AppState extends ChangeNotifier {
  AppState(this.repo) {
    _sub = repo.changes.listen((_) => notifyListeners());
  }

  final BookingRepository repo;
  StreamSubscription<void>? _sub;

  AppUser? _user;
  AppUser? get user => _user;

  /// The logged-in user. Only call this from screens shown after login.
  AppUser get me => _user!;

  bool _booting = true;

  /// True until we know whether a saved session exists.
  bool get booting => _booting;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ---- auth ----

  Future<void> restoreSession() async {
    try {
      _user = await repo.restoreSession();
    } catch (_) {
      _user = null;
    }
    _booting = false;
    notifyListeners();
  }

  /// Throws [AuthFailure] with a user-friendly message.
  Future<void> signIn(String email, String password) async {
    _user = await repo.signIn(email, password);
    notifyListeners();
  }

  Future<void> logout() async {
    _user = null;
    notifyListeners();
    await repo.signOut();
  }

  int get unreadCount => _user == null ? 0 : repo.unreadCount(_user!.id);

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } finally {
      notifyListeners();
    }
  }

  // ---- student actions ----

  Future<Booking> book(Slot slot, String topic, {String? fileName}) => _run(
    () => repo.book(
      studentId: me.id,
      slotId: slot.id,
      topic: topic,
      fileName: fileName,
    ),
  );

  Future<void> requestBookingChange({
    required String bookingId,
    required String reason,
    String? proposedSlotId,
  }) => _run(
    () => repo.requestBookingChange(
      bookingId: bookingId,
      requesterId: me.id,
      reason: reason,
      proposedSlotId: proposedSlotId,
    ),
  );

  Future<void> reviewBookingChange(String bookingId, {required bool approve}) =>
      _run(
        () => repo.reviewBookingChange(
          bookingId: bookingId,
          reviewerId: me.id,
          approve: approve,
        ),
      );

  // ---- instructor actions ----

  Future<void> addSlot(DateTime start, DateTime end) =>
      _run(() => repo.addSlot(me.id, start, end));

  Future<void> updateSlot(String slotId, DateTime start, DateTime end) =>
      _run(() => repo.updateSlot(slotId, start, end));

  Future<void> removeSlot(String slotId) => _run(() => repo.removeSlot(slotId));

  Future<void> saveAvailability(InstructorAvailability availability) =>
      _run(() => repo.saveAvailability(availability));

  Future<void> reviewRequest(String bookingId, {required bool approve}) =>
      _run(() => repo.reviewRequest(bookingId, approve: approve));

  Future<void> reviewCancellation(String bookingId, {required bool approve}) =>
      _run(() => repo.reviewCancellation(bookingId, approve: approve));

  Future<void> markCompleted(String bookingId) =>
      _run(() => repo.markCompleted(bookingId));

  // ---- notifications ----

  Future<void> markAllRead() => _run(() => repo.markAllRead(me.id));
  Future<void> signInDemo(AppUser user) async {
    _user = await repo.signInDemo(user.id);
    notifyListeners();
  }
}
