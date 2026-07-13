import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/features/dashboard/domain/enums.dart';

class TripStateController extends Notifier<TripState> {
  static const Map<TripState, Set<TripState>> _validTransitions = {
    TripState.noTrip: {TripState.preTrip},
    TripState.preTrip: {TripState.inRoute},
    TripState.inRoute: {
      TripState.geofenceEntry,
      TripState.paused,
      TripState.completed,
    },
    TripState.geofenceEntry: {TripState.delivering, TripState.inRoute},
    TripState.delivering: {TripState.inRoute, TripState.completed},
    TripState.paused: {TripState.inRoute},
    TripState.completed: {TripState.noTrip},
  };

  @override
  TripState build() => TripState.noTrip;

  void setState(TripState newState) {
    if (_validTransitions[state]?.contains(newState) ?? false) {
      state = newState;
    } else {
      debugPrint('Blocked invalid transition: $state → $newState');
    }
  }

  void forceState(TripState newState) {
    state = newState;
  }
}

final tripStateProvider =
    NotifierProvider<TripStateController, TripState>(
  TripStateController.new,
);
