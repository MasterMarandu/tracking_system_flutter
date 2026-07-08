import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:tracking_system_app/core/config/constants.dart';

class GpsService {
  static GpsService? _instance;
  static GpsService get instance => _instance ??= GpsService._();
  
  GpsService._();
  
  StreamSubscription<Position>? _positionSubscription;
  final StreamController<Position> _positionController = StreamController<Position>.broadcast();
  final StreamController<GpsSignalQuality> _signalQualityController = StreamController<GpsSignalQuality>.broadcast();
  
  Stream<Position> get positionStream => _positionController.stream;
  Stream<GpsSignalQuality> get signalQualityStream => _signalQualityController.stream;
  
  Position? _lastPosition;
  Position? get lastPosition => _lastPosition;
  
  bool _isTracking = false;
  bool get isTracking => _isTracking;
  
  GpsSignalQuality _currentSignalQuality = GpsSignalQuality.none;
  GpsSignalQuality get currentSignalQuality => _currentSignalQuality;
  
  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }
    
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    
    return true;
  }
  
  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await checkPermissions();
      if (!hasPermission) return null;
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      _lastPosition = position;
      _updateSignalQuality(position);
      return position;
    } catch (e) {
      return null;
    }
  }
  
  Future<void> startTracking() async {
    if (_isTracking) return;
    
    final hasPermission = await checkPermissions();
    if (!hasPermission) return;
    
    _isTracking = true;
    
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: AppConstants.gpsDistanceFilterMeters,
        timeLimit: Duration(seconds: AppConstants.gpsIntervalMovingSeconds),
      ),
    ).listen(
      (position) {
        _lastPosition = position;
        _positionController.add(position);
        _updateSignalQuality(position);
      },
      onError: (error) {
        _updateSignalQuality(null);
      },
    );
  }
  
  Future<void> stopTracking() async {
    _isTracking = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }
  
  void _updateSignalQuality(Position? position) {
    if (position == null) {
      _currentSignalQuality = GpsSignalQuality.none;
    } else if (position.accuracy <= 5) {
      _currentSignalQuality = GpsSignalQuality.excellent;
    } else if (position.accuracy <= 10) {
      _currentSignalQuality = GpsSignalQuality.good;
    } else if (position.accuracy <= 20) {
      _currentSignalQuality = GpsSignalQuality.medium;
    } else if (position.accuracy <= 50) {
      _currentSignalQuality = GpsSignalQuality.poor;
    } else {
      _currentSignalQuality = GpsSignalQuality.weak;
    }
    _signalQualityController.add(_currentSignalQuality);
  }
  
  int getRecommendedInterval() {
    if (_lastPosition == null) return AppConstants.gpsIntervalStoppedMinutes * 60;
    
    final speed = _lastPosition!.speed * 3.6; // Convert m/s to km/h
    
    if (speed > AppConstants.gpsHighSpeedThresholdKmh) {
      return AppConstants.gpsIntervalHighSpeedSeconds;
    } else if (speed > 1) {
      return AppConstants.gpsIntervalMovingSeconds;
    } else {
      return AppConstants.gpsIntervalStoppedMinutes * 60;
    }
  }
  
  double? calculateDistanceTo(double lat, double lng) {
    if (_lastPosition == null) return null;
    
    return Geolocator.distanceBetween(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
      lat,
      lng,
    );
  }
  
  void dispose() {
    stopTracking();
    _positionController.close();
    _signalQualityController.close();
  }
}

enum GpsSignalQuality {
  none,
  weak,
  poor,
  medium,
  good,
  excellent,
  
}

extension GpsSignalQualityExtension on GpsSignalQuality {
  String get label {
    switch (this) {
      case GpsSignalQuality.none:
        return 'No Signal';
      case GpsSignalQuality.weak:
        return 'Weak';
      case GpsSignalQuality.poor:
        return 'Poor';
      case GpsSignalQuality.medium:
        return 'Medium';
      case GpsSignalQuality.good:
        return 'Good';
      case GpsSignalQuality.excellent:
        return 'Excellent';
    }
  }
  
  double get strengthPercent {
    switch (this) {
      case GpsSignalQuality.none:
        return 0.0;
      case GpsSignalQuality.weak:
        return 0.2;
      case GpsSignalQuality.poor:
        return 0.4;
      case GpsSignalQuality.medium:
        return 0.6;
      case GpsSignalQuality.good:
        return 0.8;
      case GpsSignalQuality.excellent:
        return 1.0;
    }
  }
}
