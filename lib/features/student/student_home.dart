// OWNER: Person 1 (Lead) - the student shell with bottom navigation.
// Tabs are owned by other people:
//   Find      -> search_slots_screen.dart     (Person 3)
//   Bookings  -> my_bookings_screen.dart      (Person 4)
//   Alerts    -> notifications_screen.dart    (Person 6)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../calendar/appointment_calendar_screen.dart';
import '../notifications/notifications_screen.dart';
import 'my_bookings_screen.dart';
import 'search_slots_screen.dart';

class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  int _index = 0;

  static const _titles = [
    'Find a consultation',
    'Calendar',
    'My bookings',
    'Notifications',
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

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
          SearchSlotsScreen(),
          AppointmentCalendarScreen(),
          MyBookingsScreen(),
          NotificationsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.search), label: 'Find'),
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Calendar',
          ),
          const NavigationDestination(
            icon: Icon(Icons.event_note),
            label: 'Bookings',
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
