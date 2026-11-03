// OWNER: Person 5 (Instructor)
// Use case: "Set office hours". Add/remove 30-minute consultation slots.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/booking_repository.dart';
import '../../models/slot.dart';
import '../../state/app_state.dart';

class OfficeHoursScreen extends StatelessWidget {
  const OfficeHoursScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = DateTime.now();
    final slots = state.repo
        .slotsFor(state.me.id)
        .where((s) => s.end.isAfter(now))
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSlot(context),
        icon: const Icon(Icons.add),
        label: const Text('Add slot'),
      ),
      body: slots.isEmpty
          ? const EmptyState(
              icon: Icons.schedule,
              message: 'No office hours yet.\nTap "Add slot" to publish one.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: slots.length,
              itemBuilder: (context, index) {
                final s = slots[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      s.isLocked ? Icons.lock : Icons.event_available,
                      color: s.isLocked ? Colors.orange : Colors.green,
                    ),
                    title: Text(fmtDate(s.start)),
                    subtitle: Text(fmtRange(s.start, s.end)),
                    trailing: s.isLocked
                        ? const Chip(label: Text('Booked'))
                         : Wrap(
                             spacing: 4,
                             children: [
                               IconButton(
                                 tooltip: 'Edit slot',
                                 icon: const Icon(Icons.edit_outlined),
                                 onPressed: () => _editSlot(context, s),
                               ),
                               IconButton(
                                 tooltip: 'Remove slot',
                                 icon: const Icon(Icons.delete_outline),
                                 onPressed: () => _remove(context, s.id),
                               ),
                             ],
                           ),
                  ),
                );
              },
            ),
    );
  }

  void _remove(BuildContext context, String slotId) {
    try {
      context.read<AppState>().removeSlot(slotId);
    } on SlotUnavailableException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
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
    final start = await _pickDateTime(context, DateTime.now().add(const Duration(days: 1)));
    if (start == null || !context.mounted) return;

    try {
      context
          .read<AppState>()
          .addSlot(start, start.add(const Duration(minutes: 30)));
    } on SlotUnavailableException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
    } on SlotUnavailableException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}
