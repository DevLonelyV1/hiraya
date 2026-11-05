// OWNER: Person 3 (Student booking)
// Use case: "Search faculty slots". Search a professor, then tap to see slots.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../models/booking.dart';
import '../../state/app_state.dart';
import 'instructor_slots_screen.dart';

class SearchSlotsScreen extends StatefulWidget {
  const SearchSlotsScreen({super.key});

  @override
  State<SearchSlotsScreen> createState() => _SearchSlotsScreenState();
}

class _SearchSlotsScreenState extends State<SearchSlotsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final bookings = state.repo.bookingsForStudent(state.me.id);
    final active = bookings
        .where((booking) => booking.status.isActive)
        .toList();
    final pendingCount = active
        .where(
          (booking) =>
              booking.status == BookingStatus.pending ||
              booking.status == BookingStatus.cancelRequested ||
              booking.status == BookingStatus.changeRequested,
        )
        .length;
    final confirmedCount = active
        .where((booking) => booking.status == BookingStatus.confirmed)
        .length;
    final nextBooking = _nextBooking(state, active);
    final instructors = state.repo.instructors
        .where(
          (instructor) =>
              instructor.name.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _StudentWelcomeCard(
          name: state.me.name,
          department: state.me.department,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _StudentMetric(
              label: 'Upcoming',
              count: active.length,
              icon: Icons.event_available_rounded,
              color: const Color(0xFF3B5BDB),
            ),
            const SizedBox(width: 10),
            _StudentMetric(
              label: 'Awaiting',
              count: pendingCount,
              icon: Icons.hourglass_top_rounded,
              color: const Color(0xFFE99A32),
            ),
            const SizedBox(width: 10),
            _StudentMetric(
              label: 'Confirmed',
              count: confirmedCount,
              icon: Icons.check_circle_outline_rounded,
              color: const Color(0xFF2E9D68),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Your next consultation',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (nextBooking == null)
          const _NoUpcomingBooking()
        else
          _NextBookingCard(booking: nextBooking),
        const SizedBox(height: 24),
        Text(
          'Find a faculty member',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Browse open office hours and request a time that works for you.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search faculty',
            filled: true,
            fillColor: theme.colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 14),
        if (instructors.isEmpty)
          const SizedBox(
            height: 220,
            child: EmptyState(
              icon: Icons.person_search,
              message: 'No faculty found.',
            ),
          )
        else
          ...instructors.map((instructor) {
            final open = state.repo
                .slotsFor(instructor.id, onlyAvailable: true)
                .length;
            return _InstructorCard(
              name: instructor.name,
              initials: instructor.initials,
              department: instructor.department,
              openSlots: open,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => InstructorSlotsScreen(instructor: instructor),
                ),
              ),
            );
          }),
      ],
    );
  }

  Booking? _nextBooking(AppState state, List<Booking> active) {
    final now = DateTime.now();
    final upcoming =
        active.where((booking) {
          final slot = state.repo.slotById(booking.slotId);
          return slot != null && slot.end.isAfter(now);
        }).toList()..sort((a, b) {
          final aStart = state.repo.slotById(a.slotId)!.start;
          final bStart = state.repo.slotById(b.slotId)!.start;
          return aStart.compareTo(bStart);
        });
    return upcoming.firstOrNull;
  }
}

class _StudentWelcomeCard extends StatelessWidget {
  const _StudentWelcomeCard({required this.name, required this.department});

  final String name;
  final String department;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B5BDB), Color(0xFF536FE5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STUDENT DASHBOARD',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hi, ${name.split(' ').first}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  department,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 25,
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

class _StudentMetric extends StatelessWidget {
  const _StudentMetric({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE9ECF4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(height: 7),
            Text(
              '$count',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextBookingCard extends StatelessWidget {
  const _NextBookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    final slot = repo.slotById(booking.slotId);
    final instructor = repo.userById(booking.instructorId);
    if (slot == null) return const _NoUpcomingBooking();

    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E7F5)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF1FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  _month(slot.start.month),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${slot.start.day}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  instructor?.name ?? 'Instructor',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(fmtDate(slot.start)),
                Text(
                  fmtRange(slot.start, slot.end),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(booking.status),
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

class _NoUpcomingBooking extends StatelessWidget {
  const _NoUpcomingBooking();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9ECF4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_available, color: Color(0xFF3B5BDB)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No upcoming consultations. Browse faculty office hours below.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructorCard extends StatelessWidget {
  const _InstructorCard({
    required this.name,
    required this.initials,
    required this.department,
    required this.openSlots,
    required this.onTap,
  });

  final String name;
  final String initials;
  final String department;
  final int openSlots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFEEF1FF),
          foregroundColor: theme.colorScheme.primary,
          child: Text(
            initials,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(
          name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text('$department · $openSlots open slots'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
