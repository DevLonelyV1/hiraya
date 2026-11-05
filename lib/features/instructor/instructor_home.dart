// OWNER: Person 1 (Lead) - the instructor shell with bottom navigation.
// Tabs are owned by other people:
//   Requests     -> review_requests_screen.dart  (Person 5)
//   Office hours -> office_hours_screen.dart     (Person 5)
//   Alerts       -> notifications_screen.dart    (Person 6)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/booking.dart';
import '../../state/app_state.dart';
import '../calendar/appointment_calendar_screen.dart';
import '../notifications/notifications_screen.dart';
import 'office_hours_screen.dart';
import 'review_requests_screen.dart';

class InstructorHome extends StatefulWidget {
  const InstructorHome({super.key});

  @override
  State<InstructorHome> createState() => _InstructorHomeState();
}

class _InstructorHomeState extends State<InstructorHome> {
  int _index = 0;

  static const _titles = [
    'Requests',
    'Office hours',
    'Calendar',
    'Notifications',
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final todo = state.repo
        .bookingsForInstructor(state.me.id)
        .where(
          (b) =>
              b.status == BookingStatus.pending ||
              b.status == BookingStatus.cancelRequested ||
              b.status == BookingStatus.changeRequested,
        )
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: state.logout,
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          ReviewRequestsScreen(),
          OfficeHoursScreen(),
          AppointmentCalendarScreen(),
          NotificationsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: todo > 0,
              label: Text('$todo'),
              child: const Icon(Icons.inbox_outlined),
            ),
            label: 'Requests',
          ),
          const NavigationDestination(
            icon: Icon(Icons.schedule),
            label: 'Office hours',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: state.unreadCount > 0,
              label: Text('${state.unreadCount}'),
              child: const Icon(Icons.notifications_outlined),
            ),
            label: 'Alerts',
          ),
        ],
      ),
    );
  }
}
