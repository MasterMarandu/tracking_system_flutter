import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:tracking_system_app/core/services/gps_service.dart';
import 'package:tracking_system_app/core/services/log_service.dart';

class BackgroundService {
  static BackgroundService? _instance;
  static BackgroundService get instance => _instance ??= BackgroundService._();
  
  BackgroundService._();
  
  final FlutterBackgroundService _service = FlutterBackgroundService();
  bool _isRunning = false;
  bool get isRunning => _isRunning;
  
  Future<void> initialize() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'routio_tracking',
        initialNotificationTitle: 'Routio',
        initialNotificationContent: 'Seguimiento GPS activo',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }
  
  Future<void> start() async {
    if (_isRunning) return;
    
    await _service.startService();
    _isRunning = true;
    LogService.instance.info('Background service started');
  }
  
  Future<void> stop() async {
    if (!_isRunning) return;
    
    _service.invoke('stop');
    _isRunning = false;
    LogService.instance.info('Background service stopped');
  }
  
  void onTrackingDataUpdate(Function(Map<String, dynamic>) callback) {
    _service.on('trackingData').listen((event) {
      if (event != null) {
        callback(Map<String, dynamic>.from(event));
      }
    });
  }
  
  void onStatusUpdate(Function(Map<String, dynamic>) callback) {
    _service.on('statusUpdate').listen((event) {
      if (event != null) {
        callback(Map<String, dynamic>.from(event));
      }
    });
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.on('stop').listen((event) {
      service.stopSelf();
    });
  }
  
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // Update notification
        service.setForegroundNotificationInfo(
          title: 'Routio',
          content: 'GPS activo · ${DateTime.now().toString().substring(11, 19)}',
        );
      }
    }
    
    try {
      final position = await GpsService.instance.getCurrentPosition();
      
      if (position != null) {
        final data = {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'speed': position.speed,
          'altitude': position.altitude,
          'heading': position.heading,
          'timestamp': DateTime.now().toIso8601String(),
        };
        
        service.invoke('trackingData', data);
        
        LogService.instance.debug('GPS: ${position.latitude}, ${position.longitude}');
      }
    } catch (e) {
      LogService.instance.error('Background GPS error', e);
    }
  });
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  return true;
}
