abstract class AppConstants {
  // App Info (aligned with Routio web)
  static const String appName = 'Routio';
  static const String appTagline = 'App del conductor';
  static const String appVersion = '1.0.0';
  static const String appBuildNumber = '1';
  
  // API Timeouts
  static const int connectTimeoutMs = 30000;
  static const int receiveTimeoutMs = 30000;
  static const int sendTimeoutMs = 30000;
  
  // GPS Tracking Intervals
  static const int gpsIntervalMovingSeconds = 10;
  static const int gpsIntervalHighSpeedSeconds = 5;
  static const int gpsIntervalStoppedMinutes = 5;
  static const double gpsHighSpeedThresholdKmh = 80.0;
  static const int gpsDistanceFilterMeters = 10;
  
  // Pagination (memoria acotada en listas de la app conductor)
  static const int defaultPageSize = 20;
  static const int maxPageSize = 50;
  static const int tripsPageSize = 15;
  static const int packagesPageSize = 20;
  static const int notificationsPageSize = 20;
  /// Tope de puntos GPS en memoria (trail / historial local).
  static const int maxGpsTrailPoints = 200;
  
  // Cache
  static const int cacheExpirationHours = 24;
  static const int maxCacheSizeMb = 500;
  
  // Image
  static const int imageQuality = 80;
  static const int maxImageWidth = 1920;
  static const int maxImageHeight = 1080;
  static const int maxImageSizeMb = 10;
  
  // Signature
  static const double signatureStrokeWidth = 3.0;
  static const double signatureHeight = 200;
  
  // Notification
  static const String notificationChannelId = 'routio_tracking';
  static const String notificationChannelName = 'Routio';
  static const String notificationChannelDescription = 'Seguimiento GPS y alertas de operación';
  
  // Storage Keys
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserId = 'user_id';
  static const String keyEmpresaId = 'empresa_id';
  static const String keyDriverId = 'driver_id';
  static const String keyThemeMode = 'theme_mode';
  static const String keyLanguage = 'language';
  static const String keyFirstLaunch = 'first_launch';
  static const String keyLastSync = 'last_sync';
  static const String keyNotificationsEnabled = 'notifications_enabled';
  static const String keyTripAlertsEnabled = 'trip_alerts_enabled';
  static const String keyKeepScreenOn = 'keep_screen_on';
  
  // Date Formats
  static const String dateFormat = 'dd/MM/yyyy';
  static const String timeFormat = 'HH:mm';
  static const String dateTimeFormat = 'dd/MM/yyyy HH:mm';
  static const String apiDateFormat = 'yyyy-MM-dd';
  static const String apiDateTimeFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
  
  // Regex
  static const String emailRegex = r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+';
  static const String phoneRegex = r'^\+?[0-9]{8,15}$';
  
  // Map
  static const double defaultMapZoom = 15.0;
  static const double defaultMapZoomRoute = 12.0;
  static const double geofenceDefaultRadiusMeters = 500;
  
  // Sync
  static const int syncRetryAttempts = 3;
  static const int syncRetryDelaySeconds = 5;
  static const int syncBatchSize = 50;
  
  // Security
  static const int maxLoginAttempts = 5;
  static const int lockoutDurationMinutes = 15;
  static const int sessionTimeoutMinutes = 480; // 8 hours
  static const int tokenRefreshBeforeExpiryMinutes = 5;
}
