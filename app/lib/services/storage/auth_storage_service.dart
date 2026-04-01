import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/connect/connection_config_model.dart';

class AuthStorageService {
  static const String _storageKey = 'ai-bot.app.connection';

  Future<void> saveConnection(ConnectionConfigModel connection) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(connection.toJson()));
  }

  Future<ConnectionConfigModel?> loadConnection() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return ConnectionConfigModel.fromJson(decoded);
  }
}
