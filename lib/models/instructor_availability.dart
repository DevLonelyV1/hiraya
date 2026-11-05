class InstructorAvailability {
  const InstructorAvailability({
    required this.instructorId,
    required this.weekday,
    required this.isAvailable,
    required this.startMinute,
    required this.endMinute,
    this.slotMinutes = 30,
  }) : assert(weekday >= DateTime.monday && weekday <= DateTime.sunday),
       assert(startMinute >= 0 && startMinute < 24 * 60),
       assert(endMinute >= 0 && endMinute <= 24 * 60),
       assert(slotMinutes > 0);

  final String instructorId;
  final int weekday;
  final bool isAvailable;
  final int startMinute;
  final int endMinute;
  final int slotMinutes;

  static const defaultStartMinute = 9 * 60;
  static const defaultEndMinute = 12 * 60;
  static const defaultSlotMinutes = 30;

  static List<InstructorAvailability> defaults(String instructorId) => [
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
      InstructorAvailability(
        instructorId: instructorId,
        weekday: weekday,
        isAvailable: weekday <= DateTime.friday,
        startMinute: defaultStartMinute,
        endMinute: defaultEndMinute,
      ),
  ];

  InstructorAvailability copyWith({
    bool? isAvailable,
    int? startMinute,
    int? endMinute,
  }) => InstructorAvailability(
    instructorId: instructorId,
    weekday: weekday,
    isAvailable: isAvailable ?? this.isAvailable,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
    slotMinutes: slotMinutes,
  );
}
