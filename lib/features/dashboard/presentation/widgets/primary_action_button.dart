import 'package:flutter/material.dart';
import 'package:tracking_system_app/features/dashboard/domain/enums.dart';

class PrimaryActionButton extends StatelessWidget {
  final TripState tripState;
  final DeliveryStep deliveryStep;
  final ThemeData theme;
  final bool canStartTrip;
  final int totalStops;
  final VoidCallback onPreTripChecklist;
  final VoidCallback onStartTrip;
  final VoidCallback onNavigate;
  final VoidCallback onArriveManually;
  final VoidCallback onStartDelivery;
  final VoidCallback onContinueDelivery;
  final VoidCallback onPause;
  final VoidCallback onResume;

  const PrimaryActionButton({
    super.key,
    required this.tripState,
    required this.deliveryStep,
    required this.theme,
    required this.canStartTrip,
    required this.totalStops,
    required this.onPreTripChecklist,
    required this.onStartTrip,
    required this.onNavigate,
    required this.onArriveManually,
    required this.onStartDelivery,
    required this.onContinueDelivery,
    required this.onPause,
    required this.onResume,
  });

  static String _deliveryStepLabel(DeliveryStep step) {
    switch (step) {
      case DeliveryStep.confirmArrival:
        return 'CONTINUAR: CONFIRMAR LLEGADA';
      case DeliveryStep.scanPackages:
        return 'CONTINUAR: ESCANEAR PAQUETES';
      case DeliveryStep.takePhoto:
        return 'CONTINUAR: TOMAR FOTO';
      case DeliveryStep.captureSignature:
        return 'CONTINUAR: OBTENER FIRMA';
      case DeliveryStep.enterOTP:
        return 'CONTINUAR: VERIFICAR OTP';
      case DeliveryStep.finalizeDelivery:
        return 'CONTINUAR: FINALIZAR ENTREGA';
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (tripState) {
      case TripState.noTrip:
        return const SizedBox.shrink();
      case TripState.preTrip:
        // Un solo CTA contextual (no dos botones grandes para una decisión):
        //  - checklist incompleto → "Completar checklist" (no inicia el viaje).
        //  - checklist aprobado   → "Iniciar viaje" (decisión separada, explícita).
        if (!canStartTrip) {
          return Column(
            children: [
              ElevatedButton.icon(
                onPressed: onPreTripChecklist,
                icon: const Icon(Icons.assignment),
                label: const Text('COMPLETAR CHECKLIST'),
                style: _buttonStyle(Colors.orange),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Necesario antes de iniciar el viaje',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            ],
          );
        }
        return Column(
          children: [
            ElevatedButton.icon(
              onPressed: onStartTrip,
              icon: const Icon(Icons.play_arrow),
              label: const Text('INICIAR VIAJE'),
              style: _buttonStyle(Colors.green),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Revisión previa completada',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
          ],
        );
      case TripState.inRoute:
        // El CTA primario avanza el estado ("Llegué a la parada"); navegar es
        // auxiliar. Verde de marca para el flujo feliz.
        return Column(
          children: [
            ElevatedButton.icon(
              onPressed: totalStops > 0 ? onArriveManually : onNavigate,
              icon: const Icon(Icons.location_on),
              label: Text(totalStops > 0 ? 'LLEGUÉ A LA PARADA' : 'NAVEGAR'),
              style: _buttonStyle(const Color(0xFF206B5C)),
            ),
            if (totalStops > 0) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('Navegar'),
              ),
            ],
          ],
        );
      case TripState.geofenceEntry:
        // Verde de marca: el naranja se reserva para alerta/incidencia/bloqueo.
        return Column(
          children: [
            ElevatedButton(
              onPressed: onStartDelivery,
              style: _buttonStyle(const Color(0xFF206B5C)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_turned_in, size: 20),
                  SizedBox(width: 10),
                  Text('CONFIRMAR ENTREGA'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
                onPressed: onNavigate,
                child: const Text('Abrir navegación')),
          ],
        );
      case TripState.delivering:
        return ElevatedButton.icon(
          onPressed: onContinueDelivery,
          icon: const Icon(Icons.pending_actions),
          label: Text(_deliveryStepLabel(deliveryStep)),
          style: _buttonStyle(Colors.purple),
        );
      case TripState.paused:
        return ElevatedButton.icon(
          onPressed: onResume,
          icon: const Icon(Icons.play_arrow),
          label: const Text('REANUDAR VIAJE'),
          style: _buttonStyle(Colors.orange),
        );
      case TripState.completed:
        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('VIAJE COMPLETADO',
                  style: TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
        );
    }
  }

  ButtonStyle _buttonStyle(Color color) {
    return ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 58),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 2,
      shadowColor: color.withValues(alpha: 0.4),
      textStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
    );
  }
}
