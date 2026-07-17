import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tracking_system_app/core/config/constants.dart';

class StorageService {
  static StorageService? _instance;
  static StorageService get instance => _instance ??= StorageService._();
  
  StorageService._();
  
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  AndroidOptions _getAndroidOptions() => const AndroidOptions(
    encryptedSharedPreferences: true,
  );
  
  IOSOptions _getIOSOptions() => const IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  
  Future<void> write(String key, String value) async {
    await _storage.write(
      key: key,
      value: value,
      aOptions: _getAndroidOptions(),
      iOptions: _getIOSOptions(),
    );
  }
  
  Future<String?> read(String key) async {
    return await _storage.read(
      key: key,
      aOptions: _getAndroidOptions(),
      iOptions: _getIOSOptions(),
    );
  }
  
  Future<void> delete(String key) async {
    await _storage.delete(
      key: key,
      aOptions: _getAndroidOptions(),
      iOptions: _getIOSOptions(),
    );
  }
  
  Future<void> deleteAll() async {
    await _storage.deleteAll(
      aOptions: _getAndroidOptions(),
      iOptions: _getIOSOptions(),
    );
  }
  
  Future<bool> containsKey(String key) async {
    return await _storage.containsKey(
      key: key,
      aOptions: _getAndroidOptions(),
      iOptions: _getIOSOptions(),
    );
  }
  
  // Token management
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await write(AppConstants.keyAccessToken, accessToken);
    await write(AppConstants.keyRefreshToken, refreshToken);
  }
  
  Future<String?> getAccessToken() async {
    return await read(AppConstants.keyAccessToken);
  }
  
  Future<String?> getRefreshToken() async {
    return await read(AppConstants.keyRefreshToken);
  }
  
  Future<void> clearTokens() async {
    await delete(AppConstants.keyAccessToken);
    await delete(AppConstants.keyRefreshToken);
  }
  
  // User data
  Future<void> saveUserId(String userId) async {
    await write(AppConstants.keyUserId, userId);
  }
  
  Future<String?> getUserId() async {
    return await read(AppConstants.keyUserId);
  }
  
  Future<void> saveEmpresaId(String empresaId) async {
    await write(AppConstants.keyEmpresaId, empresaId);
  }
  
  Future<String?> getEmpresaId() async {
    return await read(AppConstants.keyEmpresaId);
  }
  
  Future<void> saveDriverId(String driverId) async {
    await write(AppConstants.keyDriverId, driverId);
  }
  
  Future<String?> getDriverId() async {
    return await read(AppConstants.keyDriverId);
  }
  
  // Preferences
  Future<void> saveThemeMode(String mode) async {
    await write(AppConstants.keyThemeMode, mode);
  }
  
  Future<String?> getThemeMode() async {
    return await read(AppConstants.keyThemeMode);
  }
  
  Future<void> saveLanguage(String language) async {
    await write(AppConstants.keyLanguage, language);
  }
  
  Future<String?> getLanguage() async {
    return await read(AppConstants.keyLanguage);
  }
  
  Future<void> setFirstLaunch(bool value) async {
    await write(AppConstants.keyFirstLaunch, value.toString());
  }
  
  Future<bool> isFirstLaunch() async {
    final value = await read(AppConstants.keyFirstLaunch);
    return value == null || value == 'true';
  }
  
  Future<void> saveLastSync(DateTime dateTime) async {
    await write(AppConstants.keyLastSync, dateTime.toIso8601String());
  }
  
  Future<DateTime?> getLastSync() async {
    final value = await read(AppConstants.keyLastSync);
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  Future<void> saveBool(String key, bool value) async {
    await write(key, value ? 'true' : 'false');
  }

  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final value = await read(key);
    if (value == null) return defaultValue;
    return value == 'true' || value == '1';
  }

  Future<void> saveNotificationsEnabled(bool value) =>
      saveBool(AppConstants.keyNotificationsEnabled, value);

  Future<bool> getNotificationsEnabled() =>
      getBool(AppConstants.keyNotificationsEnabled, defaultValue: true);

  Future<void> saveTripAlertsEnabled(bool value) =>
      saveBool(AppConstants.keyTripAlertsEnabled, value);

  Future<bool> getTripAlertsEnabled() =>
      getBool(AppConstants.keyTripAlertsEnabled, defaultValue: true);

  Future<void> saveKeepScreenOn(bool value) =>
      saveBool(AppConstants.keyKeepScreenOn, value);

  Future<bool> getKeepScreenOn() =>
      getBool(AppConstants.keyKeepScreenOn, defaultValue: false);
}
