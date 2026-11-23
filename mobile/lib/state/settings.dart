import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../core/storage/local_db.dart';

/// User preferences, persisted in the Hive `settings` box.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.handlebarMode = false,
    this.voiceAlerts = true,
    this.vibrationAlerts = true,
    this.localeCode,
    this.introSeen = false,
  });

  /// Dark by default (night rides, OLED); follow-system and light supported.
  final ThemeMode themeMode;

  /// Sunlight / handlebar-mount mode: larger text + higher contrast.
  final bool handlebarMode;
  final bool voiceAlerts;
  final bool vibrationAlerts;

  /// null = follow the phone's language.
  final String? localeCode;
  final bool introSeen;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? handlebarMode,
    bool? voiceAlerts,
    bool? vibrationAlerts,
    String? Function()? localeCode,
    bool? introSeen,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        handlebarMode: handlebarMode ?? this.handlebarMode,
        voiceAlerts: voiceAlerts ?? this.voiceAlerts,
        vibrationAlerts: vibrationAlerts ?? this.vibrationAlerts,
        localeCode: localeCode != null ? localeCode() : this.localeCode,
        introSeen: introSeen ?? this.introSeen,
      );

  Map<String, dynamic> toMap() => {
        'theme': themeMode.name,
        'handlebar': handlebarMode,
        'voice': voiceAlerts,
        'vibration': vibrationAlerts,
        'locale': localeCode,
        'intro_seen': introSeen,
      };

  factory AppSettings.fromMap(Map<dynamic, dynamic> m) => AppSettings(
        themeMode: ThemeMode.values.asNameMap()[m['theme']] ?? ThemeMode.dark,
        handlebarMode: m['handlebar'] == true,
        voiceAlerts: m['voice'] != false,
        vibrationAlerts: m['vibration'] != false,
        localeCode: m['locale'] is String ? m['locale'] as String : null,
        introSeen: m['intro_seen'] == true,
      );
}

class SettingsStore {
  SettingsStore(this._box);

  final Box<dynamic> _box;
  static const String _key = 'app';

  AppSettings load() {
    final raw = _box.get(_key);
    return raw is Map ? AppSettings.fromMap(raw) : const AppSettings();
  }

  Future<void> save(AppSettings s) => _box.put(_key, s.toMap());
}

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(Hive.box<dynamic>(LocalDb.settingsBox)),
);

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsStoreProvider).load();

  Future<void> update(AppSettings Function(AppSettings) change) async {
    final next = change(state);
    state = next;
    await ref.read(settingsStoreProvider).save(next);
  }
}
