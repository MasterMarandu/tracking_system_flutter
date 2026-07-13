import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/features/dashboard/domain/enums.dart';
import 'package:tracking_system_app/features/dashboard/domain/models.dart';
import 'package:tracking_system_app/features/dashboard/presentation/widgets/common_widgets.dart';
import 'package:tracking_system_app/features/dashboard/presentation/widgets/signature_painter.dart';
import 'package:tracking_system_app/features/dashboard/providers/delivery_flow_provider.dart';

Future<void> showDeliverySheet(
  BuildContext context, {
  required TripData tripData,
  required String tripId,
  required String? stopId,
  required String? checkpointId,
  required VoidCallback onDeliveryCompleted,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) => _DeliverySheet(
      tripData: tripData,
      tripId: tripId,
      stopId: stopId,
      checkpointId: checkpointId,
      onDeliveryCompleted: onDeliveryCompleted,
    ),
  );
}

class _DeliverySheet extends ConsumerStatefulWidget {
  final TripData tripData;
  final String tripId;
  final String? stopId;
  final String? checkpointId;
  final VoidCallback onDeliveryCompleted;

  const _DeliverySheet({
    required this.tripData,
    required this.tripId,
    required this.stopId,
    required this.checkpointId,
    required this.onDeliveryCompleted,
  });

  @override
  ConsumerState<_DeliverySheet> createState() => _DeliverySheetState();
}

class _DeliverySheetState extends ConsumerState<_DeliverySheet> {
  final _otpController = TextEditingController();
  bool _otpFormatValid = false;
  bool _otpVerified = false;
  bool _otpVerifying = false;
  int _otpAttempts = 0;

  List<String> get _packageIds =>
      List.generate(widget.tripData.packages, (i) => 'TRK-2026-${7000 + i}');

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deliveryState = ref.watch(deliveryFlowProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: ScrollableColumn(
        children: [
          _buildDeliveryStepContent(theme, deliveryState),
        ],
      ),
    );
  }

  Widget _buildDeliveryStepContent(
      ThemeData theme, DeliveryFlowState deliveryState) {
    switch (deliveryState.currentStep) {
      case DeliveryStep.confirmArrival:
        return _buildConfirmArrivalStep(theme);
      case DeliveryStep.scanPackages:
        return _buildScanStep(theme);
      case DeliveryStep.takePhoto:
        return _buildPhotoStep(theme);
      case DeliveryStep.captureSignature:
        return _buildSignatureStep(theme);
      case DeliveryStep.enterOTP:
        return _buildOTPStep(theme);
      case DeliveryStep.finalizeDelivery:
        return _buildFinalizeStep(theme);
    }
  }

  Widget _buildDeliveryProgress(int currentStep, ThemeData theme) {
    const steps = ['Llegada', 'Escaneo', 'Foto', 'Firma', 'OTP', 'Finalizar'];
    return Row(
      children: List.generate(steps.length, (i) {
        final isCompleted = i < currentStep;
        final isCurrent = i == currentStep;
        return Expanded(
          child: Row(
            children: [
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color: isCompleted ? Colors.green : Colors.grey.shade200,
                  ),
                ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? Colors.green
                      : isCurrent
                          ? theme.colorScheme.primary
                          : Colors.grey.shade200,
                ),
                child: Icon(
                  isCompleted ? Icons.check : Icons.circle,
                  size: 14,
                  color: isCompleted || isCurrent ? Colors.white : Colors.grey,
                ),
              ),
              if (i < steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    color:
                        i < currentStep ? Colors.green : Colors.grey.shade200,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildConfirmArrivalStep(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  const Icon(Icons.location_on, color: Colors.green, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Confirmar llegada',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Has llegado al destino',
                      style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.business, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.tripData.nextStopName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(widget.tripData.nextStopAddress,
                        style: const TextStyle(fontSize: 12)),
                    Text(widget.tripData.customerName,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1565C0))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () =>
              ref.read(deliveryFlowProvider.notifier).advanceStep(),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('INICIAR ENTREGA'),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _buildScanStep(ThemeData theme) {
    final deliveryState = ref.watch(deliveryFlowProvider);
    final allScanned =
        deliveryState.scannedPackageIds.length >= _packageIds.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeliveryProgress(1, theme),
        const SizedBox(height: 20),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.primary, width: 2),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_scanner, size: 64, color: Colors.white70),
                SizedBox(height: 8),
                Text('Escanea el código de barras',
                    style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ..._packageIds.map(
          (id) => CheckboxListTile(
            value: deliveryState.scannedPackageIds.contains(id),
            onChanged: (selected) {
              ref.read(deliveryFlowProvider.notifier).togglePackageScan(id);
            },
            title: Text(id),
            subtitle: const Text('Paquete estándar'),
            controlAffinity: ListTileControlAffinity.trailing,
            activeColor: Colors.green,
            dense: true,
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed:
              allScanned ? () => ref.read(deliveryFlowProvider.notifier).advanceStep() : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            disabledBackgroundColor: Colors.grey.shade300,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(
            'CONTINUAR (${deliveryState.scannedPackageIds.length}/${_packageIds.length})',
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            ref.read(deliveryFlowProvider.notifier).setOutcome(
                  DeliveryOutcome.partial,
                  reason: 'Paquetes no escaneados reportados como faltantes',
                );
            ref.read(deliveryFlowProvider.notifier).advanceStep();
          },
          child: const Text('Reportar paquete faltante'),
        ),
      ],
    );
  }

  Widget _buildPhotoStep(ThemeData theme) {
    final deliveryState = ref.watch(deliveryFlowProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeliveryProgress(2, theme),
        const SizedBox(height: 20),
        InkWell(
          onTap: () =>
              ref.read(deliveryFlowProvider.notifier).setPhotoTaken(true),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: deliveryState.photoTaken
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: deliveryState.photoTaken
                    ? Colors.green
                    : Colors.grey.shade300,
                width: 2,
              ),
            ),
            child: deliveryState.photoTaken
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check,
                            size: 40, color: Colors.green),
                      ),
                      const SizedBox(height: 8),
                      const Text('Foto capturada',
                          style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold)),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.camera_alt,
                          size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text('Toma una foto del paquete',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Toma una foto del paquete entregado como evidencia',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: deliveryState.photoTaken
              ? () => ref.read(deliveryFlowProvider.notifier).advanceStep()
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            disabledBackgroundColor: Colors.grey.shade300,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('CONTINUAR'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            ref.read(deliveryFlowProvider.notifier).setOutcome(
                  DeliveryOutcome.withIncident,
                  reason: 'Foto de evidencia omitida por el conductor',
                );
            ref.read(deliveryFlowProvider.notifier).advanceStep();
          },
          child: const Text('Saltar'),
        ),
      ],
    );
  }

  Widget _buildSignatureStep(ThemeData theme) {
    final deliveryState = ref.watch(deliveryFlowProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeliveryProgress(3, theme),
        const SizedBox(height: 16),
        const Text('Firma del receptor',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: GestureDetector(
            onPanStart: (details) {
              ref
                  .read(deliveryFlowProvider.notifier)
                  .startNewStroke(details.localPosition);
            },
            onPanUpdate: (details) {
              ref
                  .read(deliveryFlowProvider.notifier)
                  .extendLastStroke(details.localPosition);
            },
            behavior: HitTestBehavior.opaque,
            child: CustomPaint(
              painter: SignaturePainter(deliveryState.signatureStrokes),
              size: const Size(double.infinity, 160),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () =>
                  ref.read(deliveryFlowProvider.notifier).clearSignature(),
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Limpiar'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: deliveryState.signatureStrokes
                  .expand((s) => s)
                  .isNotEmpty
              ? () => ref.read(deliveryFlowProvider.notifier).advanceStep()
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            disabledBackgroundColor: Colors.grey.shade300,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('CONFIRMAR FIRMA'),
        ),
      ],
    );
  }

  Widget _buildOTPStep(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeliveryProgress(4, theme),
        const SizedBox(height: 20),
        const Icon(Icons.pin, size: 48, color: Color(0xFF1565C0)),
        const SizedBox(height: 12),
        const Text('Código de verificación',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Solicita el código OTP al receptor',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        const SizedBox(height: 20),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 8),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: theme.colorScheme.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (v) {
            setState(() {
              _otpFormatValid = v.length == 6;
              _otpVerified = false;
            });
          },
        ),
        if (_otpFormatValid && !_otpVerified) ...[
          const SizedBox(height: 12),
          Text(
            _otpAttempts > 0
                ? 'Código incorrecto. ${3 - _otpAttempts} intentos restantes'
                : '',
            style: TextStyle(
                fontSize: 12, color: Colors.red.shade700),
            textAlign: TextAlign.center,
          ),
        ],
        if (_otpVerified) ...[
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 6),
              Text('Código verificado',
                  style: TextStyle(color: Colors.green)),
            ],
          ),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _otpFormatValid && !_otpVerifying
              ? () => _verifyOtp()
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            disabledBackgroundColor: Colors.grey.shade300,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _otpVerifying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('VERIFICAR'),
        ),
        const SizedBox(height: 8),
        if (_otpVerified)
          ElevatedButton.icon(
            onPressed: () =>
                ref.read(deliveryFlowProvider.notifier).advanceStep(),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('CONTINUAR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _otpAttempts >= 3 ? () => _showOtpExceptionDialog() : null,
          child: const Text('Reportar OTP no disponible'),
        ),
      ],
    );
  }

  Future<void> _verifyOtp() async {
    setState(() => _otpVerifying = true);

    await Future.delayed(const Duration(milliseconds: 800));
    final success = _otpController.text == '123456';

    if (!mounted) return;
    setState(() {
      _otpVerifying = false;
      if (!success) _otpAttempts++;
      _otpVerified = success;
    });

    if (!success && _otpAttempts >= 3 && mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Código bloqueado'),
          content: const Text(
              'Has excedido el límite de intentos. Contacta a soporte.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showOtpExceptionDialog() async {
    final reasonController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('OTP no disponible'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'El receptor no tiene código OTP. Esta acción será registrada como excepción.'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Motivo (obligatorio)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx, reasonController.text.trim().isNotEmpty),
              child: const Text('Registrar excepción'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        ref.read(deliveryFlowProvider.notifier).setOutcome(
              DeliveryOutcome.withIncident,
              reason: reasonController.text,
            );
        ref.read(deliveryFlowProvider.notifier).advanceStep();
      }
    } finally {
      reasonController.dispose();
    }
  }

  Widget _buildFinalizeStep(ThemeData theme) {
    final deliveryState = ref.watch(deliveryFlowProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeliveryProgress(5, theme),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle,
                    size: 48, color: Colors.green),
              ),
              const SizedBox(height: 16),
              const Text('Entrega completada',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '${widget.tripData.packages} paquetes entregados a ${widget.tripData.customerName}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
              if (deliveryState.outcome != DeliveryOutcome.complete &&
                  deliveryState.incidentReason != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber,
                          color: Colors.orange, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          deliveryState.incidentReason!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => _finalizeDelivery(),
          icon: const Icon(Icons.check),
          label: const Text('FINALIZAR ENTREGA'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  Future<void> _finalizeDelivery() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar entrega'),
        content: const Text(
          '¿Confirmas que la entrega fue completada correctamente? '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Revisar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(deliveryFlowProvider.notifier).completeDelivery(
            tripId: widget.tripId,
            stopId: widget.stopId,
            checkpointId: widget.checkpointId,
            packagesDelivered: widget.tripData.packages,
          );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onDeliveryCompleted();
    }
  }
}
