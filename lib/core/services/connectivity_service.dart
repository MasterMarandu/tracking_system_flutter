import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static ConnectivityService? _instance;
  static ConnectivityService get instance => _instance ??= ConnectivityService._();
  
  ConnectivityService._();
  
  final Connectivity _connectivity = Connectivity();
  final StreamController<ConnectionStatus> _controller = StreamController<ConnectionStatus>.broadcast();
  
  Stream<ConnectionStatus> get connectionStream => _controller.stream;
  
  ConnectionStatus _currentStatus = ConnectionStatus.unknown;
  ConnectionStatus get currentStatus => _currentStatus;
  
  bool get isConnected => _currentStatus == ConnectionStatus.connected;
  
  Future<void> initialize() async {
    _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    await checkConnection();
  }
  
  Future<void> checkConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);
    } catch (e) {
      _currentStatus = ConnectionStatus.unknown;
      _controller.add(_currentStatus);
    }
  }
  
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      _currentStatus = ConnectionStatus.disconnected;
    } else {
      _currentStatus = ConnectionStatus.connected;
    }
    _controller.add(_currentStatus);
  }
  
  void dispose() {
    _controller.close();
  }
}

enum ConnectionStatus {
  unknown,
  connected,
  disconnected,
}
