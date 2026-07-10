import 'package:tracking_system_app/core/config/supabase_config.dart';
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

    final viajesConductor = await SupabaseConfig.client
        .from('operations_viajes_conductores')
        .select('viaje_id')
        .eq('conductor_id', conductorId)
        .filter('deleted_at', 'is', null)
        .order('fecha_asignacion', ascending: false)
        .limit(1);

    BootstrapTrip? trip;
    BootstrapChecklist? checklist;

    if (viajesConductor.isNotEmpty) {
      final viajeId = viajesConductor.first['viaje_id'] as String;

      final viajes = await SupabaseConfig.client
          .from(SupabaseConfig.tableViajes)
          .select()
          .eq('id', viajeId)
          .filter('deleted_at', 'is', null)
          .filter(
              'estado', 'in', '("programado","en_curso","pausado","aceptado")')
          .limit(1);

      if (viajes.isNotEmpty) {
        final v = viajes.first;
        trip = BootstrapTrip(
          id: v['id'] as String,
          code: v['codigo'] as String,
          status: v['estado'] as String,
          departureTime: v['hora_real_salida']?.toString(),
          estimatedArrival: v['hora_programada_llegada']?.toString(),
          totalDistance: (v['km_estimados'] as num?)?.toDouble(),
          remainingDistance: (v['distancia_real_km'] as num?)?.toDouble(),
          stopsProgress: null,
          totalStops: null,
          packagesRemaining: null,
          progressPercent: null,
        );

        final checklists = await SupabaseConfig.client
            .from('fleet_checklists')
            .select()
            .eq('viaje_id', viajeId)
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
      currentStop: null,
      device: const BootstrapDevice(),
    );
  }
}
