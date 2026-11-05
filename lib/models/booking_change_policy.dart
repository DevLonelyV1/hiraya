const bookingChangeCutoff = Duration(hours: 3);

bool isBeforeBookingChangeCutoff(DateTime appointmentStart, {DateTime? now}) =>
    appointmentStart.isAfter((now ?? DateTime.now()).add(bookingChangeCutoff));

String? bookingChangeReasonError(String reason) {
  final normalized = reason.trim();
  if (normalized.length < 10) {
    return 'Please provide a reason of at least 10 characters.';
  }
  if (normalized.length > 300) {
    return 'Please keep the reason to 300 characters or fewer.';
  }
  return null;
}
