import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../models/app_user.dart';
import '../../models/booking.dart';
import '../../models/slot.dart';
import '../../state/app_state.dart';

class AppointmentCalendarScreen extends StatefulWidget {
  const AppointmentCalendarScreen({super.key});

  @override
  State<AppointmentCalendarScreen> createState() =>
      _AppointmentCalendarScreenState();
}

class _AppointmentCalendarScreenState extends State<AppointmentCalendarScreen> {
  late DateTime _month;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _month = DateTime(today.year, today.month);
    _selectedDay = DateTime(today.year, today.month, today.day);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.me;
    final source = user.role == UserRole.student
        ? state.repo.bookingsForStudent(user.id)
        : state.repo.bookingsForInstructor(user.id);
    final now = DateTime.now();
    final appointments = [
      for (final booking in source)
        if (booking.status.isActive)
          if (state.repo.slotById(booking.slotId) case final Slot slot)
            if (slot.end.isAfter(now))
              _CalendarAppointment(
                booking: booking,
                slot: slot,
                otherPerson: user.role == UserRole.student
                    ? state.repo.userById(booking.instructorId)?.name ??
                          'Instructor'
                    : state.repo.userById(booking.studentId)?.name ?? 'Student',
              ),
    ]..sort((a, b) => a.slot.start.compareTo(b.slot.start));
    final dayAppointments = appointments
        .where((appointment) => sameDay(appointment.slot.start, _selectedDay))
        .toList();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        Text(
          'Upcoming meetings',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your consultation schedule at a glance.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _MonthCalendar(
          month: _month,
          selectedDay: _selectedDay,
          appointments: appointments,
          onPrevious: () => _changeMonth(-1),
          onNext: () => _changeMonth(1),
          onSelectDay: (day) => setState(() {
            _selectedDay = day;
            _month = DateTime(day.year, day.month);
          }),
        ),
        const SizedBox(height: 22),
        Text(
          fmtDate(_selectedDay),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (dayAppointments.isEmpty)
          const EmptyState(
            icon: Icons.event_available_outlined,
            message: 'No upcoming meetings on this day.',
          )
        else
          ...dayAppointments.map(
            (appointment) => _AppointmentCard(appointment: appointment),
          ),
      ],
    );
  }

  void _changeMonth(int offset) {
    setState(() {
      _month = DateTime(_month.year, _month.month + offset);
      final lastDay = DateTime(_month.year, _month.month + 1, 0).day;
      _selectedDay = DateTime(
        _month.year,
        _month.month,
        _selectedDay.day.clamp(1, lastDay).toInt(),
      );
    });
  }
}

class _CalendarAppointment {
  const _CalendarAppointment({
    required this.booking,
    required this.slot,
    required this.otherPerson,
  });

  final Booking booking;
  final Slot slot;
  final String otherPerson;
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.selectedDay,
    required this.appointments,
    required this.onPrevious,
    required this.onNext,
    required this.onSelectDay,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<_CalendarAppointment> appointments;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onSelectDay;

  static const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _monthLabels = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cellCount = ((firstWeekday + daysInMonth + 6) ~/ 7) * 7;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${_monthLabels[month.month - 1]} ${month.year}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Row(
              children: [
                for (final label in _weekdayLabels)
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cellCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 2,
                childAspectRatio: 0.9,
              ),
              itemBuilder: (context, index) {
                final dayNumber = index - firstWeekday + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const SizedBox.shrink();
                }

                final day = DateTime(month.year, month.month, dayNumber);
                final isSelected = sameDay(day, selectedDay);
                final isToday = sameDay(day, DateTime.now());
                final hasAppointments = appointments.any(
                  (appointment) => sameDay(appointment.slot.start, day),
                );
                final foreground = isSelected
                    ? colors.onPrimary
                    : colors.onSurface;

                return Material(
                  color: isSelected ? colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onSelectDay(day),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: isToday && !isSelected
                              ? BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: colors.primary),
                                )
                              : null,
                          child: Text(
                            '$dayNumber',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: foreground,
                              fontWeight: isSelected || isToday
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasAppointments
                                ? (isSelected
                                      ? colors.onPrimary
                                      : colors.primary)
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.circle, size: 9, color: colors.primary),
                const SizedBox(width: 6),
                Text(
                  'Upcoming meeting',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appointment});

  final _CalendarAppointment appointment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final booking = appointment.booking;
    final slot = appointment.slot;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF1FF),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.event_note_rounded,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          appointment.otherPerson,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      StatusChip(booking.status),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(fmtRange(slot.start, slot.end)),
                  const SizedBox(height: 3),
                  Text(
                    booking.topic,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
