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
    if (decoded is! Map) {
      return null;
    }
    final payload = Map<String, dynamic>.from(decoded);
    final draft = DevicePairingDraftModel.fromStorageJson(payload);
    final normalized = draft.toStorageJson();
    if (_needsMigration(payload, normalized)) {
      await preferences.setString(_storageKey, jsonEncode(normalized));
    }
    return draft;
  }

  bool _needsMigration(
    Map<String, dynamic> current,
    Map<String, dynamic> normalized,
  ) {
    if (current.length != normalized.length) {
      return true;
    }
    for (final entry in normalized.entries) {
      if (current[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }
}
