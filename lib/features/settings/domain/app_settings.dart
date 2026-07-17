import 'package:flutter/material.dart';

/// Preferencias locales del conductor (persistidas en secure storage).
class AppSettings {
  final ThemeMode themeMode;
  final String languageCode;
  final bool notificationsEnabled;
  final bool tripAlertsEnabled;
  final bool keepScreenOn;
  final DateTime? lastSyncAt;
  final String appVersion;
  final String buildNumber;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.languageCode = 'es',
    this.notificationsEnabled = true,
    this.tripAlertsEnabled = true,
    this.keepScreenOn = false,
    this.lastSyncAt,
    this.appVersion = '1.0.0',
    this.buildNumber = '1',
  });

  String get themeLabel {
    switch (themeMode) {
      case ThemeMode.dark:
        return 'Oscuro';
      case ThemeMode.light:
        return 'Claro';
      case ThemeMode.system:
        return 'Sistema';
    }
  }

  String get languageLabel {
    switch (languageCode) {
      case 'en':
        return 'English';
      case 'es':
      default:
        return 'Español';
    }
  }

  String get versionLabel => 'v$appVersion ($buildNumber)';

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? languageCode,
    bool? notificationsEnabled,
    bool? tripAlertsEnabled,
    bool? keepScreenOn,
    DateTime? lastSyncAt,
    String? appVersion,
    String? buildNumber,
    bool clearLastSync = false,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      tripAlertsEnabled: tripAlertsEnabled ?? this.tripAlertsEnabled,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      lastSyncAt: clearLastSync ? null : (lastSyncAt ?? this.lastSyncAt),
      appVersion: appVersion ?? this.appVersion,
      buildNumber: buildNumber ?? this.buildNumber,
    );
  }

  static ThemeMode themeModeFromString(String? raw) {
    switch ((raw ?? 'system').toLowerCase()) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }
}
