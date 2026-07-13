import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of a delivery operation
class DeliveryResult {
  final bool success;
  final String? error;
  final bool tripCompleted;
  final int? stopsProgress;
  final int? totalStops;

  const DeliveryResult({
    required this.success,
    this.error,
    this.tripCompleted = false,
    this.stopsProgress,
    this.totalStops,
  });

  factory DeliveryResult.fromJson(Map<String, dynamic> json) {
    return DeliveryResult(
      success: json['success'] == true,
      error: json['error'] as String?,
      tripCompleted: json['trip_completed'] == true,
      stopsProgress: json['stops_progress'] as int?,
      totalStops: json['total_stops'] as int?,
    );
  }

  static const empty = DeliveryResult(success: false, error: 'No data');
}

/// Service for delivery-related operations
class DeliveryService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Singleton instance
  static final DeliveryService _instance = DeliveryService._();
  static DeliveryService get instance => _instance;
  DeliveryService._();

  /// Complete a delivery checkpoint
  /// 
  /// [checkpointId] - The checkpoint ID to complete
  /// [tripId] - The trip ID
  /// [stopId] - The stop ID (parada)
  /// [outcome] - 'complete' or 'incident'
  /// [incidentReason] - Optional reason if outcome is 'incident'
  /// [packagesDelivered] - Number of packages delivered
  Future<DeliveryResult> completeDelivery({
    required String checkpointId,
    required String tripId,
    required String stopId,
    String outcome = 'complete',
    String? incidentReason,
    int packagesDelivered = 0,
  }) async {
    try {
      final response = await _client.rpc('complete_delivery', params: {
        'p_checkpoint_id': checkpointId,
        'p_trip_id': tripId,
        'p_stop_id': stopId,
        'p_outcome': outcome,
        'p_incident_reason': incidentReason,
        'p_packages_delivered': packagesDelivered,
      });

      if (response == null) {
        return const DeliveryResult(
          success: false,
          error: 'No response from server',
        );
      }

      return DeliveryResult.fromJson(response as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      debugPrint('completeDelivery PostgrestException: ${e.message}');
      return DeliveryResult(success: false, error: e.message);
    } catch (e) {
      debugPrint('completeDelivery error: $e');
      return DeliveryResult(success: false, error: e.toString());
    }
  }

  /// Verify OTP for a delivery checkpoint
  /// 
  /// [checkpointId] - The checkpoint ID
  /// [otpCode] - The OTP code to verify
  Future<DeliveryResult> verifyOtp({
    required String checkpointId,
    required String otpCode,
  }) async {
    try {
      final response = await _client.rpc('verify_delivery_otp', params: {
        'p_checkpoint_id': checkpointId,
        'p_otp_code': otpCode,
      });

      if (response == null) {
        return const DeliveryResult(
          success: false,
          error: 'No response from server',
        );
      }

      return DeliveryResult.fromJson(response as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      debugPrint('verifyOtp PostgrestException: ${e.message}');
      return DeliveryResult(success: false, error: e.message);
    } catch (e) {
      debugPrint('verifyOtp error: $e');
      return DeliveryResult(success: false, error: e.toString());
    }
  }

  /// Report an incident at a checkpoint
  Future<DeliveryResult> reportIncident({
    required String checkpointId,
    required String tripId,
    required String stopId,
    required String reason,
  }) {
    return completeDelivery(
      checkpointId: checkpointId,
      tripId: tripId,
      stopId: stopId,
      outcome: 'incident',
      incidentReason: reason,
    );
  }
}
