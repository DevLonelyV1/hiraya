import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/booking.dart';
import '../models/slot.dart';

/// Thrown when a slot is already taken, overlaps, or can't be removed.
class SlotUnavailableException implements Exception {
  SlotUnavailableException([this.message = 'That slot was just taken.']);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when login fails. [message] is safe to show to the user.
class AuthFailure implements Exception {
  AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// THE CONTRACT. Everyone codes against this interface.
/// Do not change it without telling the lead (Person 1).
///
/// Reads are synchronous and come from an in-memory cache that the
/// implementation keeps fresh. Writes are async. Whenever the cache changes,
/// [changes] emits so AppState can refresh the screens.
abstract class BookingRepository {
  /// Emits whenever cached data changes.
  Stream<void> get changes;

  // --- Auth ---
  /// Shown under the login form (mock repo shows demo logins). Null = none.
  String? get loginHint;

  /// Returns the already-signed-in user (and starts syncing), or null.
  Future<AppUser?> restoreSession();

  /// Throws [AuthFailure] on bad credentials.
  Future<AppUser> signIn(String email, String password);
  Future<void> signOut();

  // --- Users ---
  List<AppUser> get users;
  List<AppUser> get instructors;
  AppUser? userById(String id);

  // --- Slots / office hours ---
  List<Slot> slotsFor(String instructorId, {bool onlyAvailable = false});
  Slot? slotById(String id);
  Future<Slot> addSlot(String instructorId, DateTime start, DateTime end);
  Future<void> updateSlot(String slotId, DateTime start, DateTime end);
  Future<void> removeSlot(String slotId);

  // --- Bookings ---
  List<Booking> bookingsForStudent(String studentId);
  List<Booking> bookingsForInstructor(String instructorId);

  /// Locks the slot and creates a PENDING booking. Throws
  /// [SlotUnavailableException] if the slot is already locked.
  Future<Booking> book({
    required String studentId,
    required String slotId,
    required String topic,
    String? fileName,
  });

  /// Moves a booking to a new slot (old slot is released). Status goes back
  /// to PENDING so the instructor re-approves.
  Future<void> reschedule(String bookingId, String newSlotId);

  /// Student asks to cancel -> status CANCEL_REQUESTED; instructor decides.
  Future<void> requestCancellation(String bookingId);

  // --- Instructor actions ---
  Future<void> reviewRequest(String bookingId, {required bool approve});
  Future<void> reviewCancellation(String bookingId, {required bool approve});
  Future<void> markCompleted(String bookingId);
  Future<void> cancelByInstructor(String bookingId);

  // --- Queue ---
  /// 1-based position among active bookings of the same instructor on the
  /// same day, ordered by slot time. Returns 0 if the booking isn't active.
  int queuePosition(String bookingId);

  /// Slots holding an active booking for an instructor on a given day,
  /// ordered by time. (Slots, not bookings, so students never need to read
  /// each other's bookings.) A booking is "you" when `slot.id == booking.slotId`.
  List<Slot> queueFor(String instructorId, DateTime day);

  // --- Notifications (in-app) ---
  List<AppNotification> notificationsFor(String userId);
  int unreadCount(String userId);
  Future<void> markAllRead(String userId);

  // --- Seed data ---
  Future<void> seedFirestore() async {} // Add to interface
}
