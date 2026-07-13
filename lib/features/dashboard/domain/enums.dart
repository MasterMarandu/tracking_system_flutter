enum TripState {
  noTrip,
  preTrip,
  inRoute,
  geofenceEntry,
  delivering,
  completed,
  paused,
}

enum DeliveryStep {
  confirmArrival,
  scanPackages,
  takePhoto,
  captureSignature,
  enterOTP,
  finalizeDelivery,
}

enum ChecklistStatus { pending, inProgress, completed, withObservations }

enum DeliveryOutcome { complete, partial, withIncident }
