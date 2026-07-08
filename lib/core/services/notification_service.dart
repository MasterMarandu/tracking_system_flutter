import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static NotificationService? _instance;
  static NotificationService get instance => _instance ??= NotificationService._();
  
  NotificationService._();
  
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }
  
  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap
    final payload = response.payload;
    if (payload != null) {
      // Navigate based on payload
    }
  }
  
  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }
  
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String channelId = 'tracking_system',
    String channelName = 'Tracking System',
    String channelDescription = 'GPS Tracking notifications',
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _plugin.show(id, title, body, details, payload: payload);
  }
  
  Future<void> showTripNotification({
    required String title,
    required String body,
    String? tripId,
  }) async {
    await showNotification(
      id: 1,
      title: title,
      body: body,
      payload: 'trip:$tripId',
      channelId: 'trip_updates',
      channelName: 'Trip Updates',
      channelDescription: 'Trip status notifications',
    );
  }
  
  Future<void> showDeliveryNotification({
    required String title,
    required String body,
    String? packageId,
  }) async {
    await showNotification(
      id: 2,
      title: title,
      body: body,
      payload: 'delivery:$packageId',
      channelId: 'delivery_updates',
      channelName: 'Delivery Updates',
      channelDescription: 'Delivery status notifications',
    );
  }
  
  Future<void> showIncidentNotification({
    required String title,
    required String body,
    String? incidentId,
  }) async {
    await showNotification(
      id: 3,
      title: title,
      body: body,
      payload: 'incident:$incidentId',
      channelId: 'incidents',
      channelName: 'Incidents',
      channelDescription: 'Incident notifications',
    );
  }
  
  Future<void> showMessageNotification({
    required String title,
    required String body,
    String? chatId,
  }) async {
    await showNotification(
      id: 4,
      title: title,
      body: body,
      payload: 'chat:$chatId',
      channelId: 'messages',
      channelName: 'Messages',
      channelDescription: 'Chat message notifications',
    );
  }
  
  Future<void> showTrackingNotification({
    required String title,
    required String body,
  }) async {
    await showNotification(
      id: 5,
      title: title,
      body: body,
      channelId: 'tracking',
      channelName: 'Tracking',
      channelDescription: 'GPS tracking notifications',
    );
  }
  
  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }
  
  Future<void> cancelAllNotifications() async {
    await _plugin.cancelAll();
  }
  
  Future<int> getPendingNotificationCount() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.length;
  }
}
