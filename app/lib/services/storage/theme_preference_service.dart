import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemePreferenceService {
  static const String _storageKey = 'ai-bot.app.theme-mode';

  Future<void> saveThemeMode(ThemeMode themeMode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, _serialize(themeMode));
  }

  Future<ThemeMode?> loadThemeMode() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.dark,
    };
  }

  String _serialize(ThemeMode themeMode) {
    return themeMode == ThemeMode.light ? 'light' : 'dark';
  }
}
