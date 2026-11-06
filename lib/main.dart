import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:hiraya/firebase_options.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'data/booking_repository.dart';
import 'data/firebase_booking_repository.dart';
import 'data/in_memory_booking_repository.dart';
import 'features/auth/login_screen.dart';
import 'features/instructor/instructor_home.dart';
import 'features/student/student_home.dart';
import 'models/app_user.dart';
import 'state/app_state.dart';

const _useMock = bool.fromEnvironment('USE_MOCK');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final BookingRepository repo;
  if (_useMock) {
    repo = InMemoryBookingRepository();
  } else {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final firebaseRepo = FirebaseBookingRepository();
    await firebaseRepo.loadDemoUsers();
    repo = firebaseRepo;
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(repo),
      child: const ConsultApp(),
    ),
  );
}

class ConsultApp extends StatelessWidget {
  const ConsultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Student Consultation Appointment System',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const RootGate(),
      // On web, keep the app phone-sized so it looks like the real thing.
      builder: (context, child) {
        if (!kIsWeb) return child!;
        return ColoredBox(
          color: const Color(0xFFE4E9F2),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Shows login, or the student/instructor home depending on who is logged in.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().user;
    if (user == null) return const LoginScreen();
    return user.role == UserRole.student
        ? const StudentHome()
        : const InstructorHome();
  }
}
