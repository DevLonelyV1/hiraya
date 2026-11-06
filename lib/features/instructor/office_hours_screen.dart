// OWNER: Person 5 (Instructor)
// Use case: "Set office hours". Add/remove 30-minute consultation slots.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/booking_repository.dart';
import '../../models/instructor_availability.dart';
import '../../models/slot.dart';
import '../../state/app_state.dart';

class OfficeHoursScreen extends StatelessWidget {
  const OfficeHoursScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = DateTime.now();
    final slots =
        state.repo
            .slotsFor(state.me.id)
            .where((slot) => slot.end.isAfter(now))
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final availableCount = slots.where((slot) => !slot.isLocked).length;
    final bookedCount = slots.length - availableCount;
    final availability = state.repo.availabilityFor(state.me.id);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSlot(context),
        icon: const Icon(Icons.add),
        label: const Text('Add slot'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 104),
        children: [
          _DashboardBanner(
            name: state.me.name,
            department: state.me.department,
            greeting: _greeting(now),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Available',
                  detail: 'Open to students',
                  count: availableCount,
                  icon: Icons.event_available_rounded,
                  color: const Color(0xFF2E9D68),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  label: 'Booked',
                  detail: 'Reserved slots',
                  count: bookedCount,
                  icon: Icons.lock_clock_rounded,
                  color: const Color(0xFFE99A32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Weekly availability',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF20243A),
                  ),
                ),
              ),
              Text(
                '4-week view',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Set your bookable hours by day. Students can only book published slots.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ...availability.map(
            (schedule) => _AvailabilityDay(
              schedule: schedule,
              onTap: () => _editAvailability(context, schedule),
            ),
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Upcoming slots',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF20243A),
                  ),
                ),
              ),
              Text(
                '${slots.length} total',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Manage the times students can book with you.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          if (slots.isEmpty)
            _EmptySlots(onAdd: () => _addSlot(context))
          else
            ...slots.map(
              (slot) => _OfficeHourCard(
                date: slot.start,
                start: slot.start,
                end: slot.end,
                isBooked: slot.isLocked,
                onEdit: slot.isLocked ? null : () => _editSlot(context, slot),
                onRemove: slot.isLocked
                    ? null
                    : () => _remove(context, slot.id),
              ),
            ),
        ],
      ),
    );
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _editAvailability(
    BuildContext context,
    InstructorAvailability current,
  ) async {
    final updated = await showDialog<InstructorAvailability>(
      context: context,
      builder: (_) => _AvailabilityDialog(schedule: current),
    );
    if (updated == null || !context.mounted) return;

    try {
      final state = context.read<AppState>();
      final repo = state.repo;
      final now = DateTime.now();
      final firstDay = DateTime(now.year, now.month, now.day);
      final until = firstDay.add(const Duration(days: 28));
      final daySlots = repo
          .slotsFor(updated.instructorId)
          .where(
            (slot) =>
                slot.start.weekday == updated.weekday &&
                !slot.start.isBefore(firstDay) &&
                slot.start.isBefore(until),
          )
          .toList();
      var bookingConflicts = 0;

      for (final slot in daySlots) {
        if (slot.isLocked) {
          bookingConflicts++;
        } else {
          await state.removeSlot(slot.id);
        }
      }

      if (updated.isAvailable) {
        for (var offset = 0; offset < 28; offset++) {
          final day = firstDay.add(Duration(days: offset));
          if (day.weekday != updated.weekday) continue;

          for (
            var minute = updated.startMinute;
            minute + updated.slotMinutes <= updated.endMinute;
            minute += updated.slotMinutes
          ) {
            final start = DateTime(
              day.year,
              day.month,
              day.day,
              minute ~/ 60,
              minute % 60,
            );
            if (!start.isAfter(now)) continue;
            final end = start.add(Duration(minutes: updated.slotMinutes));
            final overlapsExisting = repo
                .slotsFor(updated.instructorId)
                .any(
                  (slot) =>
                      slot.isLocked &&
                      slot.start.isBefore(end) &&
                      start.isBefore(slot.end),
                );
            if (overlapsExisting) continue;
            await state.addSlot(start, end);
          }
        }
      }

      await state.saveAvailability(updated);
      if (context.mounted) {
        final message = updated.isAvailable
            ? 'Weekly hours saved for the next 4 weeks.'
            : 'Day marked unavailable for the next 4 weeks.';
        _showMessage(
          context,
          bookingConflicts == 0
              ? message
              : '$message $bookingConflicts booked slot(s) were kept.',
        );
      }
    } on SlotUnavailableException catch (error) {
      if (context.mounted) _showMessage(context, error.message);
    } on FirebaseException catch (error) {
      if (context.mounted) {
        _showMessage(context, 'Could not update availability: $error');
      }
    } on StateError catch (error) {
      if (context.mounted) {
        _showMessage(context, 'Could not update availability: $error');
      }
    }
  }

  Future<void> _remove(BuildContext context, String slotId) async {
    try {
      await context.read<AppState>().removeSlot(slotId);
      if (context.mounted) _showMessage(context, 'Office-hour slot removed.');
    } on SlotUnavailableException catch (error) {
      if (context.mounted) _showMessage(context, error.message);
    } on FirebaseException catch (error) {
      if (context.mounted) {
        _showMessage(context, 'Could not remove slot: $error');
      }
    } on StateError catch (error) {
      if (context.mounted) {
        _showMessage(context, 'Could not remove slot: $error');
      }
    }
  }

  Future<DateTime?> _pickDateTime(
    BuildContext context,
    DateTime initial,
  ) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (date == null || !context.mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !context.mounted) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _addSlot(BuildContext context) async {
    final start = await _pickDateTime(
      context,
      DateTime.now().add(const Duration(days: 1)),
    );
    if (start == null || !context.mounted) return;

    if (!start.isAfter(DateTime.now())) {
      _showMessage(context, 'Choose a future time for the office-hour slot.');
      return;
    }

    try {
      await context.read<AppState>().addSlot(
        start,
        start.add(const Duration(minutes: 30)),
      );
      if (context.mounted) _showMessage(context, 'Office-hour slot published.');
    } on SlotUnavailableException catch (error) {
      if (context.mounted) _showMessage(context, error.message);
    } on FirebaseException catch (error) {
      if (context.mounted) _showMessage(context, 'Could not add slot: $error');
    } on StateError catch (error) {
      if (context.mounted) _showMessage(context, 'Could not add slot: $error');
    }
  }

  Future<void> _editSlot(BuildContext context, Slot slot) async {
    final start = await _pickDateTime(context, slot.start);
    if (start == null || !context.mounted) return;
    try {
      await context.read<AppState>().updateSlot(
        slot.id,
        start,
        start.add(slot.end.difference(slot.start)),
      );
      if (context.mounted) _showMessage(context, 'Office-hour slot updated.');
    } on SlotUnavailableException catch (error) {
      if (context.mounted) _showMessage(context, error.message);
    } on FirebaseException catch (error) {
      if (context.mounted) _showMessage(context, 'Could not edit slot: $error');
    } on StateError catch (error) {
      if (context.mounted) _showMessage(context, 'Could not edit slot: $error');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DashboardBanner extends StatelessWidget {
  const _DashboardBanner({
    required this.name,
    required this.department,
    required this.greeting,
  });

  final String name;
  final String department;
  final String greeting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF3B5BDB), Color(0xFF536FE5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'INSTRUCTOR DASHBOARD',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.15,
                        ),
                      ),
                    ),
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      child: Text(
                        _initials(name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  '$greeting,',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (department.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    department,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            right: -40,
            bottom: -78,
            child: IgnorePointer(
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.09),
                    width: 28,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String value) {
    final parts = value.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts.isEmpty ? '?' : parts.first[0].toUpperCase();
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.detail,
    required this.count,
    required this.icon,
    required this.color,
  });

  final String label;
  final String detail;
  final int count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF20243A).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 12),
          Text(
            '$count',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: const Color(0xFF20243A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficeHourCard extends StatelessWidget {
  const _OfficeHourCard({
    required this.date,
    required this.start,
    required this.end,
    required this.isBooked,
    required this.onEdit,
    required this.onRemove,
  });

  final DateTime date;
  final DateTime start;
  final DateTime end;
  final bool isBooked;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = isBooked
        ? const Color(0xFFE99A32)
        : const Color(0xFF2E9D68);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9ECF4)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: isBooked
                  ? const Color(0xFFFFF5E8)
                  : const Color(0xFFEEF1FF),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              children: [
                Text(
                  _month(date.month),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isBooked ? statusColor : const Color(0xFF3B5BDB),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${date.day}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmtDate(date),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fmtRange(start, end),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      isBooked
                          ? Icons.lock_rounded
                          : Icons.check_circle_rounded,
                      size: 15,
                      color: statusColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isBooked ? 'Booked' : 'Available to students',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isBooked)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.lock_outline, color: Color(0xFFADB3C3)),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit slot',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined),
                  color: theme.colorScheme.onSurfaceVariant,
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'Remove slot',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: theme.colorScheme.onSurfaceVariant,
                  onPressed: onRemove,
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _month(int month) => const [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ][month - 1];
}

class _EmptySlots extends StatelessWidget {
  const _EmptySlots({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE9ECF4)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.calendar_month_rounded,
            size: 42,
            color: Color(0xFF3B5BDB),
          ),
          const SizedBox(height: 12),
          Text(
            'No upcoming slots',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Publish an office-hour time so students can book a consultation.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Create first slot'),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityDay extends StatelessWidget {
  const _AvailabilityDay({required this.schedule, required this.onTap});

  final InstructorAvailability schedule;
  final VoidCallback onTap;

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAvailable = schedule.isAvailable;
    final start = _timeOfDay(schedule.startMinute);
    final end = _timeOfDay(schedule.endMinute);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          isAvailable ? Icons.event_available : Icons.event_busy,
          color: isAvailable
              ? const Color(0xFF2E9D68)
              : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          _days[schedule.weekday - 1],
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          isAvailable
              ? '${fmtTime(DateTime(2000, 1, 1, start.hour, start.minute))} – '
                    '${fmtTime(DateTime(2000, 1, 1, end.hour, end.minute))}'
              : 'Unavailable for bookings',
        ),
        trailing: const Icon(Icons.edit_outlined),
      ),
    );
  }

  static TimeOfDay _timeOfDay(int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
}

class _AvailabilityDialog extends StatefulWidget {
  const _AvailabilityDialog({required this.schedule});

  final InstructorAvailability schedule;

  @override
  State<_AvailabilityDialog> createState() => _AvailabilityDialogState();
}

class _AvailabilityDialogState extends State<_AvailabilityDialog> {
  late bool _isAvailable;
  late TimeOfDay _start;
  late TimeOfDay _end;

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _isAvailable = widget.schedule.isAvailable;
    _start = _AvailabilityDay._timeOfDay(widget.schedule.startMinute);
    _end = _AvailabilityDay._timeOfDay(widget.schedule.endMinute);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${_days[widget.schedule.weekday - 1]} hours'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Available for bookings'),
          value: _isAvailable,
          onChanged: (value) => setState(() => _isAvailable = value),
        ),
        const SizedBox(height: 8),
        Text(
          'Appointment length: ${widget.schedule.slotMinutes} minutes',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickTime(isStart: true),
                child: Text('From ${_start.format(context)}'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _pickTime(isStart: false),
            child: Text('Until ${_end.format(context)}'),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save hours')),
    ],
  );

  Future<void> _pickTime({required bool isStart}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = selected;
      } else {
        _end = selected;
      }
    });
  }

  void _save() {
    final startMinute = _start.hour * 60 + _start.minute;
    final endMinute = _end.hour * 60 + _end.minute;
    if (endMinute <= startMinute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }

    Navigator.pop(
      context,
      widget.schedule.copyWith(
        isAvailable: _isAvailable,
        startMinute: startMinute,
        endMinute: endMinute,
      ),
    );
  }
}
