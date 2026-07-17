import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/core/services/notification_service.dart';
import 'package:tracking_system_app/features/dashboard/providers/bootstrap_provider.dart';
import 'package:tracking_system_app/features/profile/data/profile_service.dart';
import 'package:tracking_system_app/features/settings/data/settings_service.dart';
import 'package:tracking_system_app/features/settings/domain/app_settings.dart';
import 'package:tracking_system_app/features/sync/domain/sync_engine.dart';

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    // Carga asíncrona post-frame; estado inicial seguro
    Future.microtask(_load);
    return const AppSettings();
  }

  Future<void> _load() async {
    try {
      final loaded = await SettingsService.instance.load();
      state = loaded;
      await _applyKeepScreenOn(loaded.keepScreenOn);
    } catch (e) {
      // Mantener defaults
    }
  }

  Future<void> refresh() async {
    final loaded = await SettingsService.instance.load();
    state = loaded;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await SettingsService.instance.saveThemeMode(mode);
  }

  Future<void> setLanguage(String code) async {
    state = state.copyWith(languageCode: code);
    await SettingsService.instance.saveLanguage(code);
  }

  Future<void> setNotificationsEnabled(bool value) async {
    state = state.copyWith(notificationsEnabled: value);
    await SettingsService.instance.saveNotificationsEnabled(value);
    if (value) {
      try {
        await NotificationService.instance.requestPermission();
      } catch (_) {}
    }
  }

  Future<void> setTripAlertsEnabled(bool value) async {
    state = state.copyWith(tripAlertsEnabled: value);
    await SettingsService.instance.saveTripAlertsEnabled(value);
  }

  Future<void> setKeepScreenOn(bool value) async {
    state = state.copyWith(keepScreenOn: value);
    await SettingsService.instance.saveKeepScreenOn(value);
    await _applyKeepScreenOn(value);
  }

  Future<void> _applyKeepScreenOn(bool value) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // Keep screen awake via wakelock would need a package; use brightness hint only.
      // For now store preference; GPS/tracking services can read it later.
      if (value) {
        // no-op without wakelock package — preference is persisted for future use
      }
    } catch (_) {}
  }

  Future<void> syncNow() async {
    try {
      await ref.read(syncEngineProvider.notifier).forceRefresh();
      await SettingsService.instance.markSyncedNow();
      state = state.copyWith(lastSyncAt: DateTime.now());
    } catch (_) {
      rethrow;
    }
  }

  Future<void> resetPreferences() async {
    await SettingsService.instance.clearLocalPreferences();
    final loaded = await SettingsService.instance.load();
    state = loaded;
    await _applyKeepScreenOn(loaded.keepScreenOn);
  }

  Future<void> logout() async {
    try {
      await ref.read(syncEngineProvider.notifier).clearAll();
    } catch (_) {}
    ref.read(bootstrapProvider.notifier).clear();
    await ProfileService.instance.signOut();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// ThemeMode derivado para MaterialApp.
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(settingsProvider).themeMode;
});
