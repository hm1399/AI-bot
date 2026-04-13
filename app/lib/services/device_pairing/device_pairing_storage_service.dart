import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_pairing/device_pairing_draft_model.dart';

class DevicePairingStorageService {
  static const String _storageKey = 'ai-bot.device-pairing.defaults';

  Future<void> saveDraft(DevicePairingDraftModel draft) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(draft.toStorageJson()));
  }

  Future<DevicePairingDraftModel?> loadDraft() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return DevicePairingDraftModel.fromStorageJson(decoded);
  }
}
