import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hiraya/data/in_memory_booking_repository.dart';
import 'package:hiraya/models/booking.dart';
import 'package:hiraya/models/booking_change_policy.dart';
import 'package:hiraya/models/slot.dart';
import 'package:hiraya/state/app_state.dart';
import 'package:hiraya/features/student/my_bookings_screen.dart';

void main() {
  group('booking change cutoff', () {
    final now = DateTime(2026, 11, 4, 9);

    test('requires more than three hours before the appointment', () {
      expect(
        isBeforeBookingChangeCutoff(
          now.add(const Duration(hours: 3, milliseconds: 1)),
          now: now,
        ),
        isTrue,
      );
      expect(
        isBeforeBookingChangeCutoff(
          now.add(const Duration(hours: 3)),
          now: now,
        ),
        isFalse,
      );
      expect(
        isBeforeBookingChangeCutoff(
          now.add(const Duration(hours: 2, minutes: 59)),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('mutual booking changes', () {
    late InMemoryBookingRepository repo;
    late Booking booking;
    late Slot originalSlot;
    late Slot proposedSlot;

    setUp(() {
      repo = InMemoryBookingRepository();
      booking = repo
          .bookingsForInstructor('i1')
          .firstWhere((entry) => entry.status == BookingStatus.confirmed);
      originalSlot = repo.slotById(booking.slotId)!;
      proposedSlot = repo.slotsFor('i1', onlyAvailable: true).first;
    });

    test(
      'accepting a reschedule releases the old slot and keeps the new one',
      () async {
        final studentNotificationCount = repo
            .notificationsFor(booking.studentId)
            .length;
        final instructorNotificationCount = repo
            .notificationsFor(booking.instructorId)
            .length;
        await repo.requestBookingChange(
          bookingId: booking.id,
          requesterId: booking.studentId,
          reason: 'I have a class schedule conflict.',
          proposedSlotId: proposedSlot.id,
        );

        expect(booking.status, BookingStatus.changeRequested);
        expect(originalSlot.isLocked, isTrue);
        expect(proposedSlot.isLocked, isTrue);
        expect(proposedSlot.inQueue, isFalse);
        expect(
          repo.notificationsFor(booking.studentId),
          hasLength(studentNotificationCount + 1),
        );
        expect(
          repo.notificationsFor(booking.instructorId),
          hasLength(instructorNotificationCount + 1),
        );
        expect(
          repo
              .notificationsFor(booking.instructorId)
              .any(
                (notification) =>
                    notification.message.contains('class schedule conflict'),
              ),
          isTrue,
        );

        await repo.reviewBookingChange(
          bookingId: booking.id,
          reviewerId: booking.instructorId,
          approve: true,
        );

        expect(booking.status, BookingStatus.confirmed);
        expect(booking.slotId, proposedSlot.id);
        expect(originalSlot.isLocked, isFalse);
        expect(proposedSlot.isLocked, isTrue);
        expect(proposedSlot.inQueue, isTrue);
        expect(booking.changeReason, isNull);
        expect(
          repo.notificationsFor(booking.studentId),
          hasLength(studentNotificationCount + 2),
        );
        expect(
          repo.notificationsFor(booking.instructorId),
          hasLength(instructorNotificationCount + 2),
        );
      },
    );

    test('declining a reschedule releases only the proposed slot', () async {
      final studentNotificationCount = repo
          .notificationsFor(booking.studentId)
          .length;
      final instructorNotificationCount = repo
          .notificationsFor(booking.instructorId)
          .length;
      await repo.requestBookingChange(
        bookingId: booking.id,
        requesterId: booking.instructorId,
        reason: 'I need to attend an urgent faculty meeting.',
        proposedSlotId: proposedSlot.id,
      );

      await repo.reviewBookingChange(
        bookingId: booking.id,
        reviewerId: booking.studentId,
        approve: false,
      );

      expect(booking.status, BookingStatus.confirmed);
      expect(booking.slotId, originalSlot.id);
      expect(originalSlot.isLocked, isTrue);
      expect(proposedSlot.isLocked, isFalse);
      expect(booking.changeRequestedBy, isNull);
      expect(
        repo.notificationsFor(booking.studentId),
        hasLength(studentNotificationCount + 2),
      );
      expect(
        repo.notificationsFor(booking.instructorId),
        hasLength(instructorNotificationCount + 2),
      );
    });

    test(
      'cancellation takes effect only after the other person approves',
      () async {
        final studentNotificationCount = repo
            .notificationsFor(booking.studentId)
            .length;
        final instructorNotificationCount = repo
            .notificationsFor(booking.instructorId)
            .length;
        await repo.requestBookingChange(
          bookingId: booking.id,
          requesterId: booking.instructorId,
          reason: 'I will be away from campus that day.',
        );

        expect(booking.status, BookingStatus.changeRequested);
        expect(originalSlot.isLocked, isTrue);
        expect(
          repo.notificationsFor(booking.studentId),
          hasLength(studentNotificationCount + 1),
        );
        expect(
          repo.notificationsFor(booking.instructorId),
          hasLength(instructorNotificationCount + 1),
        );

        await repo.reviewBookingChange(
          bookingId: booking.id,
          reviewerId: booking.studentId,
          approve: true,
        );

        expect(booking.status, BookingStatus.canceled);
        expect(originalSlot.isLocked, isFalse);
        expect(originalSlot.inQueue, isFalse);
        expect(
          repo.notificationsFor(booking.studentId),
          hasLength(studentNotificationCount + 2),
        );
        expect(
          repo.notificationsFor(booking.instructorId),
          hasLength(instructorNotificationCount + 2),
        );
      },
    );

    test(
      'mock demo includes an instructor cancellation for student approval',
      () {
        final request = repo
            .bookingsForInstructor('i1')
            .firstWhere(
              (entry) => entry.status == BookingStatus.changeRequested,
            );

        expect(request.changeRequestedBy, 'i1');
        expect(request.changeReason, contains('urgent faculty commitment'));
        expect(request.changeIsCancellation, isTrue);
        expect(
          repo
              .notificationsFor('s1')
              .any(
                (notification) => notification.message.contains('Prof. Reyes'),
              ),
          isTrue,
        );
      },
    );

    test(
      'student can approve instructor cancellation and release the slot',
      () async {
        final request = repo
            .bookingsForInstructor('i1')
            .firstWhere(
              (entry) => entry.status == BookingStatus.changeRequested,
            );
        final slot = repo.slotById(request.slotId)!;

        await repo.reviewBookingChange(
          bookingId: request.id,
          reviewerId: request.studentId,
          approve: true,
        );

        expect(request.status, BookingStatus.canceled);
        expect(slot.isLocked, isFalse);
        expect(slot.inQueue, isFalse);
        expect(
          repo
              .notificationsFor(request.studentId)
              .any(
                (notification) => notification.message.contains('You approved'),
              ),
          isTrue,
        );
        expect(
          repo
              .notificationsFor(request.instructorId)
              .any(
                (notification) =>
                    notification.message.contains('approved your cancellation'),
              ),
          isTrue,
        );
      },
    );

    test('student can approve an instructor-proposed reschedule', () async {
      final request = repo
          .bookingsForInstructor('i1')
          .firstWhere((entry) => entry.status == BookingStatus.confirmed);
      final originalSlot = repo.slotById(request.slotId)!;
      final proposedSlot = repo.slotsFor('i1', onlyAvailable: true).first;

      await repo.requestBookingChange(
        bookingId: request.id,
        requesterId: request.instructorId,
        reason: 'I have an urgent faculty commitment at the original time.',
        proposedSlotId: proposedSlot.id,
      );

      await repo.reviewBookingChange(
        bookingId: request.id,
        reviewerId: request.studentId,
        approve: true,
      );

      expect(request.status, BookingStatus.confirmed);
      expect(request.slotId, proposedSlot.id);
      expect(originalSlot.isLocked, isFalse);
      expect(proposedSlot.isLocked, isTrue);
      expect(proposedSlot.inQueue, isTrue);
    });

    test(
      'requires a meaningful reason and the other participant to review',
      () async {
        await expectLater(
          repo.requestBookingChange(
            bookingId: booking.id,
            requesterId: booking.studentId,
            reason: 'No.',
          ),
          throwsA(isA<StateError>()),
        );

        await repo.requestBookingChange(
          bookingId: booking.id,
          requesterId: booking.studentId,
          reason: 'I have a class schedule conflict.',
        );

        await expectLater(
          repo.reviewBookingChange(
            bookingId: booking.id,
            reviewerId: booking.studentId,
            approve: true,
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('student booking actions', () {
    late InMemoryBookingRepository repo;
    late AppState state;
    late Booking instructorCancellation;

    setUp(() async {
      repo = InMemoryBookingRepository();
      state = AppState(repo);
      await state.signInDemo(repo.userById('s1')!);
      instructorCancellation = repo
          .bookingsForStudent('s1')
          .firstWhere((entry) => entry.status == BookingStatus.changeRequested);
    });

    tearDown(() {
      state.dispose();
    });

    Widget buildBookingsScreen() => ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: MyBookingsScreen())),
    );

    testWidgets('student can approve a professor cancellation', (tester) async {
      await tester.pumpWidget(buildBookingsScreen());
      await tester.ensureVisible(find.text('Approve cancellation'));
      await tester.pumpAndSettle();

      expect(find.text('Decline cancellation'), findsOneWidget);
      await tester.tap(find.text('Approve cancellation'));
      await tester.pumpAndSettle();

      expect(instructorCancellation.status, BookingStatus.canceled);
      expect(repo.slotById(instructorCancellation.slotId)!.isLocked, isFalse);
    });

    testWidgets('student can decline a professor cancellation', (tester) async {
      await tester.pumpWidget(buildBookingsScreen());
      await tester.ensureVisible(find.text('Decline cancellation'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Decline cancellation'));
      await tester.pumpAndSettle();

      expect(instructorCancellation.status, BookingStatus.confirmed);
      expect(repo.slotById(instructorCancellation.slotId)!.isLocked, isTrue);
    });
  });
}
