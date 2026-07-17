import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tracking_system_app/core/config/constants.dart';
import 'package:tracking_system_app/core/services/storage_service.dart';
import 'package:tracking_system_app/features/settings/domain/app_settings.dart';

class SettingsService {
  static SettingsService? _instance;
  static SettingsService get instance => _instance ??= SettingsService._();
  SettingsService._();

  final _storage = StorageService.instance;

  Future<AppSettings> load() async {
    final themeRaw = await _storage.getThemeMode();
    final language = await _storage.getLanguage();
    final notifications = await _storage.getNotificationsEnabled();
    final tripAlerts = await _storage.getTripAlertsEnabled();
    final keepScreen = await _storage.getKeepScreenOn();
    final lastSync = await _storage.getLastSync();

    var version = AppConstants.appVersion;
    var build = AppConstants.appBuildNumber;
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (e) {
      debugPrint('SettingsService packageInfo: $e');
    }

    return AppSettings(
      themeMode: AppSettings.themeModeFromString(themeRaw),
      languageCode: (language == null || language.isEmpty) ? 'es' : language,
      notificationsEnabled: notifications,
      tripAlertsEnabled: tripAlerts,
      keepScreenOn: keepScreen,
      lastSyncAt: lastSync,
      appVersion: version,
      buildNumber: build,
    );
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    await _storage.saveThemeMode(AppSettings.themeModeToString(mode));
  }

  Future<void> saveLanguage(String code) async {
    await _storage.saveLanguage(code);
  }

  Future<void> saveNotificationsEnabled(bool value) async {
    await _storage.saveNotificationsEnabled(value);
  }

  Future<void> saveTripAlertsEnabled(bool value) async {
    await _storage.saveTripAlertsEnabled(value);
  }

  Future<void> saveKeepScreenOn(bool value) async {
    await _storage.saveKeepScreenOn(value);
  }

  Future<void> markSyncedNow() async {
    await _storage.saveLastSync(DateTime.now());
  }

  /// Limpia preferencias no críticas (no borra tokens de sesión).
  Future<void> clearLocalPreferences() async {
    await _storage.delete(AppConstants.keyThemeMode);
    await _storage.delete(AppConstants.keyLanguage);
    await _storage.delete(AppConstants.keyNotificationsEnabled);
    await _storage.delete(AppConstants.keyTripAlertsEnabled);
    await _storage.delete(AppConstants.keyKeepScreenOn);
    await _storage.delete(AppConstants.keyLastSync);
    await _storage.delete(AppConstants.keyFirstLaunch);
  }
}
