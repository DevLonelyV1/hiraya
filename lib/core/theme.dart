import 'package:flutter/material.dart';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3B5BDB));
  final textTheme = ThemeData.light().textTheme.apply(fontFamily: 'Roboto');

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF6F8FC),
    fontFamily: 'Roboto',
    textTheme: textTheme.copyWith(
      headlineSmall: textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.35),
      labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}
