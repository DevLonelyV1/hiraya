# Student Consultation Appointment System

A Flutter mobile app where students book consultations with instructors, track their
queue position, and get notified. Built for STI Caloocan.

**Current iteration:** Iteration 1 (about 30% of the full app) - the **Appointment & Queue subsystem**.
**Data:** Firebase by default; use the in-memory mock for local demos (resets when the app restarts).
**Targets:** Android emulator (main), Flutter web in a phone-sized window (backup).

**Team lead:** Emanuel Czire C. Haber  |  **Group:** Hiraya
**Developer:** Adhrian Joaquin A. Penaflor 

---

## 1. Quick start

You need Flutter installed and an Android emulator (or Chrome).

```bash
git clone <repo-url>
cd consult_app
flutter pub get
flutter run              # Firebase-backed app
# or: flutter run -d chrome
```

For an offline instructor-workflow demo with seeded requests, run:

```bash
flutter run -d emulator-5554 --dart-define=USE_MOCK=true
```

Choose any instructor to see their own office hours and request dashboard.
Prof. Reyes has proposed canceling Ana's consultation; sign in as Ana to approve
or decline the request. Prof. Santos and Prof. Dela Cruz have their own pending
and confirmed sessions. Student accounts show
their individual booking summaries, next consultation, and faculty search.
Mock bookings and slot changes reset when the app restarts.

Instructor office hours use a default Monday-Friday, 9:00 AM-12:00 PM weekly
schedule, with weekends off and 30-minute slots. Instructors can edit each
weekday or mark it unavailable; changes publish slots for the next four weeks.
Already-booked appointments are retained when a day or time range changes.
Both roles have a Calendar tab showing their own upcoming booked meetings.
Firebase weekly settings are stored under the instructor's
`users/{instructorId}.availabilitySchedules` field.

Students and instructors can propose a cancellation or a reschedule with a
reason. A reschedule proposal reserves an available instructor slot while the
other participant reviews it. The booking changes only after the other person
approves; declining releases the proposed slot and keeps the original booking.
Requests and approvals must happen at least three hours before the existing
appointment, and reschedule times must also be at least three hours away.
Both participants receive in-app notifications for proposals and decisions.

---

## 2. Project structure

```
lib/
  main.dart                  App entry, routes to login / student / instructor
  core/                      Theme, shared widgets, date formatting
  models/                    User, Slot, Booking, Notification
  data/
    booking_repository.dart  THE CONTRACT (interface everyone codes against)
    in_memory_booking_repository.dart  In-memory data + business rules
  state/
    app_state.dart           App-wide state (logged-in user + actions)
  features/
    auth/                    Login
    student/                 Find slots, book, my bookings, queue
    instructor/              Office hours, review requests
    notifications/           Notification list
test/                        Unit and widget tests
```

### How data flows

```
Screen  ->  AppState (action)  ->  BookingRepository  ->  data
Screen  <-  notifyListeners()  <-  (state changed)
```

- **Read** data with `context.watch<AppState>()`, then `state.repo.something()`.
- **Change** data only through `AppState` methods. Never edit models directly from a screen.

### Booking status flow

```
pending --approve--> confirmed --complete--> completed
pending --reject---> rejected
pending/confirmed --either party proposes a change--> changeRequested
changeRequested --other party approves--> confirmed or canceled
changeRequested --other party declines--> previous status
```

Queue position is calculated, not stored: earlier active bookings for the same
instructor on the same day, plus 1.

---

## 3. Who owns what

Only edit the files in **your** row.

| # | Role | Name | Files |
|---|------|------|-------|
| 1 | Lead / foundation | Czire Haber | `main.dart`, `core/*`, `models/*`, `data/*`, `state/*`, `student_home.dart`, `instructor_home.dart` |
| 2 | Auth & roles | [Name] | `features/auth/login_screen.dart` |
| 3 | Student booking | [Name] | `student/search_slots_screen.dart`, `student/instructor_slots_screen.dart`, `student/book_consultation_screen.dart` |
| 4 | Student bookings | [Name] | `student/my_bookings_screen.dart` |
| 5 | Instructor | [Name] | `instructor/review_requests_screen.dart`, `instructor/office_hours_screen.dart` |
| 6 | Notifications & QA | [Name] | `notifications/notifications_screen.dart`, `test/*`, demo script |

Notes:
- Person 4 reuses `InstructorSlotsScreen(rescheduleBookingId: ...)` from Person 3 for rescheduling. Do not rename it.
- Need a new field, method, status or package? **Ask the lead.** Do not edit `models/*`, `data/*`, `pubspec.yaml` or `main.dart` yourself.

---

## 4. Git workflow

**Never work or push directly on `main`.**

```bash
# 1. Start from the latest main
git checkout main
git pull origin main

# 2. Create your branch
git checkout -b feature/<yourname>-<thing>     # e.g. feature/ana-booking-form

# 3. Work, commit small and often
git add .
git commit -m "Add booking form validation"

# 4. Before opening a PR
git pull --rebase origin main
flutter analyze                                # must have no errors

# 5. Push and open a Pull Request into main
git push -u origin feature/<yourname>-<thing>
```

### 15.2 Commit your changes

Make small, focused commits with meaningful messages.

```bash
git add <files>
git commit -m "feat: add student appointment booking"
```

Do not wait until the entire feature is finished before committing. Commit whenever you complete a logical piece of work.

### 15.3 Commit message convention

All team members must follow **Conventional Commits**.

**Format:**

```text
<type>: <short description>
```

Use the following commit types:

| Type | When to use it | Example |
|---|---|---|
| `feat` | Adds a new feature or capability | `feat: add student login screen` |
| `fix` | Fixes incorrect or broken behavior | `fix: prevent duplicate slot bookings` |
| `refactor` | Restructures code without intentionally changing behavior | `refactor: simplify booking repository logic` |
| `test` | Adds or updates automated tests | `test: add booking validation tests` |
| `docs` | Adds or updates documentation | `docs: update project README` |
| `chore` | Performs general maintenance | `chore: remove unused dependencies` |
| `style` | Changes formatting without changing program behavior | `style: format booking screen widgets` |
| `perf` | Improves performance | `perf: optimize appointment filtering` |
| `build` | Changes build configuration or dependency setup | `build: update Flutter package dependencies` |
| `ci` | Changes continuous integration workflows | `ci: add automated Flutter analysis` |

### Pull request checklist
Copy this into your PR description:

```bash
## What I built

Describe the feature or fix.

## How to test it

List the steps needed to verify the changes.

## Checklist

- [ ] flutter analyze passes
- [ ] flutter test passes
- [ ] The app runs and the feature works
- [ ] I edited only files I own or changes approved by the lead
- [ ] I rebased against the latest main
- [ ] No secrets or unnecessary files were committed
```

The team lead reviews the code, verifies the changes, and merges approved pull requests using the agreed merge strategy.


The lead reviews and merges (Squash and merge). Keep PRs small: one screen or feature each.

### Merge conflicts
The author of the PR resolves it:

```bash
git pull --rebase origin main
# open each conflicted file, keep the right code, delete the <<<<<<< ======= >>>>>>> markers
git add <file>
git rebase --continue
flutter analyze && flutter run
git push --force-with-lease
```
Stuck? `git rebase --abort` undoes the attempt, then ask the lead.

---

## 5. Team collaboration rules

1. Work on assigned branches, not directly on `main`.
2. Follow the commit message convention.
3. Respect file ownership and obtain approval for shared-code changes.
4. Keep pull requests focused and easy to review.
5. Run `flutter analyze` and `flutter test` before submitting changes.
6. Communicate when a pull request is opened or work becomes blocked.
7. Coordinate changes to models, repository interfaces, application state, routing, and dependencies with the team lead.
8. Merge only reviewed and verified pull requests.
9. After the agreed feature freeze, prioritize bug fixes and stability.
10. Do not commit passwords, API keys, access tokens, or production credentials.
