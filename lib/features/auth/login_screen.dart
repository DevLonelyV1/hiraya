// OWNER: Person 2 (Auth & roles)
// Starter: demo login where you tap an account. Upgrade ideas: email/password
// form with demo credentials, remember last user, nicer branding.

import 'package:flutter/material.dart';
import 'package:hiraya/data/firebase_booking_repository.dart';
import 'package:provider/provider.dart';

import '../../core/widgets.dart';
import '../../models/app_user.dart';
import '../../state/app_state.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final users = state.repo.users;
    final students = users.where((u) => u.role == UserRole.student);
    final instructors = users.where((u) => u.role == UserRole.instructor);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Inside LoginScreen build method children list:
            const SizedBox(height: 32),
            if (state.repo is FirebaseBookingRepository)
              OutlinedButton.icon(
                onPressed: () async {
                  final repo = context.read<AppState>().repo;
                  if (repo is! FirebaseBookingRepository) return;
                  try {
                    await repo.seedFirestore();
                    await repo.loadDemoUsers();

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Database seeded successfully! Refreshing...',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Seeding failed: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Seed Firestore Demo Data'),
              ),
            const SizedBox(height: 24),
            Icon(
              Icons.event_available,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Student Consultation\nAppointment System',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Demo login - pick an account',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            const SectionHeader('Students'),
            ...students.map((u) => _UserTile(user: u)),
            const SizedBox(height: 8),
            const SectionHeader('Instructors'),
            ...instructors.map((u) => _UserTile(user: u)),
          ],
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Text(user.initials)),
        title: Text(user.name),
        subtitle: Text(user.department),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          try {
            await context.read<AppState>().signInDemo(user);
          } catch (e) {
            if (!context.mounted) return;

            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(e.toString())));
          }
        },
      ),
    );
  }
}
