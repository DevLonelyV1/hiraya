// OWNER: Person 3 (Student booking)
// Shows one instructor's open slots grouped by day.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../models/app_user.dart';
import '../../models/slot.dart';
import '../../state/app_state.dart';
import 'book_consultation_screen.dart';

class InstructorSlotsScreen extends StatelessWidget {
  const InstructorSlotsScreen({super.key, required this.instructor});

  final AppUser instructor;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final slots = state.repo.slotsFor(instructor.id, onlyAvailable: true);

    final byDay = <DateTime, List<Slot>>{};
    for (final s in slots) {
      final key = DateTime(s.start.year, s.start.month, s.start.day);
      byDay.putIfAbsent(key, () => []).add(s);
    }

    return Scaffold(
      appBar: AppBar(title: Text(instructor.name)),
      body: slots.isEmpty
          ? const EmptyState(
              icon: Icons.event_busy,
              message: 'No open slots right now.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${instructor.name} - tap a time to book.'),
                const SizedBox(height: 8),
                for (final entry in byDay.entries) ...[
                  SectionHeader(fmtDate(entry.key)),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in entry.value)
                        ActionChip(
                          label: Text(fmtRange(s.start, s.end)),
                          onPressed: () => _onSlotTap(context, s),
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _onSlotTap(BuildContext context, Slot slot) async {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BookConsultationScreen(slot: slot)),
    );
  }
}
