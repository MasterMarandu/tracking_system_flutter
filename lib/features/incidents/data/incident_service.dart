import 'package:flutter/foundation.dart';
import 'package:tracking_system_app/core/config/constants.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/core/pagination/page_result.dart';
import 'package:tracking_system_app/core/pagination/paged_scroll_mixin.dart';
import 'package:tracking_system_app/features/incidents/domain/incident.dart';

class IncidentService {
  static IncidentService? _instance;
  static IncidentService get instance => _instance ??= IncidentService._();
  IncidentService._();

  final _client = SupabaseConfig.client;

  Future<({String? usuarioId, String? empresaId, String? conductorId})>
      _resolveContext() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return (usuarioId: null, empresaId: null, conductorId: null);
    }
    try {
      final core = await _client
          .from('core_usuarios')
          .select('id, empresa_id')
          .eq('auth_user_id', user.id)
          .filter('deleted_at', 'is', null)
          .maybeSingle();
      if (core == null) {
        return (usuarioId: null, empresaId: null, conductorId: null);
      }
      final usuarioId = core['id'] as String?;
      final empresaId = core['empresa_id'] as String?;
      String? conductorId;
      if (usuarioId != null) {
        final cond = await _client
            .from('fleet_conductores')
            .select('id')
            .eq('usuario_id', usuarioId)
            .filter('deleted_at', 'is', null)
            .maybeSingle();
        conductorId = cond?['id'] as String?;
      }
      return (
        usuarioId: usuarioId,
        empresaId: empresaId,
        conductorId: conductorId,
      );
    } catch (e) {
      debugPrint('IncidentService context: $e');
      return (usuarioId: null, empresaId: null, conductorId: null);
    }
  }

  Future<List<String>> _tripIdsForConductor(String conductorId) async {
    try {
      final links = await _client
          .from('operations_viajes_conductores')
          .select('viaje_id')
          .eq('conductor_id', conductorId)
          .filter('deleted_at', 'is', null)
          .limit(80);
      return (links as List)
          .map((e) => e['viaje_id'] as String?)
          .whereType<String>()
          .toList();
    } catch (e) {
      debugPrint('IncidentService tripIds: $e');
      return [];
    }
  }

  /// Página de incidencias filtradas al conductor (viajes) o empresa.
  Future<PageResult<Incident>> fetchPage({
    int page = 0,
    int pageSize = AppConstants.defaultPageSize,
  }) async {
    final ctx = await _resolveContext();
    if (ctx.empresaId == null) {
      return PageResult.empty(page: page, pageSize: pageSize);
    }

    final range = PageRange.of(page, pageSize: pageSize);

    try {
      List<String>? tripFilter;
      if (ctx.conductorId != null) {
        tripFilter = await _tripIdsForConductor(ctx.conductorId!);
        // Conductor sin viajes → solo incidencias sin viaje de su empresa (propias)
      }

      var query = _client
          .from(SupabaseConfig.tableIncidencias)
          .select(
            'id, tipo, descripcion, estado, foto_url, latitud, longitud, '
            'paquete_id, viaje_id, solucion, created_at, '
            'viaje:operations_viajes(codigo), '
            'paquete:shipping_paquetes(tracking_number)',
          )
          .eq('empresa_id', ctx.empresaId!)
          .filter('deleted_at', 'is', null);

      if (tripFilter != null && tripFilter.isNotEmpty) {
        // Viajes del conductor O incidencias creadas por él sin viaje
        // PostgREST: or(viaje_id.in.(...),and(viaje_id.is.null,created_by.eq.X))
        final ids = tripFilter.take(40).join(',');
        if (ctx.usuarioId != null) {
          query = query.or(
            'viaje_id.in.($ids),and(viaje_id.is.null,created_by.eq.${ctx.usuarioId})',
          );
        } else {
          query = query.inFilter('viaje_id', tripFilter.take(40).toList());
        }
      } else if (ctx.conductorId != null && ctx.usuarioId != null) {
        // Sin viajes: solo las que creó
        query = query.eq('created_by', ctx.usuarioId!);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(range.from, range.to);

      final items = (data as List)
          .map((e) => _mapRow(Map<String, dynamic>.from(e as Map)))
          .toList();

      return PageResult(
        items: items,
        page: page,
        pageSize: pageSize,
        hasMore: items.length >= pageSize,
      );
    } catch (e) {
      debugPrint('IncidentService.fetchPage: $e');
      // Fallback simple por empresa
      try {
        final data = await _client
            .from(SupabaseConfig.tableIncidencias)
            .select(
              'id, tipo, descripcion, estado, foto_url, latitud, longitud, '
              'paquete_id, viaje_id, solucion, created_at',
            )
            .eq('empresa_id', ctx.empresaId!)
            .filter('deleted_at', 'is', null)
            .order('created_at', ascending: false)
            .range(range.from, range.to);

        final items = (data as List)
            .map((e) => _mapRow(Map<String, dynamic>.from(e as Map)))
            .toList();
        return PageResult(
          items: items,
          page: page,
          pageSize: pageSize,
          hasMore: items.length >= pageSize,
        );
      } catch (e2) {
        debugPrint('IncidentService.fetchPage fallback: $e2');
        return PageResult.empty(page: page, pageSize: pageSize);
      }
    }
  }

  /// Reportar incidencia → `delivery_incidencias`.
  Future<Incident> reportIncident({
    required IncidentType type,
    required String description,
    String? tripId,
    String? packageId,
    double? lat,
    double? lng,
    String? fotoUrl,
  }) async {
    final ctx = await _resolveContext();
    if (ctx.empresaId == null) {
      throw Exception('Sesión inválida: sin empresa');
    }

    // Si no mandan viaje, usar viaje activo del conductor
    String? resolvedTripId = tripId;
    if (resolvedTripId == null && ctx.conductorId != null) {
      final trips = await _tripIdsForConductor(ctx.conductorId!);
      if (trips.isNotEmpty) {
        // Preferir en_curso
        try {
          final active = await _client
              .from('operations_viajes')
              .select('id, estado')
              .inFilter('id', trips.take(20).toList())
              .filter('deleted_at', 'is', null);
          for (final t in active as List) {
            if (t['estado'] == 'en_curso') {
              resolvedTripId = t['id'] as String?;
              break;
            }
          }
          resolvedTripId ??= trips.first;
        } catch (_) {
          resolvedTripId = trips.first;
        }
      }
    }

    final payload = <String, dynamic>{
      'empresa_id': ctx.empresaId,
      'tipo': type.dbCode,
      'descripcion': description.trim(),
      'estado': 'abierta',
      if (resolvedTripId != null) 'viaje_id': resolvedTripId,
      if (packageId != null && packageId.isNotEmpty) 'paquete_id': packageId,
      if (lat != null) 'latitud': lat,
      if (lng != null) 'longitud': lng,
      if (fotoUrl != null) 'foto_url': fotoUrl,
      if (ctx.usuarioId != null) 'created_by': ctx.usuarioId,
    };

    final row = await _client
        .from(SupabaseConfig.tableIncidencias)
        .insert(payload)
        .select()
        .single();

    // Evento de viaje para la campana web
    if (resolvedTripId != null) {
      try {
        await _client.from('operations_viajes_eventos').insert({
          'viaje_id': resolvedTripId,
          'tipo': 'incidente',
          'descripcion': '${type.label}: ${description.trim()}',
          'metadata': {
            'incidencia_id': row['id'],
            'tipo': type.dbCode,
            'source': 'app_conductor',
          },
          if (ctx.usuarioId != null) 'usuario_id': ctx.usuarioId,
        });
      } catch (e) {
        debugPrint('IncidentService evento: $e');
      }

      try {
        await _client.from('integration_outbox').insert({
          'empresa_id': ctx.empresaId,
          'aggregate_type': 'delivery_incidencias',
          'aggregate_id': row['id'],
          'event_type': 'incidencia_reportada',
          'payload': {
            'incidencia_id': row['id'],
            'viaje_id': resolvedTripId,
            'tipo': type.dbCode,
            'descripcion': description.trim(),
            'source': 'tracking_system_flutter',
          },
          'destino': 'web',
          'status': 'pendiente',
        });
      } catch (e) {
        debugPrint('IncidentService outbox: $e');
      }
    }

    return _mapRow(Map<String, dynamic>.from(row as Map));
  }

  Incident _mapRow(Map<String, dynamic> r) {
    String? tripCode;
    final viaje = r['viaje'];
    if (viaje is Map) tripCode = viaje['codigo'] as String?;

    String? tracking;
    final paquete = r['paquete'];
    if (paquete is Map) tracking = paquete['tracking_number'] as String?;

    final created = r['created_at'] != null
        ? DateTime.tryParse(r['created_at'] as String)?.toLocal()
        : null;

    return Incident(
      id: r['id'] as String,
      type: IncidentType.fromDb(r['tipo'] as String?),
      description: (r['descripcion'] as String?) ?? '',
      date: created ?? DateTime.now(),
      status: IncidentStatus.fromDb(r['estado'] as String?),
      packageId: r['paquete_id'] as String?,
      packageTracking: tracking,
      tripId: r['viaje_id'] as String?,
      tripCode: tripCode,
      fotoUrl: r['foto_url'] as String?,
      lat: (r['latitud'] as num?)?.toDouble(),
      lng: (r['longitud'] as num?)?.toDouble(),
      solucion: r['solucion'] as String?,
    );
  }
}
