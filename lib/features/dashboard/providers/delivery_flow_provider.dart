import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/features/dashboard/domain/enums.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap.dart';
import 'package:tracking_system_app/features/sync/domain/sync_engine.dart';
import 'package:tracking_system_app/features/sync/data/sync_queue.dart';

class DeliveryFlowState {
  final DeliveryStep currentStep;
  final Set<String> scannedPackageIds;
  final List<List<Offset>> signatureStrokes;
  final bool photoTaken;
  final bool otpVerified;
  final bool otpVerifying;
  final int otpAttempts;
  final bool otpFormatValid;
  final DeliveryOutcome outcome;
  final String? incidentReason;

  const DeliveryFlowState({
    this.currentStep = DeliveryStep.confirmArrival,
    this.scannedPackageIds = const {},
    this.signatureStrokes = const [],
    this.photoTaken = false,
    this.otpVerified = false,
    this.otpVerifying = false,
    this.otpAttempts = 0,
    this.otpFormatValid = false,
    this.outcome = DeliveryOutcome.complete,
    this.incidentReason,
  });

  bool get isBlocked => otpAttempts >= 3 && !otpVerified;

  DeliveryFlowState copyWith({
    DeliveryStep? currentStep,
    Set<String>? scannedPackageIds,
    List<List<Offset>>? signatureStrokes,
    bool? photoTaken,
    bool? otpVerified,
    bool? otpVerifying,
    int? otpAttempts,
    bool? otpFormatValid,
    DeliveryOutcome? outcome,
    String? incidentReason,
    bool clearIncidentReason = false,
  }) {
    return DeliveryFlowState(
      currentStep: currentStep ?? this.currentStep,
      scannedPackageIds: scannedPackageIds ?? this.scannedPackageIds,
      signatureStrokes: signatureStrokes ?? this.signatureStrokes,
      photoTaken: photoTaken ?? this.photoTaken,
      otpVerified: otpVerified ?? this.otpVerified,
      otpVerifying: otpVerifying ?? this.otpVerifying,
      otpAttempts: otpAttempts ?? this.otpAttempts,
      otpFormatValid: otpFormatValid ?? this.otpFormatValid,
      outcome: outcome ?? this.outcome,
      incidentReason:
          clearIncidentReason ? null : (incidentReason ?? this.incidentReason),
    );
  }
}

class DeliveryFlowController extends Notifier<DeliveryFlowState> {
  @override
  DeliveryFlowState build() => const DeliveryFlowState();

  void advanceStep() {
    final steps = DeliveryStep.values;
    final currentIndex = steps.indexOf(state.currentStep);
    if (currentIndex >= steps.length - 1) return;
    state = state.copyWith(currentStep: steps[currentIndex + 1]);
  }

  void togglePackageScan(String packageId) {
    final updated = Set<String>.from(state.scannedPackageIds);
    if (updated.contains(packageId)) {
      updated.remove(packageId);
    } else {
      updated.add(packageId);
    }
    state = state.copyWith(scannedPackageIds: updated);
  }

  void setPhotoTaken(bool value) {
    state = state.copyWith(photoTaken: value);
  }

  void startNewStroke(Offset point) {
    final strokes = List<List<Offset>>.from(state.signatureStrokes)
      ..add([point]);
    state = state.copyWith(signatureStrokes: strokes);
  }

  void extendLastStroke(Offset point) {
    if (state.signatureStrokes.isEmpty) return;
    final strokes = List<List<Offset>>.from(state.signatureStrokes);
    strokes.last = [...strokes.last, point];
    state = state.copyWith(signatureStrokes: strokes);
  }

  void clearSignature() {
    state = state.copyWith(signatureStrokes: []);
  }

  void setOtpFormatValid(bool valid) {
    state = state.copyWith(otpFormatValid: valid, otpVerified: false);
  }

  Future<bool> verifyOtp(String code) async {
    state = state.copyWith(otpVerifying: true);

    try {
      await Future.delayed(const Duration(milliseconds: 800));
      final success = code == '123456';

      state = state.copyWith(
        otpVerifying: false,
        otpAttempts: success ? state.otpAttempts : state.otpAttempts + 1,
        otpVerified: success,
      );

      return success;
    } catch (_) {
      state = state.copyWith(otpVerifying: false);
      return false;
    }
  }

  void setOutcome(DeliveryOutcome outcome, {String? reason}) {
    state = state.copyWith(
      outcome: outcome,
      incidentReason: reason,
      clearIncidentReason: reason == null && outcome == DeliveryOutcome.complete,
    );
  }

  Future<void> completeDelivery({
    required String tripId,
    required String? stopId,
    required String? checkpointId,
    required int packagesDelivered,
  }) async {
    await ref.read(syncEngineProvider.notifier).enqueueOperation(
          SyncOperationType.completeDelivery,
          {
            'tripId': tripId,
            if (stopId != null) 'stopId': stopId,
            if (checkpointId != null) 'checkpointId': checkpointId,
            'outcome': state.outcome.name,
            'packagesDelivered': packagesDelivered,
            if (state.incidentReason != null)
              'incidentReason': state.incidentReason,
            'scannedPackages': state.scannedPackageIds.toList(),
            'photoTaken': state.photoTaken,
            'signatureCaptured':
                state.signatureStrokes.expand((s) => s).isNotEmpty,
            'otpVerified': state.otpVerified,
            'completedAt': DateTime.now().toIso8601String(),
          },
        );

    reset();
  }

  void reset() {
    state = const DeliveryFlowState();
  }

  void restoreFromSession(BootstrapDeliverySession session) {
    state = DeliveryFlowState(
      currentStep: DeliveryStep.values.firstWhere(
        (s) => s.name == session.currentStep,
        orElse: () => DeliveryStep.confirmArrival,
      ),
      scannedPackageIds: Set<String>.from(session.scannedPackageIds),
      photoTaken: session.photoCompleted,
      otpVerified: session.otpVerified,
      signatureStrokes: session.signatureCompleted
          ? [[const Offset(0, 0), const Offset(10, 10)]]
          : [],
    );
  }
}

final deliveryFlowProvider =
    NotifierProvider<DeliveryFlowController, DeliveryFlowState>(
  DeliveryFlowController.new,
);
