import 'package:flutter/foundation.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/core/services/current_trip_service.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap.dart';

class DriverBootstrapService {
  static DriverBootstrapService? _instance;
  static DriverBootstrapService get instance =>
      _instance ??= DriverBootstrapService._();

  DriverBootstrapService._();

  Future<DriverBootstrap> fetchBootstrap() async {
    final data = await SupabaseConfig.client
        .rpc(SupabaseConfig.rpcGetDriverBootstrap);

    if (data == null) {
      throw Exception('Bootstrap devolvió datos nulos');
    }

    final map = data as Map<String, dynamic>;
    if (map['user'] == null) {
      throw Exception('Bootstrap sin perfil de usuario');
    }

    return DriverBootstrap.fromJson(map);
  }

  Future<DriverBootstrap> fetchBootstrapFallback() async {
    final user = SupabaseConfig.client.auth.currentUser;
    final session = SupabaseConfig.client.auth.currentSession;

    if (user == null || session == null) {
      throw Exception('No hay sesión activa');
    }

    final usuarios = await SupabaseConfig.client
        .from(SupabaseConfig.tableUsuarios)
        .select()
        .eq('auth_user_id', user.id)
        .filter('deleted_at', 'is', null)
        .eq('activo', true);

    if (usuarios.isEmpty) {
      return const DriverBootstrap(
        user: BootstrapUser(
          id: '',
          name: '',
          role: '',
          companyId: '',
          active: false,
        ),
        driver: BootstrapDriver(id: '', status: 'inactivo', license: ''),
        device: BootstrapDevice(),
      );
    }

    final usuario = usuarios.first;
    final usuarioId = usuario['id'] as String;
    final empresaId = usuario['empresa_id'] as String;

    final conductores = await SupabaseConfig.client
        .from(SupabaseConfig.tableConductores)
        .select()
        .eq('usuario_id', usuarioId)
        .filter('deleted_at', 'is', null);

    if (conductores.isEmpty) {
      return DriverBootstrap(
        user: BootstrapUser(
          id: usuarioId,
          name: '${usuario['nombre']} ${usuario['apellido']}',
          role: 'Chofer',
          companyId: empresaId,
          active: true,
        ),
        driver: const BootstrapDriver(
            id: '', status: 'sin_perfil', license: ''),
        device: const BootstrapDevice(),
      );
    }

    final conductor = conductores.first;
    final conductorId = conductor['id'] as String;

    BootstrapVehicle? vehicle;
    if (conductor['vehiculo_actual'] != null) {
      final vehiculos = await SupabaseConfig.client
          .from(SupabaseConfig.tableVehiculos)
          .select()
          .eq('id', conductor['vehiculo_actual'] as String)
          .filter('deleted_at', 'is', null);

      if (vehiculos.isNotEmpty) {
        final v = vehiculos.first;
        vehicle = BootstrapVehicle(
          id: v['id'] as String,
          plate: v['matricula'] as String,
          brand: v['marca'] as String? ?? '',
          model: v['modelo'] as String? ?? '',
        );
      }
    }

    // ── Usar CurrentTripService para obtener el viaje activo ──
    // Misma consulta que usa Mis Viajes: prioriza en_curso > pausado > programado
    final activeTrip = await CurrentTripService.instance.fetchActiveTrip();

    BootstrapTrip? trip;
    BootstrapChecklist? checklist;
    BootstrapCurrentStop? currentStop;

    if (activeTrip != null && activeTrip.conductorId == conductorId) {
      trip = BootstrapTrip(
        id: activeTrip.id,
        code: activeTrip.code,
        status: activeTrip.status,
        departureTime: activeTrip.departureTime,
        estimatedArrival: activeTrip.estimatedArrival,
        totalDistance: activeTrip.totalDistance,
        remainingDistance: activeTrip.remainingDistance,
        stopsProgress: activeTrip.completedStops,
        totalStops: activeTrip.totalStops,
        packagesRemaining: activeTrip.pendingPackages,
        progressPercent: activeTrip.progressPercent,
        origin: activeTrip.origin,
        destination: activeTrip.destination,
        routeName: activeTrip.routeName,
      );

      // Cargar currentStop (primer checkpoint incompleto)
      try {
        final checkpoints = await SupabaseConfig.client
            .from('operations_checkpoints')
            .select('id, estado, parada_id')
            .eq('viaje_id', activeTrip.id)
            .filter('deleted_at', 'is', null);

        final pendingCheckpoints = checkpoints
            .where((c) => c['estado'] == 'pendiente' || c['estado'] == 'llego')
            .toList();

        if (pendingCheckpoints.isNotEmpty) {
          final cp = pendingCheckpoints.first;
          final paradaId = cp['parada_id'] as String?;

          String stopName = 'Sin nombre';
          String stopAddress = '';
          double? lat;
          double? lng;
          int? etaMinutes;

          if (paradaId != null) {
            final paradas = await SupabaseConfig.client
                .from('operations_paradas')
                .select(
                    'nombre, direccion, latitud, longitud, eta_minutos, orden')
                .eq('id', paradaId)
                .filter('deleted_at', 'is', null)
                .limit(1);

            if (paradas.isNotEmpty) {
              final p = paradas.first;
              stopName = p['nombre'] as String? ?? 'Sin nombre';
              stopAddress = p['direccion'] as String? ?? '';
              lat = (p['latitud'] as num?)?.toDouble();
              lng = (p['longitud'] as num?)?.toDouble();
              etaMinutes = p['eta_minutos'] as int?;
            }
          }

          currentStop = BootstrapCurrentStop(
            id: paradaId ?? cp['id'] as String,
            checkpointId: cp['id'] as String,
            name: stopName,
            address: stopAddress,
            lat: lat,
            lng: lng,
            etaMinutes: etaMinutes,
            status: cp['estado'] as String,
          );
        }
      } catch (e) {
        debugPrint('Fallback: error cargando currentStop: $e');
      }

      // Checklist pre-viaje
      try {
        final checklists = await SupabaseConfig.client
            .from('fleet_checklists')
            .select()
            .eq('viaje_id', activeTrip.id)
            .eq('tipo', 'pre_viaje')
            .filter('deleted_at', 'is', null)
            .limit(1);

        if (checklists.isNotEmpty) {
          final cl = checklists.first;
          final checklistId = cl['id'] as String;

          final items = await SupabaseConfig.client
              .from('fleet_checklists_items')
              .select()
              .eq('checklist_id', checklistId)
              .filter('deleted_at', 'is', null)
              .order('orden');

          final completedCount =
              items.where((i) => i['estado'] == 'ok').length;

          checklist = BootstrapChecklist(
            id: checklistId,
            type: cl['tipo'] as String? ?? 'pre_viaje',
            status: cl['estado'] as String,
            completed: completedCount,
            total: items.length,
            items: items
                .map((i) => BootstrapChecklistItem(
                      id: i['id'] as String,
                      name: i['nombre'] as String,
                      category: i['categoria'] as String? ?? '',
                      status: i['estado'] as String,
                      observation: i['observacion'] as String?,
                    ))
                .toList(),
          );
        }
      } catch (e) {
        debugPrint('Fallback: error cargando checklist: $e');
      }
    }

    return DriverBootstrap(
      user: BootstrapUser(
        id: usuarioId,
        name: '${usuario['nombre']} ${usuario['apellido']}',
        role: 'Chofer',
        companyId: empresaId,
        active: true,
      ),
      driver: BootstrapDriver(
        id: conductorId,
        status: conductor['estado'] as String,
        license: conductor['licencia'] as String,
        vehicleId: conductor['vehiculo_actual'] as String?,
      ),
      vehicle: vehicle,
      trip: trip,
      checklist: checklist,
      currentStop: currentStop,
      device: const BootstrapDevice(),
    );
  }
}
