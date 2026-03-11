import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 4.0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      elevation: 8.0,
      type: BottomNavigationBarType.fixed,
    ),
    cardTheme: CardTheme(
      elevation: 2.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 4.0,
    ),
    textTheme: TextTheme(
      headlineSmall: const TextStyle(
        fontWeight: FontWeight.bold,
      ),
      bodyLarge: const TextStyle(),
      bodySmall: TextStyle(
        color: Colors.grey.shade600,
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 4.0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      elevation: 8.0,
      type: BottomNavigationBarType.fixed,
    ),
    cardTheme: CardTheme(
      elevation: 2.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 4.0,
    ),
    textTheme: TextTheme(
      headlineSmall: const TextStyle(
        fontWeight: FontWeight.bold,
      ),
      bodyLarge: const TextStyle(),
      bodySmall: TextStyle(
        color: Colors.grey.shade400,
      ),
    ),
  );
}